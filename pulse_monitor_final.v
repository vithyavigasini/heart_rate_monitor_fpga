// ############################################################################
//  PULSE MONITOR  --  FINAL PROJECT  (DE2-115, Cyclone IV E EP4CE115F29C7)
//  MAVLD503 Digital System Design with FPGA
// ############################################################################
//
//  pulse sensor --> ADS1115 (ADC) --> FPGA --> 1.3" OLED
//
//  The OLED shows:      BPM: 072
//                       NORMAL        (BRADY < 60, NORMAL 60-100, TACHY > 100,
//                                      WAIT 45 = countdown to the first reading)
//
//  This ONE file contains every module of the project:
//
//    top_main          the full project (top-level entity)        <- default
//    top_main_direct   backup top-level: sensor straight into the
//                      FPGA, no ADC (use only if the ADC is broken)
//    adc_reader        reads the sensor voltage from the ADS1115 (100 per second)
//    i2c_master        sends / receives bytes on the I2C wires
//    beat_detector     finds each heartbeat in the ADC readings
//    pulse_input       finds each heartbeat on a plain pin (backup only)
//    bpm_calc          BPM = beats counted in a 60 s window, and BRADY / NORMAL / TACHY
//    buzzer            tick on every beat (SW0 down) or alarm when abnormal (SW0 up)
//    oled_display      draws "BPM: 072" and the condition on the OLED
//    seven_seg         one digit on a 7-segment display
//    reset_gen         reset after programming and when KEY0 is pressed
//
//  How the modules connect (top_main):
//
//    ADS1115 --I2C--> adc_reader --sample--> beat_detector --beat--> bpm_calc
//                                                                       |
//                                                              bpm, status
//                                                                       |
//                      OLED <--I2C-- oled_display <----------------------+
//                                    seven_seg (HEX2-0) <----------------+
//                                    buzzer (header pin 5) <-- beat, status
//
//  WIRING (GPIO header JP5)      -- see WIRING.md for pictures
//    header pin 1  -> OLED SDA           header pin 2  -> OLED SCL
//    header pin 3  -> ADS1115 SDA        header pin 4  -> ADS1115 SCL
//    header pin 5  -> buzzer + (or S)    buzzer - -> GND
//    header pin 29 (3.3 V) -> breadboard + rail
//    header pin 30 (GND)   -> breadboard - rail
//    + rail -> OLED VCC, ADS1115 VDD, sensor +
//    - rail -> OLED GND, ADS1115 GND, ADS1115 ADDR, sensor -
//    sensor S -> ADS1115 A0
//    NEVER use header pin 11 (5 V).
// ############################################################################


