// ------------------------------------------------------------
// i2c_slave_models.v  (simulation only)
//
// Bit-accurate I2C slave models. They ONLY listen after a real
// START condition (SDA falling while SCL high), so a missing
// START = NACK, exactly like the real chips.
//   oled_model : SSD1306/SH1106 command parser + 8x132 framebuffer
//   ads_model  : ADS1115 pointer/config/conversion registers,
//                conversion = simulated pulse waveform
// ------------------------------------------------------------
`timescale 1ns/1ps

module i2c_slave_core #(parameter [6:0] ADDR = 7'h3C) (
    inout  wire sda,
    input  wire scl,
    // byte interface to the device model
    output reg        wr_strobe,     // pulses: a written byte is in wr_byte
    output reg  [7:0] wr_byte,
    output reg  [7:0] wr_index,      // 0 = first byte after address
    output reg        rd_strobe,     // pulses: model must present rd_index byte
    output reg  [7:0] rd_index,
    input  wire [7:0] rd_byte,
    output reg        txn_start      // pulses on START addressed to us
);
    integer starts, stops;
    reg drive_low = 0;
    assign sda = drive_low ? 1'b0 : 1'bz;

    reg active = 0, skip_fall = 0, addr_phase = 0, selected = 0, rw = 0, m_ack = 0;
    reg [3:0] bitcnt = 0;
    reg [7:0] sh = 0, tx = 0;

    initial begin starts = 0; stops = 0; wr_strobe = 0; rd_strobe = 0; txn_start = 0;
                  wr_index = 0; rd_index = 0; wr_byte = 0; end

    always @(negedge sda) if (scl === 1'b1) begin
        active = 1; skip_fall = 1; addr_phase = 1; selected = 0; bitcnt = 0;
        drive_low = 0; starts = starts + 1;
    end
    always @(posedge sda) if (scl === 1'b1 && $time > 0) begin
        active = 0; selected = 0; drive_low = 0; stops = stops + 1;
    end

    always @(posedge scl) if (active) begin
        if (bitcnt < 8) begin
            if (addr_phase || (selected && !rw)) sh = {sh[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
        end else if (selected && rw) begin
            m_ack = (sda === 1'b0);
        end
    end

    task load_tx; begin
        rd_strobe = 1; #1; rd_strobe = 0; #1;   // let model update rd_byte
        tx = rd_byte; rd_index = rd_index + 1;
        drive_low = ~tx[7];
    end endtask

    always @(negedge scl) if (active) begin
        if (skip_fall) skip_fall = 0;
        else if (bitcnt < 7) begin
            bitcnt = bitcnt + 1;
            if (selected && rw && !addr_phase) drive_low = ~tx[7 - bitcnt];
        end else if (bitcnt == 7) begin
            bitcnt = 8;
            if (addr_phase) begin
                if (sh[7:1] == ADDR) begin
                    selected = 1; rw = sh[0]; drive_low = 1;
                    wr_index = 0; rd_index = 0;
                    txn_start = 1; #1 txn_start = 0;
                end else drive_low = 0;
            end else if (selected && !rw) begin
                wr_byte = sh; wr_strobe = 1; #1 wr_strobe = 0;
                wr_index = wr_index + 1;
                drive_low = 1;                       // ACK
            end else drive_low = 0;                  // release for master ACK
        end else begin                               // end of ACK clock
            bitcnt = 0;
            if (addr_phase) begin
                addr_phase = 0;
                if (selected && rw) load_tx; else drive_low = 0;
            end else if (selected && rw) begin
                if (m_ack) load_tx; else drive_low = 0;
            end else drive_low = 0;
        end
    end
endmodule

// ------------------------------------------------------------
module oled_model #(parameter [6:0] ADDR = 7'h3C) (inout wire sda, input wire scl);
    wire wr_strobe, rd_strobe, txn_start; wire [7:0] wr_byte, wr_index, rd_index;
    i2c_slave_core #(.ADDR(ADDR)) core (.sda(sda), .scl(scl),
        .wr_strobe(wr_strobe), .wr_byte(wr_byte), .wr_index(wr_index),
        .rd_strobe(rd_strobe), .rd_index(rd_index), .rd_byte(8'hFF),
        .txn_start(txn_start));

    reg [7:0] fb [0:7][0:131];
    reg [2:0] page; reg [7:0] col;
    reg is_data; reg param_pending;
    reg display_on, all_on;
    integer data_bytes, i, j;

    initial begin
        page = 0; col = 0; display_on = 0; all_on = 0; data_bytes = 0; param_pending = 0;
        for (i = 0; i < 8; i = i + 1) for (j = 0; j < 132; j = j + 1)
            fb[i][j] = $random;          // GDDRAM powers up as noise, like the real chip
    end

    always @(posedge wr_strobe) begin
        if (wr_index == 0) begin
            is_data = (wr_byte == 8'h40);
            param_pending = 0;
        end else if (is_data) begin
            if (col < 132) fb[page][col] = wr_byte;
            col = col + 1; data_bytes = data_bytes + 1;
        end else if (param_pending) begin
            param_pending = 0;
        end else begin
            casez (wr_byte)
                8'b1011_0???: page = wr_byte[2:0];
                8'b0000_????: col = {col[7:4], wr_byte[3:0]};
                8'b0001_????: col = {wr_byte[3:0], col[3:0]};
                8'hAE: display_on = 0;
                8'hAF: display_on = 1;
                8'hA4: all_on = 0;
                8'hA5: all_on = 1;
                8'hD5, 8'hA8, 8'hD3, 8'h8D, 8'h20, 8'hDA, 8'h81, 8'hD9, 8'hDB:
                       param_pending = 1;
                default: ;
            endcase
        end
    end

    // print page p, columns c0..c0+w-1, as ASCII art (# = pixel on)
    task show_page(input integer p, input integer c0, input integer w);
        integer r, c;
        begin
            for (r = 0; r < 8; r = r + 1) begin
                $write("      |");
                for (c = c0; c < c0 + w; c = c + 1) $write("%s", fb[p][c][r] ? "#" : " ");
                $write("|\n");
            end
        end
    endtask

    function integer nonzero_bytes; input dummy; integer p, c; begin
        nonzero_bytes = 0;
        for (p = 0; p < 8; p = p + 1) for (c = 0; c < 132; c = c + 1)
            if (fb[p][c] !== 8'h00) nonzero_bytes = nonzero_bytes + 1;
    end endfunction
endmodule

// ------------------------------------------------------------
module ads_model #(parameter [6:0] ADDR = 7'h48) (inout wire sda, input wire scl);
    wire wr_strobe, rd_strobe, txn_start; wire [7:0] wr_byte, wr_index, rd_index;
    reg  [7:0] rd_byte = 0;
    i2c_slave_core #(.ADDR(ADDR)) core (.sda(sda), .scl(scl),
        .wr_strobe(wr_strobe), .wr_byte(wr_byte), .wr_index(wr_index),
        .rd_strobe(rd_strobe), .rd_index(rd_index), .rd_byte(rd_byte),
        .txn_start(txn_start));

    reg [7:0]  ptr = 0;
    reg [15:0] config_reg = 16'h8583;
    reg [15:0] conv = 0;
    integer    reads = 0;
    real       bpm_sim = 80.0;     // heart rate the model produces (tb can change it)
    real       gain    = 1.0;      // signal strength (grows when a finger is held longer)
    real       notch   = 0.0;      // size of the second (dicrotic) bump, 0 = none
    real       offset  = 0.0;      // slow shift of the whole signal (finger pressing harder)
    real       phase = 0.0, t_last = 0.0;

    always @(posedge wr_strobe) begin
        if (wr_index == 0)       ptr = wr_byte;
        else if (ptr == 8'h01) begin
            if (wr_index == 1) config_reg[15:8] = wr_byte;
            else               config_reg[7:0]  = wr_byte;
        end
    end

    // pulse-like waveform: baseline 13000 codes (~1.6 V) + sharp peak per beat
    always @(posedge rd_strobe) begin
        if (rd_index == 0) begin
            phase  = phase + ($realtime*1e-9 - t_last) * bpm_sim / 60.0;
            t_last = $realtime*1e-9;
            while (phase >= 1.0) phase = phase - 1.0;
            if (phase < 0.15)
                conv = 13000 + $rtoi(2500.0 * gain * $sin(3.14159265 * phase / 0.15));
            else if (notch > 0.0 && phase >= 0.45 && phase < 0.60)    // second bump ~0.4 s later
                conv = 13000 - 200 + $rtoi(2500.0 * gain * notch * $sin(3.14159265 * (phase - 0.45) / 0.15));
            else
                conv = 13000 - 200;
            conv = conv + $rtoi(offset) + ($random % 40);   // drift + a little noise
            reads = reads + 1;
        end
        rd_byte = (ptr == 8'h00) ? (rd_index == 0 ? conv[15:8] : conv[7:0])
                                 : (rd_index == 0 ? config_reg[15:8] : config_reg[7:0]);
    end
endmodule
