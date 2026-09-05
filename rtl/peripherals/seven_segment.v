`timescale 1ns/1ps

module seven_segment #(
    parameter integer CLOCK_HZ = 100000000,
    parameter integer SCAN_HZ = 1000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] value,
    output reg  [7:0]  digit_n,
    output reg  [7:0]  segment_n
);
    localparam integer CLKS_PER_SCAN = (SCAN_HZ > 0) ? (CLOCK_HZ / SCAN_HZ) : 0;

    integer   scan_count;
    reg [2:0] digit_index;
    reg [3:0] hex_digit;

    generate
        if ((CLOCK_HZ <= 0) || (SCAN_HZ <= 0) || (CLKS_PER_SCAN < 1)) begin : invalid_parameters
            initial begin
                $error("seven_segment requires positive rates and CLOCK_HZ/SCAN_HZ >= 1");
                $finish;
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            scan_count  <= 0;
            digit_index <= 3'd0;
        end else if (scan_count == CLKS_PER_SCAN - 1) begin
            scan_count  <= 0;
            digit_index <= digit_index + 1'b1;
        end else begin
            scan_count <= scan_count + 1;
        end
    end

    always @* begin
        digit_n = ~(8'b00000001 << digit_index);
        hex_digit = value >> (digit_index * 4);
        case (hex_digit)
            4'h0: segment_n = 8'b11000000;
            4'h1: segment_n = 8'b11111001;
            4'h2: segment_n = 8'b10100100;
            4'h3: segment_n = 8'b10110000;
            4'h4: segment_n = 8'b10011001;
            4'h5: segment_n = 8'b10010010;
            4'h6: segment_n = 8'b10000010;
            4'h7: segment_n = 8'b11111000;
            4'h8: segment_n = 8'b10000000;
            4'h9: segment_n = 8'b10010000;
            4'hA: segment_n = 8'b10001000;
            4'hB: segment_n = 8'b10000011;
            4'hC: segment_n = 8'b11000110;
            4'hD: segment_n = 8'b10100001;
            4'hE: segment_n = 8'b10000110;
            default: segment_n = 8'b10001110;
        endcase
    end
endmodule