// ============================================================
// top_main.v  --  THE FULL PROJECT
// ============================================================
//  pulse sensor -> ADS1115 -> FPGA -> OLED
//
//  adc_reader    : reads the sensor voltage 100 times a second
//  beat_detector : finds each heartbeat in those readings
//  bpm_calc      : counts beats for 60 s -> BPM = beats counted,
//                  and decides BRADY / NORMAL / TACHY
//  oled_display  : shows "BPM: 072" and the condition
//
//  Wiring (GPIO header JP5):
//    pin 1 = OLED SDA     pin 2 = OLED SCL
//    pin 3 = ADC  SDA     pin 4 = ADC  SCL
//    pin 5 = BUZZER (other buzzer leg / module GND -> GND)
//    pin 29 = 3.3 V       pin 30 = GND   (for OLED, ADC and sensor)
//
//  Board LEDs / displays:
//    HEX2-0  : BPM (same number as on the OLED), first reading after 60 s
//    LEDG0   : flashes on every heartbeat
//    LEDG1   : OLED answering        LEDR0 : OLED NOT answering
//    LEDG2   : ADC answering         LEDR1 : ADC NOT answering
//    LEDG5/6/7 : BRADY / NORMAL / TACHY
//    LEDR17-2: raw ADC number (moves with the pulse)
//    KEY0    : reset
//    SW0     : buzzer mode  (down = tick on every beat, up = alarm when BRADY/TACHY)
//    SW1     : up = buzzer muted
//    LEDG3   : on while the buzzer sounds
// ============================================================
module top_main #(
    parameter CLK_HZ     = 50_000_000,
    parameter RESET_BITS = 24,
    parameter WINDOW_SEC = 60,         // BPM counting window in seconds
    parameter OPEN_DRAIN = 0,          // see i2c_master.v
    parameter BUZZER_ACTIVE     = 0,   // 0 = passive buzzer (needs a tone), 1 = active buzzer
    parameter BUZZER_ACTIVE_LOW = 0,   // 1 = buzzer module that beeps when its pin is 0
    parameter HYST       = 300         // beat sensitivity, see beat_detector.v
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [1:0]  SW,
    inout  wire        OLED_SDA,
    inout  wire        OLED_SCL,
    inout  wire        ADC_SDA,
    inout  wire        ADC_SCL,
    output wire [17:0] LEDR,
    output wire        BUZZER,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2
);
    wire clk = CLOCK_50;
    wire rst;
    reset_gen #(.BITS(RESET_BITS)) u_reset (.clk(clk), .key0(KEY[0]), .rst(rst));

    // 1. read the sensor
    wire [15:0] sample;
    wire        new_sample, adc_ok;
    adc_reader #(.CLK_HZ(CLK_HZ), .OPEN_DRAIN(OPEN_DRAIN)) u_adc (
        .clk(clk), .rst(rst), .sda(ADC_SDA), .scl(ADC_SCL),
        .sample(sample), .new_sample(new_sample), .ok(adc_ok));

    // 2. find heartbeats
    wire        beat;
    wire [15:0] average;
    beat_detector #(.CLK_HZ(CLK_HZ), .HYST(HYST)) u_beat (
        .clk(clk), .rst(rst), .sample(sample), .new_sample(new_sample),
        .beat(beat), .average(average));

    // 3. beats -> BPM and heart condition
    wire [7:0] bpm;
    wire [1:0] status;
    wire [5:0] seconds, secs_left;
    bpm_calc #(.CLK_HZ(CLK_HZ), .WINDOW_SEC(WINDOW_SEC)) u_bpm (
        .clk(clk), .rst(rst), .beat(beat),
        .bpm(bpm), .status(status), .seconds(seconds), .secs_left(secs_left));

    // 4. show it on the OLED
    wire oled_ok;
    oled_display #(.CLK_HZ(CLK_HZ), .OPEN_DRAIN(OPEN_DRAIN)) u_oled (
        .clk(clk), .rst(rst), .bpm(bpm), .status(status), .secs_left(secs_left),
        .sda(OLED_SDA), .scl(OLED_SCL), .ok(oled_ok));

    // 5. buzzer: tick per beat (SW0 down) or alarm when abnormal (SW0 up)
    wire buzzing;
    buzzer #(.CLK_HZ(CLK_HZ), .ACTIVE(BUZZER_ACTIVE), .ACTIVE_LOW(BUZZER_ACTIVE_LOW)) u_buzz (
        .clk(clk), .rst(rst), .beat(beat), .status(status),
        .mode(SW[0]), .mute(SW[1]), .sound_on(buzzing), .pin(BUZZER));

    // ---------- board LEDs ----------
    reg [31:0] flash;                      // keeps the beat LED on for 0.1 s
    always @(posedge clk or posedge rst)
        if (rst)             flash <= 0;
        else if (beat)       flash <= CLK_HZ / 10;
        else if (flash != 0) flash <= flash - 1'b1;

    assign LEDG[0]    = (flash != 0);
    assign LEDG[1]    = oled_ok;
    assign LEDG[2]    = adc_ok;
    assign LEDG[3]    = buzzing;
    assign LEDG[4]    = 1'b0;
    assign LEDG[5]    = (status == 1);     // BRADY
    assign LEDG[6]    = (status == 2);     // NORMAL
    assign LEDG[7]    = (status == 3);     // TACHY
    assign LEDG[8]    = 1'b0;
    assign LEDR[0]    = !oled_ok;
    assign LEDR[1]    = !adc_ok;
    assign LEDR[17:2] = sample;

    // ---------- BPM on the 7-segment displays ----------
    wire [7:0] hundreds = bpm / 8'd100;
    wire [7:0] tens     = (bpm / 8'd10) % 8'd10;
    wire [7:0] ones     = bpm % 8'd10;
    wire       no_bpm   = (status == 0);
    seven_seg d2 (.digit(hundreds[3:0]), .blank(no_bpm || bpm < 100), .seg(HEX2));
    seven_seg d1 (.digit(tens[3:0]),     .blank(no_bpm || bpm < 10),  .seg(HEX1));
    seven_seg d0 (.digit(ones[3:0]),     .blank(no_bpm),              .seg(HEX0));
endmodule


// ============================================================
// top_main_direct.v  --  FULL PROJECT, backup version WITHOUT ADC
// ============================================================
//  pulse sensor S  ->  FPGA pin (header pin 3)  ->  OLED
//
//  pulse_input  : finds each heartbeat on the pin
//  bpm_calc     : counts beats for 60 s -> BPM = beats counted,
//                 and decides BRADY / NORMAL / TACHY
//  oled_display : shows "BPM: 072" and the condition
//
//  Wiring (GPIO header JP5):
//    pin 1  = OLED SDA        pin 2  = OLED SCL
//    pin 3  = sensor S (signal)
//    pin 5  = BUZZER
//    pin 29 = 3.3 V -> + rail (OLED VCC, sensor +)
//    pin 30 = GND   -> - rail (OLED GND, sensor -)
//
//  Board LEDs / displays:
//    LEDR17  : the raw sensor pin (should blink with your pulse)
//    LEDR16  : the cleaned-up signal
//    LEDG0   : flashes on every counted heartbeat
//    LEDG1   : OLED answering         LEDR0 : OLED NOT answering
//    LEDG5/6/7 : BRADY / NORMAL / TACHY
//    HEX2-0  : BPM (same as the OLED)
//    KEY0    : reset
//    SW0     : buzzer mode  (down = tick on every beat, up = alarm when BRADY/TACHY)
//    SW1     : up = buzzer muted
//    LEDG3   : on while the buzzer sounds
// ============================================================
module top_main_direct #(
    parameter CLK_HZ     = 50_000_000,
    parameter RESET_BITS = 24,
    parameter WINDOW_SEC = 60,         // BPM counting window in seconds
    parameter OPEN_DRAIN = 0,
    parameter BUZZER_ACTIVE     = 0,   // 0 = passive buzzer (needs a tone), 1 = active buzzer
    parameter BUZZER_ACTIVE_LOW = 0    // 1 = buzzer module that beeps when its pin is 0
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [1:0]  SW,
    inout  wire        OLED_SDA,
    inout  wire        OLED_SCL,
    input  wire        PULSE_IN,
    output wire [17:0] LEDR,
    output wire        BUZZER,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2
);
    wire clk = CLOCK_50;
    wire rst;
    reset_gen #(.BITS(RESET_BITS)) u_reset (.clk(clk), .key0(KEY[0]), .rst(rst));

    // 1. find heartbeats on the pin
    wire beat, level;
    pulse_input #(.CLK_HZ(CLK_HZ)) u_pulse (
        .clk(clk), .rst(rst), .pulse_pin(PULSE_IN), .beat(beat), .level(level));

    // 2. beats -> BPM and heart condition
    wire [7:0] bpm;
    wire [1:0] status;
    wire [5:0] seconds, secs_left;
    bpm_calc #(.CLK_HZ(CLK_HZ), .WINDOW_SEC(WINDOW_SEC)) u_bpm (
        .clk(clk), .rst(rst), .beat(beat),
        .bpm(bpm), .status(status), .seconds(seconds), .secs_left(secs_left));

    // 3. show it on the OLED
    wire oled_ok;
    oled_display #(.CLK_HZ(CLK_HZ), .OPEN_DRAIN(OPEN_DRAIN)) u_oled (
        .clk(clk), .rst(rst), .bpm(bpm), .status(status), .secs_left(secs_left),
        .sda(OLED_SDA), .scl(OLED_SCL), .ok(oled_ok));

    // 4. buzzer: tick per beat (SW0 down) or alarm when abnormal (SW0 up)
    wire buzzing;
    buzzer #(.CLK_HZ(CLK_HZ), .ACTIVE(BUZZER_ACTIVE), .ACTIVE_LOW(BUZZER_ACTIVE_LOW)) u_buzz (
        .clk(clk), .rst(rst), .beat(beat), .status(status),
        .mode(SW[0]), .mute(SW[1]), .sound_on(buzzing), .pin(BUZZER));

    // ---------- board LEDs ----------
    reg [31:0] flash;                      // keeps the beat LED on for 0.1 s
    always @(posedge clk or posedge rst)
        if (rst)             flash <= 0;
        else if (beat)       flash <= CLK_HZ / 10;
        else if (flash != 0) flash <= flash - 1'b1;

    assign LEDR[17]   = PULSE_IN;
    assign LEDR[16]   = level;
    assign LEDR[15:1] = 15'd0;
    assign LEDR[0]    = !oled_ok;
    assign LEDG[0]    = (flash != 0);
    assign LEDG[1]    = oled_ok;
    assign LEDG[2]    = 1'b0;
    assign LEDG[3]    = buzzing;
    assign LEDG[4]    = 1'b0;
    assign LEDG[5]    = (status == 1);     // BRADY
    assign LEDG[6]    = (status == 2);     // NORMAL
    assign LEDG[7]    = (status == 3);     // TACHY
    assign LEDG[8]    = 1'b0;

    // ---------- BPM on the 7-segment displays ----------
    wire [7:0] hundreds = bpm / 8'd100;
    wire [7:0] tens     = (bpm / 8'd10) % 8'd10;
    wire [7:0] ones     = bpm % 8'd10;
    wire       no_bpm   = (status == 0);
    seven_seg d2 (.digit(hundreds[3:0]), .blank(no_bpm || bpm < 100), .seg(HEX2));
    seven_seg d1 (.digit(tens[3:0]),     .blank(no_bpm || bpm < 10),  .seg(HEX1));
    seven_seg d0 (.digit(ones[3:0]),     .blank(no_bpm),              .seg(HEX0));
endmodule


// ============================================================
// adc_reader.v  --  reads the pulse sensor voltage from the ADS1115
// ============================================================
// The ADS1115 turns the sensor's analog voltage into a number.
// This module talks to it over I2C in a fixed list of steps:
//
//   step 0-4  : write the CONFIG register (once)
//               -> input A0, range +/-4.096 V, keep converting
//   step 5-7  : point the chip at its CONVERSION register (once)
//   step 8    : wait 10 ms                     <- loop starts here
//   step 9-12 : read 2 bytes = one sample, go back to step 8
//
// Result: `sample` (0..32767), updated 100 times a second.
//         1 count = 0.125 mV, so  millivolts = sample / 8
// If the chip stops answering, it starts again from step 0.
// ============================================================
module adc_reader #(
    parameter       CLK_HZ     = 50_000_000,
    parameter       I2C_HZ     = 100_000,
    parameter       OPEN_DRAIN = 0,
    parameter [6:0] ADDR       = 7'h48      // ADDR pin to GND -> 0x48
)(
    input  wire        clk,
    input  wire        rst,
    inout  wire        sda,
    inout  wire        scl,
    output reg  [15:0] sample,
    output reg         new_sample,  // 1-clock pulse when `sample` is updated
    output reg         ok           // 1 = the ADC answered last time
);
    // ---------- I2C master ----------
    reg        start, write, read, stop, last;
    reg  [7:0] din;
    wire [7:0] dout;
    wire       done, nack;

    i2c_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ), .OPEN_DRAIN(OPEN_DRAIN)) i2c (
        .clk(clk), .rst(rst),
        .start(start), .write(write), .read(read), .stop(stop), .last(last),
        .din(din), .dout(dout), .done(done), .nack(nack),
        .sda(sda), .scl(scl)
    );

    localparam [7:0] ADDR_WRITE = {ADDR, 1'b0};   // 0x90
    localparam [7:0] ADDR_READ  = {ADDR, 1'b1};   // 0x91
    localparam WAIT_10MS = CLK_HZ / 100;

    reg [3:0]  step;
    reg        waiting;      // 1 = command given, waiting for `done`
    reg [31:0] timer;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            step <= 0; waiting <= 0; timer <= 0;
            start <= 0; write <= 0; read <= 0; stop <= 0; last <= 0; din <= 0;
            sample <= 0; new_sample <= 0; ok <= 0;
        end else begin
            // command pulses last only 1 clock
            start <= 0; write <= 0; read <= 0; stop <= 0;
            new_sample <= 0;

            if (step == 8) begin
                // ---- step 8: wait 10 ms between samples ----
                if (timer == WAIT_10MS - 1) begin timer <= 0; step <= 9; end
                else timer <= timer + 1'b1;
            end

            else if (!waiting) begin
                // ---- give the command for this step ----
                case (step)
                    0:  begin din <= ADDR_WRITE; start <= 1; end  // talk to ADC (write)
                    1:  begin din <= 8'h01;      write <= 1; end  // -> config register
                    2:  begin din <= 8'hC2;      write <= 1; end  // A0, +/-4.096 V, continuous
                    3:  begin din <= 8'h83;      write <= 1; end  // 128 samples/s
                    4:  begin                    stop  <= 1; end
                    5:  begin din <= ADDR_WRITE; start <= 1; end  // talk to ADC (write)
                    6:  begin din <= 8'h00;      write <= 1; end  // -> conversion register
                    7:  begin                    stop  <= 1; end
                    9:  begin din <= ADDR_READ;  start <= 1; end  // talk to ADC (read)
                    10: begin last <= 0;         read  <= 1; end  // high byte
                    11: begin last <= 1;         read  <= 1; end  // low byte (last)
                    12: begin                    stop  <= 1; end
                    default: ;
                endcase
                waiting <= 1;
            end

            else if (done) begin
                // ---- the command finished: look at the result ----
                waiting <= 0;
                if ((step == 0 || step == 5 || step == 9) && nack) begin
                    ok   <= 0;                   // nobody answered
                    stop <= 1;                   // end this transfer...
                    step <= 13;                  // ...and start over
                end else begin
                    case (step)
                        9:  begin ok <= 1; step <= 10; end
                        10: begin sample[15:8] <= dout; step <= 11; end
                        11: begin sample[7:0]  <= dout; step <= 12; end
                        12: begin new_sample <= 1; step <= 8; end   // loop
                        13: step <= 0;                              // after a failed try
                        default: step <= step + 1'b1;
                    endcase
                end
            end
        end
    end
endmodule


// ============================================================
// i2c_master.v  --  sends and receives single bytes over I2C
// ============================================================
// I2C uses two wires:  SCL = clock (we always make it)
//                      SDA = data  (we drive it, except when the
//                                   chip has to answer us)
//
// How to use it: give ONE command as a 1-clock pulse, then wait
// until `done` pulses before giving the next command.
//
//   start  : START condition + send the address byte `din`
//   write  : send the byte `din`
//   read   : read one byte into `dout`
//            (last = 1 for the final byte we want)
//   stop   : STOP condition
//
// After `start` or `write`, `nack` tells us if the chip answered:
//   nack = 0  -> chip said "got it" (ACK)
//   nack = 1  -> nobody answered (wrong wiring / address / power)
//
// Timing: every bit is split into 4 quarter-steps ("ticks").
// ============================================================
module i2c_master #(
    parameter CLK_HZ     = 50_000_000,  // FPGA clock
    parameter I2C_HZ     = 100_000,     // I2C speed (100 kHz = standard)
    parameter OPEN_DRAIN = 0            // 0: FPGA drives the lines high itself
                                        // 1: lines go high only through pull-up
                                        //    resistors (textbook I2C)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       write,
    input  wire       read,
    input  wire       stop,
    input  wire       last,
    input  wire [7:0] din,
    output reg  [7:0] dout,
    output reg        done,
    output reg        nack,
    inout  wire       sda,
    inout  wire       scl
);
    // ---------- quarter-bit tick ----------
    localparam QTR = CLK_HZ / (4 * I2C_HZ);   // 125 clocks at 50 MHz / 100 kHz
    reg  [15:0] div;
    wire        tick = (div == QTR - 1);
    always @(posedge clk or posedge rst)
        if (rst)       div <= 0;
        else if (tick) div <= 0;
        else           div <= div + 1'b1;

    // ---------- the two pins ----------
    reg scl_o;      // value we want on SCL
    reg sda_o;      // value we want on SDA
    reg sda_oe;     // 1 = we drive SDA, 0 = we let go so the chip can talk

    assign scl = (OPEN_DRAIN && scl_o)               ? 1'bz : scl_o;
    assign sda = (!sda_oe || (OPEN_DRAIN && sda_o))  ? 1'bz : sda_o;

    reg sda_m, sda_in;                     // read SDA safely (2 flip-flops)
    always @(posedge clk) begin sda_m <= sda; sda_in <= sda_m; end

    // ---------- state machine ----------
    localparam IDLE = 3'd0, START = 3'd1, BITS = 3'd2, ACK = 3'd3, STOP = 3'd4;

    reg [2:0] state;
    reg [1:0] q;          // which quarter of the bit we are in (0..3)
    reg [2:0] bitn;       // which bit (7 down to 0)
    reg [7:0] shift;      // byte being sent / received
    reg       reading;    // 1 = this byte is a read
    reg       last_r;     // 1 = send NACK after this read (final byte)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; q <= 0; bitn <= 0; shift <= 0; reading <= 0; last_r <= 0;
            scl_o <= 1; sda_o <= 1; sda_oe <= 1;
            dout <= 0; done <= 0; nack <= 0;
        end else begin
            done <= 0;

            if (state == IDLE) begin
                q <= 0;
                if (start) begin
                    shift <= din; reading <= 0; state <= START;
                end else if (write) begin
                    shift <= din; reading <= 0; bitn <= 7; state <= BITS;
                end else if (read) begin
                    reading <= 1; last_r <= last; bitn <= 7; state <= BITS;
                end else if (stop) begin
                    state <= STOP;
                end
            end

            else if (tick) begin
                q <= q + 1'b1;
                case (state)
                    // START: SDA goes low while SCL is high, then send the address
                    START: case (q)
                        0: begin sda_oe <= 1; sda_o <= 1; scl_o <= 1; end
                        1: sda_o <= 0;
                        2: scl_o <= 0;
                        3: begin bitn <= 7; state <= BITS; end
                    endcase

                    // one data bit: set SDA while SCL is low, then pulse SCL high
                    BITS: case (q)
                        0: begin
                               if (reading) sda_oe <= 0;                 // chip talks
                               else begin sda_oe <= 1; sda_o <= shift[bitn]; end
                           end
                        1: scl_o <= 1;
                        2: if (reading) shift[bitn] <= sda_in;          // read the bit
                        3: begin
                               scl_o <= 0;
                               if (bitn == 0) begin
                                   if (!reading) sda_oe <= 0;   // let go NOW: the chip answers right away
                                   state <= ACK;
                               end else bitn <= bitn - 1'b1;
                           end
                    endcase

                    // 9th bit: after a write the CHIP answers, after a read WE answer
                    ACK: case (q)
                        0: if (reading) begin sda_oe <= 1; sda_o <= last_r; end
                           else         sda_oe <= 0;                     // let chip answer
                        1: scl_o <= 1;
                        2: if (!reading) nack <= sda_in;                 // low = ACK
                        3: begin
                               scl_o <= 0;
                               if (reading) dout <= shift;
                               done  <= 1;
                               state <= IDLE;
                           end
                    endcase

                    // STOP: SDA goes high while SCL is high
                    STOP: case (q)
                        0: begin sda_oe <= 1; sda_o <= 0; end
                        1: scl_o <= 1;
                        2: sda_o <= 1;
                        3: begin done <= 1; state <= IDLE; end
                    endcase

                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule


// ============================================================
// beat_detector.v  --  finds each heartbeat in the sensor signal
// ============================================================
// The pulse sensor gives a voltage that sits around ~1.6 V and
// jumps up with every heartbeat. Each heartbeat ALSO has a smaller
// second bump about 0.3-0.4 s later (the "dicrotic notch"). When
// the finger stays on the sensor for a while the signal gets
// stronger, and that second bump can look like an extra beat.
// So every beat must pass 3 rules:
//
//   RULE 1  The signal must rise above its running AVERAGE by at
//           least HYST, AND by at least HALF the height of the
//           previous beat.  -> the smaller second bump is ignored,
//           and the threshold grows/shrinks with the signal.
//
//   RULE 2  After a beat, wait 5/8 of the previous beat-to-beat
//           time before accepting the next one (at least 300 ms,
//           at most 600 ms).  -> the second bump comes too early.
//
//   RULE 3  The signal must first drop back below the average
//           (one beat = one rise).
//
//   SAFETY  If no beat is seen for 2 s (finger moved or pressed),
//           rules 1 and 2 go back to their starting values (HYST and
//           300 ms) for as long as no beat is found, so the detector
//           always picks the pulse up again.
//           A beat's height is only measured in the first 300 ms after
//           it, so a slow drift (finger pressing harder) can never be
//           mistaken for one huge beat.
//
// Average update: avg = avg + (sample - avg) / 64
// (we store avg x 64 so this needs only add/subtract, no divide)
// ============================================================
module beat_detector #(
    parameter        CLK_HZ = 50_000_000,
    parameter [15:0] HYST   = 16'd300      // minimum rise: 300 counts = 37.5 mV
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] sample,
    input  wire        new_sample,
    output reg         beat,                // 1-clock pulse per heartbeat
    output wire [15:0] average
);
    // ---------- 1 ms tick ----------
    reg  [31:0] div;
    wire        ms = (div == CLK_HZ / 1000 - 1);
    always @(posedge clk or posedge rst)
        if (rst)     div <= 0;
        else if (ms) div <= 0;
        else         div <= div + 1'b1;

    wire [15:0] x = sample[15] ? 16'd0 : sample;   // ignore negative readings

    reg  [21:0] avg64;          // average x 64
    reg         started;        // 1 after the first sample
    reg         armed;          // 1 = signal went below average (rule 3)
    reg  [15:0] height;         // highest rise of the current beat
    reg  [15:0] last_height;    // height of the previous beat
    reg  [11:0] since_ms;       // ms since the last beat (stops at 4000)
    reg  [11:0] interval_ms;    // ms between the last two beats

    assign average = avg64[21:6];

    // how far the signal is above its average right now
    wire [15:0] rise = (x > average) ? (x - average) : 16'd0;

    // SAFETY: no beat for 2 s -> forget the old beat (lost = 1)
    wire        lost      = (since_ms >= 12'd2000);

    // RULE 1: needed rise = the bigger of HYST and half the last beat's height
    wire [15:0] half_last = last_height >> 1;
    wire [15:0] need      = (!lost && half_last > HYST) ? half_last : HYST;

    // RULE 2: wait 5/8 of the last interval (1/2 + 1/8), kept between 300 and 600 ms
    wire [11:0] five_8ths = (interval_ms >> 1) + (interval_ms >> 3);
    wire [11:0] min_gap   = lost                   ? 12'd300 :
                            (five_8ths < 12'd300) ? 12'd300 :
                            (five_8ths > 12'd600) ? 12'd600 : five_8ths;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            avg64 <= 0; started <= 0; armed <= 0; beat <= 0;
            height <= 0; last_height <= 0; since_ms <= 0; interval_ms <= 0;
        end else begin
            beat <= 0;

            // ---- time since the last beat ----
            if (ms && since_ms < 4000) since_ms <= since_ms + 1'b1;

            // ---- every new ADC sample ----
            if (new_sample) begin
                if (!started) begin
                    avg64   <= {x, 6'd0};            // start the average at the first value
                    started <= 1;
                end else begin
                    avg64 <= avg64 + x - average;    // slow running average

                    if (armed && since_ms >= min_gap && rise > need) begin
                        beat        <= 1;            // heartbeat!
                        armed       <= 0;
                        interval_ms <= since_ms;     // remember beat-to-beat time
                        since_ms    <= 0;
                        height      <= rise;         // start measuring this beat's height
                    end else if (!armed) begin
                        if (rise > height && since_ms < 300)
                            height <= rise;                  // top of this beat (first 300 ms only)
                        if (x < average) begin               // beat is over (rule 3)
                            armed       <= 1;
                            last_height <= height;
                        end
                    end
                end
            end
        end
    end
endmodule


// ============================================================
// pulse_input.v  --  heartbeats from a sensor wired STRAIGHT
//                    to an FPGA pin (backup: no ADC needed)
// ============================================================
// An FPGA input pin reads any voltage as just 0 or 1: below
// about 1.4 V it reads 0, above it reads 1. The pulse sensor's
// output rises with every heartbeat, so the pin goes 0 -> 1
// once per beat.
//
// Steps:
//   1. pass the pin through 2 flip-flops (safe to use inside the FPGA)
//   2. clean it: check it every 1 ms and accept a new level only
//      if it stays the same for 20 ms in a row (removes noise)
//   3. beat = the clean signal goes 0 -> 1, and enough time has
//      passed since the previous beat: 5/8 of the previous
//      beat-to-beat time (at least 300 ms, at most 600 ms).
//      This ignores the small second bump that follows each
//      heartbeat. After 2 s with no beat the wait resets to 300 ms.
// ============================================================
module pulse_input #(
    parameter CLK_HZ = 50_000_000
)(
    input  wire clk,
    input  wire rst,
    input  wire pulse_pin,      // sensor S wired to this FPGA pin
    output reg  beat,           // 1-clock pulse per heartbeat
    output reg  level           // cleaned-up signal (for an LED)
);
    // ---------- 1. synchronise ----------
    reg s1, s2;
    always @(posedge clk) begin s1 <= pulse_pin; s2 <= s1; end

    // ---------- 1 ms tick ----------
    reg [31:0] div;
    wire ms = (div == CLK_HZ / 1000 - 1);
    always @(posedge clk or posedge rst)
        if (rst)     div <= 0;
        else if (ms) div <= 0;
        else         div <= div + 1'b1;

    // ---------- 2. clean, 3. detect ----------
    reg [4:0]  same;        // how many ms the pin has differed from `level`
    reg [11:0] gap;         // ms since the last beat (stops at 4000)
    reg [11:0] interval;    // ms between the last two beats

    wire [11:0] five_8ths = (interval >> 1) + (interval >> 3);
    wire [11:0] min_gap   = (five_8ths < 12'd300) ? 12'd300 :
                            (five_8ths > 12'd600) ? 12'd600 : five_8ths;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            level <= 0; same <= 0; gap <= 0; interval <= 0; beat <= 0;
        end else begin
            beat <= 0;
            if (ms) begin
                if (gap < 4000) gap <= gap + 1'b1;
                if (gap == 2000) interval <= 0;       // no beat for 2 s: start fresh

                if (s2 == level) same <= 0;           // nothing new
                else if (same == 19) begin            // new level held for 20 ms
                    same  <= 0;
                    level <= s2;
                    if (s2 == 1 && gap >= min_gap) begin  // rising edge = heartbeat
                        beat     <= 1;
                        interval <= gap;
                        gap      <= 0;
                    end
                end
                else same <= same + 1'b1;
            end
        end
    end
endmodule


// ============================================================
// bpm_calc.v  --  beats per minute + heart condition
// ============================================================
// Counts heartbeats for a full 60-second window. The number of
// beats counted in that minute IS the BPM, so no multiplying is
// needed. Then it starts counting again.
//
//      BPM = beats counted in 60 s
//
// (WINDOW_SEC can be set to 15 or 30 for faster updates; the
//  count is then multiplied by 60 / WINDOW_SEC = 4 or 2.)
//
// Heart condition (status):
//      0 = WAIT    first window not finished yet
//      1 = BRADY   BPM < 60      (bradycardia, slow)
//      2 = NORMAL  60 to 100
//      3 = TACHY   BPM > 100     (tachycardia, fast)
// ============================================================
module bpm_calc #(
    parameter CLK_HZ     = 50_000_000,
    parameter WINDOW_SEC = 60            // length of one counting window
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       beat,
    output reg  [7:0] bpm,
    output reg  [1:0] status,
    output reg  [5:0] seconds,           // 0 .. WINDOW_SEC-1, time inside the window
    output wire [5:0] secs_left          // seconds until the next reading
);
    localparam MULT = 60 / WINDOW_SEC;   // 60 s window -> x1

    reg [31:0] clocks;     // counts clock cycles up to 1 second
    reg [7:0]  beats;      // beats counted in this window
    reg        have_bpm;   // 1 after the first window

    assign secs_left = WINDOW_SEC - seconds;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clocks <= 0; seconds <= 0; beats <= 0; bpm <= 0; have_bpm <= 0;
        end else begin
            if (beat && beats != 8'd255) beats <= beats + 1'b1;

            if (clocks == CLK_HZ - 1) begin                  // one second passed
                clocks <= 0;
                if (seconds == WINDOW_SEC - 1) begin         // the window is over
                    seconds  <= 0;
                    bpm      <= (beats * MULT > 255) ? 8'd255 : beats * MULT;
                    beats    <= 0;
                    have_bpm <= 1;
                end else begin
                    seconds <= seconds + 1'b1;
                end
            end else begin
                clocks <= clocks + 1'b1;
            end
        end
    end

    always @(*) begin
        if (!have_bpm)       status = 2'd0;   // WAIT
        else if (bpm < 60)   status = 2'd1;   // BRADY
        else if (bpm <= 100) status = 2'd2;   // NORMAL
        else                 status = 2'd3;   // TACHY
    end
endmodule


// ============================================================
// buzzer.v  --  beeps with the heartbeat, or as an alarm
// ============================================================
//   mode = 0 (SW0 down) : short "tick" (60 ms) on EVERY heartbeat
//   mode = 1 (SW0 up)   : ALARM - "beep-beep" every second, but
//                         only while the condition is BRADY or TACHY
//   mute = 1 (SW1 up)   : silent
//
// Two kinds of buzzer exist:
//   PASSIVE buzzer: just clicks if you give it DC. It needs a tone
//                   (we send a 2 kHz square wave)  -> ACTIVE = 0
//   ACTIVE buzzer : beeps by itself when given DC
//                   (we just switch it on and off) -> ACTIVE = 1
// Some 3-pin buzzer modules beep when the pin is LOW -> ACTIVE_LOW = 1
// ============================================================
module buzzer #(
    parameter CLK_HZ     = 50_000_000,
    parameter ACTIVE     = 0,        // 0 = passive buzzer, 1 = active buzzer
    parameter ACTIVE_LOW = 0,        // 1 = module beeps when its pin is 0
    parameter TONE_HZ    = 2000      // pitch for a passive buzzer
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       beat,          // 1-clock pulse per heartbeat
    input  wire [1:0] status,        // 0 WAIT, 1 BRADY, 2 NORMAL, 3 TACHY
    input  wire       mode,          // 0 = beat ticks, 1 = alarm
    input  wire       mute,
    output wire       sound_on,      // 1 while beeping (for an LED)
    output wire       pin            // goes to the buzzer
);
    // ---------- 1 ms tick ----------
    reg  [31:0] div;
    wire        ms = (div == CLK_HZ / 1000 - 1);
    always @(posedge clk or posedge rst)
        if (rst)     div <= 0;
        else if (ms) div <= 0;
        else         div <= div + 1'b1;

    // ---------- mode 0: 60 ms tick per heartbeat ----------
    reg [6:0] tick_ms;
    always @(posedge clk or posedge rst)
        if (rst)                    tick_ms <= 0;
        else if (beat)              tick_ms <= 7'd60;
        else if (ms && tick_ms != 0) tick_ms <= tick_ms - 1'b1;

    // ---------- mode 1: beep 0-199 ms and 300-499 ms of every second ----------
    reg [9:0] alarm_ms;
    always @(posedge clk or posedge rst)
        if (rst)     alarm_ms <= 0;
        else if (ms) alarm_ms <= (alarm_ms == 999) ? 10'd0 : alarm_ms + 1'b1;

    wire abnormal  = (status == 1) || (status == 3);       // BRADY or TACHY
    wire alarm_on  = abnormal && (alarm_ms < 200 || (alarm_ms >= 300 && alarm_ms < 500));

    assign sound_on = !mute && (mode ? alarm_on : (tick_ms != 0));

    // ---------- 2 kHz tone for a passive buzzer ----------
    reg [31:0] tone_cnt;
    reg        tone;
    always @(posedge clk or posedge rst)
        if (rst) begin tone_cnt <= 0; tone <= 0; end
        else if (tone_cnt == CLK_HZ / (2 * TONE_HZ) - 1) begin tone_cnt <= 0; tone <= !tone; end
        else tone_cnt <= tone_cnt + 1'b1;

    wire drive = ACTIVE ? sound_on : (sound_on && tone);
    assign pin = ACTIVE_LOW ? !drive : drive;
endmodule


// ============================================================
// oled_display.v  --  shows BPM and heart condition on the OLED
// ============================================================
// Screen (128 x 64 pixels = 8 "pages", each page 8 pixels tall):
//
//      page 2 :   BPM: 072
//      page 5 :   NORMAL        (or BRADY / TACHY, or WAIT 45 = seconds
//                                 until the first reading)
//
// It simply redraws the WHOLE screen again and again (about 3
// times a second), so it always shows the newest values and
// clears any noise. Every redraw is 3 kinds of I2C transfer:
//
//   part 0 : setup commands   [0x78] 00 AE D5 80 ... AF   (once per redraw)
//   part 1 : go to page p     [0x78] 00 B0+p 00 10
//   part 2 : 132 pixel bytes  [0x78] 40 xx xx xx ...      (parts 1+2 for p = 0..7)
//
// One pixel byte = one column of 8 pixels (bit 0 = top pixel).
// Each letter is 8 columns wide: 5 columns of font + 3 blank.
// ============================================================
module oled_display #(
    parameter       CLK_HZ     = 50_000_000,
    parameter       I2C_HZ     = 100_000,
    parameter       OPEN_DRAIN = 0,
    parameter [6:0] ADDR       = 7'h3C,
    parameter [7:0] X0         = 8'd34     // column where the text starts
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] bpm,
    input  wire [1:0] status,        // 0 WAIT, 1 BRADY, 2 NORMAL, 3 TACHY
    input  wire [5:0] secs_left,     // countdown shown next to WAIT (0 = no countdown)
    inout  wire       sda,
    inout  wire       scl,
    output reg        ok             // 1 = the OLED answered
);
    // ---------- I2C master ----------
    reg        start, write, stop;
    reg  [7:0] din;
    wire [7:0] dout;
    wire       done, nack;

    i2c_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ), .OPEN_DRAIN(OPEN_DRAIN)) i2c (
        .clk(clk), .rst(rst),
        .start(start), .write(write), .read(1'b0), .stop(stop), .last(1'b0),
        .din(din), .dout(dout), .done(done), .nack(nack),
        .sda(sda), .scl(scl)
    );

    // ---------- setup commands (work for SSD1306 and SH1106 chips) ----------
    function [7:0] setup_cmd(input [4:0] i);
        case (i)
            0:  setup_cmd = 8'hAE;   // display off
            1:  setup_cmd = 8'hD5;   2:  setup_cmd = 8'h80;   // clock
            3:  setup_cmd = 8'hA8;   4:  setup_cmd = 8'h3F;   // 64 rows
            5:  setup_cmd = 8'hD3;   6:  setup_cmd = 8'h00;   // no offset
            7:  setup_cmd = 8'h40;                            // start line 0
            8:  setup_cmd = 8'h8D;   9:  setup_cmd = 8'h14;   // charge pump on
            10: setup_cmd = 8'h20;   11: setup_cmd = 8'h02;   // page mode
            12: setup_cmd = 8'hA1;                            // mirror left-right
            13: setup_cmd = 8'hC8;                            // mirror up-down
            14: setup_cmd = 8'hDA;   15: setup_cmd = 8'h12;
            16: setup_cmd = 8'h81;   17: setup_cmd = 8'hCF;   // brightness
            18: setup_cmd = 8'hD9;   19: setup_cmd = 8'hF1;
            20: setup_cmd = 8'hDB;   21: setup_cmd = 8'h40;
            22: setup_cmd = 8'hA4;                            // show memory contents
            23: setup_cmd = 8'hA6;                            // normal (not inverted)
            default: setup_cmd = 8'hAF;                       // 24: display ON
        endcase
    endfunction

    // ---------- 5x7 font: 5 bytes per letter, packed into 40 bits ----------
    function [7:0] font(input [7:0] ch, input [2:0] c);
        reg [39:0] g;
        begin
            case (ch)
                "0": g = 40'h3E_51_49_45_3E;   "1": g = 40'h00_42_7F_40_00;
                "2": g = 40'h42_61_51_49_46;   "3": g = 40'h21_41_45_4B_31;
                "4": g = 40'h18_14_12_7F_10;   "5": g = 40'h27_45_45_45_39;
                "6": g = 40'h3C_4A_49_49_30;   "7": g = 40'h01_71_09_05_03;
                "8": g = 40'h36_49_49_49_36;   "9": g = 40'h06_49_49_29_1E;
                "A": g = 40'h7E_11_11_11_7E;   "B": g = 40'h7F_49_49_49_36;
                "C": g = 40'h3E_41_41_41_22;   "D": g = 40'h7F_41_41_22_1C;
                "H": g = 40'h7F_08_08_08_7F;   "I": g = 40'h00_41_7F_41_00;
                "L": g = 40'h7F_40_40_40_40;   "M": g = 40'h7F_02_0C_02_7F;
                "N": g = 40'h7F_04_08_10_7F;   "O": g = 40'h3E_41_41_41_3E;
                "P": g = 40'h7F_09_09_09_06;   "R": g = 40'h7F_09_19_29_46;
                "T": g = 40'h01_01_7F_01_01;   "W": g = 40'h3F_40_38_40_3F;
                "Y": g = 40'h07_08_70_08_07;   ":": g = 40'h00_36_36_00_00;
                "-": g = 40'h08_08_08_08_08;
                default: g = 40'h00_00_00_00_00;   // space
            endcase
            case (c)
                0: font = g[39:32];
                1: font = g[31:24];
                2: font = g[23:16];
                3: font = g[15:8];
                4: font = g[7:0];
                default: font = 8'h00;              // columns 5-7: gap between letters
            endcase
        end
    endfunction

    // ---------- values being drawn (copied at the start of each redraw) ----------
    reg [7:0] show_bpm;
    reg [1:0] show_status;
    reg [5:0] show_secs;

    wire [7:0] hundreds = "0" + show_bpm / 8'd100;              // ASCII digits
    wire [7:0] tens     = "0" + (show_bpm / 8'd10) % 8'd10;
    wire [7:0] ones     = "0" + show_bpm % 8'd10;

    // ---------- which letter is at position k (0..7) of each line ----------
    function [7:0] line1(input [2:0] k, input [1:0] st,
                         input [7:0] h, input [7:0] t, input [7:0] o);  // "BPM: 072" / "BPM: ---"
        case (k)
            0: line1 = "B";  1: line1 = "P";  2: line1 = "M";  3: line1 = ":";  4: line1 = " ";
            5: line1 = (st == 0) ? "-" : h;
            6: line1 = (st == 0) ? "-" : t;
            default: line1 = (st == 0) ? "-" : o;
        endcase
    endfunction

    wire [7:0] secs_tens = "0" + show_secs / 6'd10;               // countdown digits
    wire [7:0] secs_ones = "0" + show_secs % 6'd10;

    function [7:0] line2(input [2:0] k, input [1:0] st,
                         input [7:0] c10, input [7:0] c1, input show_c);  // heart condition word
        case (st)
            0: case (k) 0: line2="W"; 1: line2="A"; 2: line2="I"; 3: line2="T";
                        5: line2 = show_c ? c10 : " ";               // "WAIT 45"
                        6: line2 = show_c ? c1  : " ";
                        default: line2=" "; endcase
            1: case (k) 0: line2="B"; 1: line2="R"; 2: line2="A"; 3: line2="D"; 4: line2="Y"; default: line2=" "; endcase
            2: case (k) 0: line2="N"; 1: line2="O"; 2: line2="R"; 3: line2="M"; 4: line2="A"; 5: line2="L"; default: line2=" "; endcase
            default: case (k) 0: line2="T"; 1: line2="A"; 2: line2="C"; 3: line2="H"; 4: line2="Y"; default: line2=" "; endcase
        endcase
    endfunction

    // ---------- transfer bookkeeping ----------
    reg [1:0] part;        // 0 setup, 1 go-to-page, 2 pixels
    reg [2:0] page;        // 0..7
    reg [7:0] n;           // byte number inside the transfer (after the address)

    // the pixel byte for screen column (n-1) on this page
    wire [7:0] col     = n - 8'd1;
    wire [7:0] x       = col - X0;
    wire       in_text = (col >= X0) && (col < X0 + 8'd64);
    reg  [7:0] letter;
    always @(*) begin
        if (page == 2)      letter = line1(x[5:3], show_status, hundreds, tens, ones);
        else if (page == 5) letter = line2(x[5:3], show_status, secs_tens, secs_ones, show_secs != 0);
        else                letter = " ";
    end
    wire [7:0] pixel = in_text ? font(letter, x[2:0]) : 8'h00;

    // the next byte to send, and how many bytes this transfer has
    reg [7:0] next_byte, length;
    always @(*) begin
        case (part)
            0: begin
                   length    = 8'd26;                            // 00 + 25 commands
                   next_byte = (n == 0) ? 8'h00 : setup_cmd(n - 1);
               end
            1: begin
                   length = 8'd4;
                   case (n)
                       0: next_byte = 8'h00;                     // "commands follow"
                       1: next_byte = 8'hB0 + page;              // page number
                       2: next_byte = 8'h00;                     // column 0 (low)
                       default: next_byte = 8'h10;               // column 0 (high)
                   endcase
               end
            default: begin
                   length    = 8'd133;                           // 40 + 132 pixels
                   next_byte = (n == 0) ? 8'h40 : pixel;         // "pixels follow"
               end
        endcase
    end

    // ---------- state machine ----------
    localparam PAUSE = 2'd0, ADDRESS = 2'd1, BYTES = 2'd2, FINISH = 2'd3;
    localparam PAUSE_CLOCKS = CLK_HZ / 5;            // 0.2 s between redraws

    reg [1:0]  state;
    reg        waiting;
    reg [31:0] timer;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= PAUSE; waiting <= 0; timer <= 0;
            part <= 0; page <= 0; n <= 0;
            start <= 0; write <= 0; stop <= 0; din <= 0;
            show_bpm <= 0; show_status <= 0; show_secs <= 0; ok <= 0;
        end else begin
            start <= 0; write <= 0; stop <= 0;

            if (state == PAUSE) begin
                if (timer == PAUSE_CLOCKS - 1) begin
                    timer <= 0;
                    show_bpm <= bpm; show_status <= status;   // take the newest values
                    show_secs <= secs_left;
                    part <= 0; page <= 0;
                    state <= ADDRESS;
                end else timer <= timer + 1'b1;
            end

            else if (!waiting) begin
                // give the next I2C command
                case (state)
                    ADDRESS: begin din <= {ADDR, 1'b0}; start <= 1; end   // 0x78
                    BYTES:   begin din <= next_byte;    write <= 1; end
                    FINISH:  begin                      stop  <= 1; end
                endcase
                waiting <= 1;
            end

            else if (done) begin
                waiting <= 0;
                case (state)
                    ADDRESS: begin
                        if (part == 0) ok <= !nack;           // did the OLED answer?
                        n <= 0;
                        state <= BYTES;
                    end
                    BYTES: begin
                        if (n == length - 1) state <= FINISH;
                        else n <= n + 1'b1;
                    end
                    FINISH: begin                             // choose the next transfer
                        if (part == 0)        begin part <= 1; page <= 0;         state <= ADDRESS; end
                        else if (part == 1)   begin part <= 2;                    state <= ADDRESS; end
                        else if (page != 7)   begin part <= 1; page <= page + 1'b1; state <= ADDRESS; end
                        else                  state <= PAUSE;  // whole screen done
                    end
                endcase
            end
        end
    end
endmodule


// ============================================================
// seven_seg.v  --  shows one digit (0-9) on a 7-segment display
// ============================================================
// DE2-115 segments light up when the pin is 0.
// blank = 1 turns the whole digit off.
// ============================================================
module seven_seg (
    input  wire [3:0] digit,
    input  wire       blank,
    output reg  [6:0] seg        // seg[0] = top ... seg[6] = middle
);
    always @(*) begin
        if (blank) seg = 7'b1111111;
        else case (digit)
            0: seg = 7'b1000000;
            1: seg = 7'b1111001;
            2: seg = 7'b0100100;
            3: seg = 7'b0110000;
            4: seg = 7'b0011001;
            5: seg = 7'b0010010;
            6: seg = 7'b0000010;
            7: seg = 7'b1111000;
            8: seg = 7'b0000000;
            9: seg = 7'b0010000;
            default: seg = 7'b0111111;   // shows '-'
        endcase
    end
endmodule


// ============================================================
// reset_gen.v  --  makes a clean reset signal
// ============================================================
// Reset is ON for ~0.17 s after the FPGA is programmed, and
// whenever KEY[0] is pressed.  (FPGA flip-flops start at 0 after
// programming, so `count` starts at 0 without an initial block.)
// ============================================================
module reset_gen #(
    parameter BITS = 24          // reset time = 2^(BITS-1) clocks
)(
    input  wire clk,
    input  wire key0,            // KEY[0]: 0 when pressed
    output wire rst              // 1 = reset
);
    reg [BITS-1:0] count;
    wire finished = count[BITS-1];

    always @(posedge clk)
        if (!finished) count <= count + 1'b1;

    assign rst = !finished || !key0;
endmodule
