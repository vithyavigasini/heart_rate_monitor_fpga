// ============================================================
// tb_top_main.v  --  testbench for the final design (simulation only)
// ============================================================
// Runs top_main with bit-accurate models of the OLED and the
// ADS1115 (i2c_slave_models.v). The ADS1115 model answers on the
// I2C wires like the real chip and returns a pulse waveform at a
// chosen BPM, with an optional second bump (dicrotic notch).
//
// The clock is 1 MHz instead of 50 MHz (CLK_HZ = 1_000_000) so the
// simulation runs 50x faster. Every time in the design is written
// as a multiple of CLK_HZ, so one simulated second = one second.
//
//   minute 1 : 72 BPM, second bump 55 % of the beat, signal 1x -> 3x
//   minute 2 : 120 BPM  -> expect TACHY
//   minute 3 : 45 BPM   -> expect BRADY
// ============================================================
`timescale 1ns/1ps
module tb_top_main;
    reg clk = 0;
    always #500 clk = ~clk;                        // 1 MHz
    reg  [3:0]  KEY = 4'b1111;                     // no key pressed
    reg  [1:0]  SW  = 2'b00;                       // buzzer: tick mode, not muted
    tri1        oled_sda, oled_scl, adc_sda, adc_scl;   // pull-up resistors
    wire [17:0] LEDR;
    wire [8:0]  LEDG;
    wire [6:0]  HEX0, HEX1, HEX2;
    wire        buzz;
    integer     errors = 0, beats = 0, b0, csv;

    // ---------- design under test + chip models ----------
    top_main #(.CLK_HZ(1_000_000), .RESET_BITS(4)) dut (
        .CLOCK_50(clk), .KEY(KEY), .SW(SW), .BUZZER(buzz),
        .OLED_SDA(oled_sda), .OLED_SCL(oled_scl),
        .ADC_SDA(adc_sda),   .ADC_SCL(adc_scl),
        .LEDR(LEDR), .LEDG(LEDG), .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2));
    oled_model #(7'h3C) oled (.sda(oled_sda), .scl(oled_scl));
    ads_model  #(7'h48) ads  (.sda(adc_sda),  .scl(adc_scl));

    // ---------- helpers ----------
    task check(input ok, input [8*60-1:0] msg);
        begin
            if (ok) $display("  PASS  %0s", msg);
            else begin $display("  FAIL  %0s", msg); errors = errors + 1; end
        end
    endtask

    function [7:0] segc(input [6:0] s);            // HEX segments -> character
        case (s)
            7'b1000000: segc="0"; 7'b1111001: segc="1"; 7'b0100100: segc="2"; 7'b0110000: segc="3";
            7'b0011001: segc="4"; 7'b0010010: segc="5"; 7'b0000010: segc="6"; 7'b1111000: segc="7";
            7'b0000000: segc="8"; 7'b0010000: segc="9"; 7'b1111111: segc=" "; default: segc="?";
        endcase
    endfunction

    function [8*6-1:0] cond(input [1:0] st);
        cond = (st == 0) ? "WAIT" : (st == 1) ? "BRADY" : (st == 2) ? "NORMAL" : "TACHY";
    endfunction

    task report(input [8*40-1:0] what);
        begin
            $display("\n  %0s: beats=%0d  BPM=%0d  status=%0s  HEX=%s%s%s  LEDG=%b",
                     what, beats - b0, dut.bpm, cond(dut.status),
                     segc(HEX2), segc(HEX1), segc(HEX0), LEDG);
            $display("    OLED page 2:"); oled.show_page(2, 34, 64);
            $display("    OLED page 5:"); oled.show_page(5, 34, 64);
        end
    endtask

    always @(posedge clk) if (dut.beat) beats = beats + 1;

    // ---------- log 20 s to 26 s of samples for the waveform figure ----------
    initial csv = $fopen("beat_trace.csv", "w");
    always @(posedge clk) begin
        if (dut.new_sample && $realtime >= 20e9 && $realtime < 26e9)
            $fwrite(csv, "S,%0.4f,%0d,%0d,%0d\n", $realtime * 1e-9,
                    dut.u_beat.x, dut.u_beat.average, dut.u_beat.need);
        if (dut.beat && $realtime >= 20e9 && $realtime < 26e9)
            $fwrite(csv, "B,%0.4f\n", $realtime * 1e-9);
    end

    // ---------- the simulated finger ----------
    initial begin : finger
        ads.bpm_sim = 72.0; ads.notch = 0.55; ads.gain = 1.0;
        repeat (600) begin #100_000_000; ads.gain = ads.gain + 0.0033; end   // 1x -> 3x in 60 s
    end

    // ---------- test sequence ----------
    initial begin
        $display("==== tb_top_main: final design, 60 s window ====");
        dut.u_reset.count = 0;          // FPGA flip-flops start at 0 after programming
        b0 = 0;

        #1_000_000_000;                                     // 1 s
        check(LEDG[1] && LEDG[2] && !LEDR[0] && !LEDR[1], "OLED and ADC both answering");
        check(ads.config_reg == 16'hC283,                   "ADC config register = 0xC283");
        check(oled.display_on,                              "OLED switched on");

        #14_500_000_000;                                    // 15.5 s
        $display("\n  at 15.5 s: status=%0s  seconds left=%0d", cond(dut.status), dut.secs_left);
        $display("    OLED page 5:"); oled.show_page(5, 34, 64);
        check(dut.status == 0 && dut.secs_left == 45,       "WAIT with a 45 s countdown");

        #45_000_000_000;                                    // 60.5 s
        report("minute 1 (72 BPM, long hold)");
        check(dut.bpm >= 70 && dut.bpm <= 74 && dut.status == 2, "minute 1: about 72, NORMAL");
        check(LEDG[6] && !LEDG[5] && !LEDG[7],              "NORMAL LED (LEDG6) on");

        b0 = beats; ads.bpm_sim = 120.0;
        #60_000_000_000;                                    // 120.5 s
        report("minute 2 (120 BPM)");
        check(dut.bpm >= 117 && dut.bpm <= 122 && dut.status == 3, "minute 2: about 120, TACHY");

        b0 = beats; ads.bpm_sim = 45.0;
        #60_000_000_000;                                    // 180.5 s
        report("minute 3 (45 BPM)");
        check(dut.bpm >= 43 && dut.bpm <= 47 && dut.status == 1, "minute 3: about 45, BRADY");
        check(LEDG[1] && LEDG[2],                           "both I2C devices still answering");

        $display("\n==== %0s (%0d errors) ====", errors ? "FAILED" : "ALL PASSED", errors);
        $fclose(csv);
        $finish;
    end
endmodule
