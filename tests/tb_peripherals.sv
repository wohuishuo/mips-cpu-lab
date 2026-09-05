`timescale 1ns/1ps

module tb_peripherals;
    localparam integer CLOCK_HZ = 1000;
    localparam integer BAUD = 100;
    localparam integer UART_CLKS_PER_BIT = CLOCK_HZ / BAUD;
    localparam integer SCAN_HZ = 100;
    localparam integer SCAN_CLKS = CLOCK_HZ / SCAN_HZ;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg        tx_valid = 1'b0;
    reg [7:0]  tx_data = 8'h00;
    wire       tx_ready;
    wire       tx;

    reg         rx = 1'b1;
    wire        rx_valid;
    wire [7:0]  rx_data;
    wire        frame_error;

    reg  [31:0] value = 32'h00000000;
    wire [7:0]  digit_n;
    wire [7:0]  segment_n;

    reg         buzzer_enable = 1'b0;
    reg  [15:0] frequency_hz = 16'd0;
    wire        wave;

    integer failures = 0;
    integer rx_valid_count = 0;
    integer rx_error_count = 0;
    reg [7:0] last_rx_data = 8'h00;

    uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) dut_tx (
        .clk(clk), .rst(rst), .tx_valid(tx_valid), .tx_data(tx_data),
        .tx_ready(tx_ready), .tx(tx)
    );

    uart_rx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) dut_rx (
        .clk(clk), .rst(rst), .rx(rx), .rx_valid(rx_valid),
        .rx_data(rx_data), .frame_error(frame_error)
    );

    seven_segment #(.CLOCK_HZ(CLOCK_HZ), .SCAN_HZ(SCAN_HZ)) dut_display (
        .clk(clk), .rst(rst), .value(value),
        .digit_n(digit_n), .segment_n(segment_n)
    );

    buzzer #(.CLOCK_HZ(CLOCK_HZ)) dut_buzzer (
        .clk(clk), .rst(rst), .enable(buzzer_enable),
        .frequency_hz(frequency_hz), .wave(wave)
    );

    always @(negedge clk) begin
        if (rx_valid) begin
            rx_valid_count = rx_valid_count + 1;
            last_rx_data = rx_data;
        end
        if (frame_error)
            rx_error_count = rx_error_count + 1;
    end

    task automatic check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic apply_reset;
        begin
            @(negedge clk);
            rst = 1'b1;
            tx_valid = 1'b0;
            rx = 1'b1;
            buzzer_enable = 1'b0;
            frequency_hz = 16'd0;
            repeat (3) @(posedge clk);
            #1;
            check(tx === 1'b1, "TX must be idle-high in reset");
            check(tx_ready === 1'b1, "TX must be ready after reset");
            check(rx_valid === 1'b0, "RX valid must clear in reset");
            check(frame_error === 1'b0, "RX frame error must clear in reset");
            check(wave === 1'b0, "buzzer output must clear in reset");
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task automatic monitor_tx_byte;
        input [7:0] expected;
        integer bit_number;
        begin
            @(negedge tx);
            repeat (UART_CLKS_PER_BIT/2) @(posedge clk);
            #1;
            check(tx === 1'b0, "TX start bit must be low at its center");
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                repeat (UART_CLKS_PER_BIT) @(posedge clk);
                #1;
                check(tx === expected[bit_number], "TX data bit mismatch (LSB first)");
                check(tx_ready === 1'b0, "TX ready must stay low while a frame is active");
            end
            repeat (UART_CLKS_PER_BIT) @(posedge clk);
            #1;
            check(tx === 1'b1, "TX stop bit must be high");
        end
    endtask

    task automatic drive_rx_frame;
        input [7:0] serial_data;
        input good_stop;
        integer bit_number;
        begin
            rx = 1'b0;
            repeat (UART_CLKS_PER_BIT) @(negedge clk);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                rx = serial_data[bit_number];
                repeat (UART_CLKS_PER_BIT) @(negedge clk);
            end
            rx = good_stop;
            repeat (UART_CLKS_PER_BIT) @(negedge clk);
            rx = 1'b1;
        end
    endtask

    function automatic [7:0] expected_segments;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: expected_segments = 8'b11000000;
                4'h1: expected_segments = 8'b11111001;
                4'h2: expected_segments = 8'b10100100;
                4'h3: expected_segments = 8'b10110000;
                4'h4: expected_segments = 8'b10011001;
                4'h5: expected_segments = 8'b10010010;
                4'h6: expected_segments = 8'b10000010;
                4'h7: expected_segments = 8'b11111000;
                4'h8: expected_segments = 8'b10000000;
                4'h9: expected_segments = 8'b10010000;
                4'hA: expected_segments = 8'b10001000;
                4'hB: expected_segments = 8'b10000011;
                4'hC: expected_segments = 8'b11000110;
                4'hD: expected_segments = 8'b10100001;
                4'hE: expected_segments = 8'b10000110;
                default: expected_segments = 8'b10001110;
            endcase
        end
    endfunction

    task automatic test_tx;
        begin
            $display("TEST: UART TX independent decode and consecutive bytes");
            apply_reset();
            fork
                begin
                    monitor_tx_byte(8'hA5);
                    monitor_tx_byte(8'h3C);
                end
                begin
                    @(negedge clk);
                    tx_data = 8'hA5;
                    tx_valid = 1'b1;
                    @(posedge clk);
                    @(negedge clk);
                    tx_data = 8'h3C;
                    while (!tx_ready) @(negedge clk);
                    @(posedge clk);
                    @(negedge clk);
                    tx_valid = 1'b0;
                end
            join
            repeat (UART_CLKS_PER_BIT) @(posedge clk);
            #1;
            check(tx_ready === 1'b1, "TX must return ready after consecutive frames");
            check(tx === 1'b1, "TX must return to idle high");

            $display("TEST: UART TX synchronous reset during frame");
            @(negedge clk);
            tx_data = 8'h00;
            tx_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            tx_valid = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b1;
            @(posedge clk);
            #1;
            check(tx === 1'b1, "TX reset during frame must restore idle high");
            check(tx_ready === 1'b1, "TX reset during frame must cancel transaction");
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task automatic test_rx;
        integer valid_before;
        integer errors_before;
        begin
            $display("TEST: UART RX independent bit-banged frames");
            apply_reset();
            valid_before = rx_valid_count;
            errors_before = rx_error_count;
            @(negedge clk);
            drive_rx_frame(8'h96, 1'b1);
            repeat (5) @(posedge clk);
            check(rx_valid_count == valid_before + 1, "RX must pulse valid once for a good frame");
            check(last_rx_data == 8'h96, "RX must reconstruct LSB-first data");
            check(rx_error_count == errors_before, "good RX frame must not report frame error");
            check(rx_valid === 1'b0, "RX valid pulse must be one clock wide");

            $display("TEST: UART RX malformed stop bit");
            valid_before = rx_valid_count;
            errors_before = rx_error_count;
            @(negedge clk);
            drive_rx_frame(8'h55, 1'b0);
            repeat (5) @(posedge clk);
            check(rx_valid_count == valid_before, "bad stop bit must suppress RX valid");
            check(rx_error_count == errors_before + 1, "bad stop bit must pulse frame error once");
            check(frame_error === 1'b0, "frame error pulse must be one clock wide");

            $display("TEST: UART RX back-to-back bytes");
            valid_before = rx_valid_count;
            errors_before = rx_error_count;
            @(negedge clk);
            drive_rx_frame(8'h00, 1'b1);
            drive_rx_frame(8'hFF, 1'b1);
            repeat (5) @(posedge clk);
            check(rx_valid_count == valid_before + 2, "RX must accept frames with no extra idle bit");
            check(last_rx_data == 8'hFF, "RX must preserve the second consecutive byte");
            check(rx_error_count == errors_before, "consecutive good frames must not error");

            $display("TEST: UART RX reset during frame");
            valid_before = rx_valid_count;
            errors_before = rx_error_count;
            @(negedge clk);
            rx = 1'b0;
            repeat (UART_CLKS_PER_BIT) @(negedge clk);
            rx = 1'b1;
            repeat (2*UART_CLKS_PER_BIT) @(negedge clk);
            rst = 1'b1;
            rx = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            check(rx_valid === 1'b0, "RX valid must remain clear during mid-frame reset");
            check(frame_error === 1'b0, "RX error must remain clear during mid-frame reset");
            @(negedge clk);
            rst = 1'b0;
            repeat (12*UART_CLKS_PER_BIT) @(posedge clk);
            check(rx_valid_count == valid_before, "reset must cancel a partial RX frame");
            check(rx_error_count == errors_before, "reset partial frame must not report error");
        end
    endtask

    task automatic test_display;
        integer nibble;
        integer scan_index;
        reg [7:0] expected_digit_n;
        begin
            $display("TEST: seven-segment all hexadecimal glyphs");
            apply_reset();
            for (nibble = 0; nibble < 16; nibble = nibble + 1) begin
                value = {8{nibble[3:0]}};
                @(negedge clk);
                #1;
                check(segment_n === expected_segments(nibble[3:0]),
                      "seven-segment hexadecimal glyph mismatch");
                check(segment_n[7] === 1'b1, "decimal point must remain off");
            end

            $display("TEST: seven-segment scan order and one-hot active-low digit select");
            apply_reset();
            value = 32'h76543210;
            #1;
            check(digit_n === 8'b11111110, "display reset must select least-significant digit");
            check(segment_n === expected_segments(4'h0), "digit zero must show least-significant nibble");
            for (scan_index = 1; scan_index < 8; scan_index = scan_index + 1) begin
                repeat (SCAN_CLKS) @(posedge clk);
                #1;
                expected_digit_n = ~(8'b00000001 << scan_index);
                check(digit_n === expected_digit_n, "display digit scan order mismatch");
                check(segment_n === expected_segments(scan_index[3:0]),
                      "display selected nibble mismatch");
                check((~digit_n != 8'h00) && (((~digit_n) & ((~digit_n)-1'b1)) == 8'h00),
                      "display must select exactly one active-low digit");
            end
        end
    endtask

    task automatic test_buzzer;
        integer cycle_number;
        reg prior_wave;
        begin
            $display("TEST: buzzer frequency, disable and reset");
            apply_reset();
            @(negedge clk);
            buzzer_enable = 1'b1;
            frequency_hz = 16'd50;
            prior_wave = wave;
            for (cycle_number = 1; cycle_number <= 20; cycle_number = cycle_number + 1) begin
                @(posedge clk);
                #1;
                if ((cycle_number == 10) || (cycle_number == 20)) begin
                    check(wave !== prior_wave, "buzzer must toggle at each half-period");
                    prior_wave = wave;
                end else begin
                    check(wave === prior_wave, "buzzer must hold between half-period boundaries");
                end
            end
            check(wave === 1'b0, "two buzzer half-periods must produce one full period");

            @(negedge clk);
            buzzer_enable = 1'b0;
            @(posedge clk);
            #1;
            check(wave === 1'b0, "disabled buzzer must drive zero");
            repeat (12) @(posedge clk);
            check(wave === 1'b0, "disabled buzzer must remain zero");

            @(negedge clk);
            buzzer_enable = 1'b1;
            frequency_hz = 16'd30;
            repeat (16) begin
                @(posedge clk);
                #1;
                check(wave === 1'b0, "fractional buzzer period must not toggle early");
            end
            @(posedge clk);
            #1;
            check(wave === 1'b1, "fractional buzzer period must preserve requested average frequency");

            @(negedge clk);
            buzzer_enable = 1'b0;
            @(posedge clk);

            @(negedge clk);
            buzzer_enable = 1'b1;
            frequency_hz = 16'd0;
            repeat (12) @(posedge clk);
            #1;
            check(wave === 1'b0, "zero-frequency buzzer must remain zero");

            @(negedge clk);
            frequency_hz = 16'd50;
            repeat (10) @(posedge clk);
            #1;
            check(wave === 1'b1, "enabled buzzer must start oscillating");
            @(negedge clk);
            rst = 1'b1;
            @(posedge clk);
            #1;
            check(wave === 1'b0, "buzzer reset during tone must drive zero");
            @(negedge clk);
            rst = 1'b0;
            buzzer_enable = 1'b0;
        end
    endtask

    task automatic test_output_validity;
        integer cycle_number;
        begin
            $display("TEST: peripheral outputs never become X or Z after reset");
            apply_reset();
            for (cycle_number = 0; cycle_number < 32; cycle_number = cycle_number + 1) begin
                @(posedge clk);
                #1;
                check(!$isunknown({tx_ready, tx, rx_valid, rx_data, frame_error,
                                   digit_n, segment_n, wave}),
                      "peripheral output contains X or Z");
            end
        end
    endtask

    initial begin
        test_tx();
        test_rx();
        test_display();
        test_buzzer();
        test_output_validity();

        if (failures == 0) begin
            $display("PASS: all peripheral tests passed");
            $finish;
        end else begin
            $fatal(1, "FAIL: %0d peripheral assertions failed", failures);
        end
    end

    initial begin
        #200000;
        $fatal(1, "FAIL: peripheral testbench timeout");
    end
endmodule
