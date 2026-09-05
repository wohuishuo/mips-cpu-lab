`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLOCK_HZ = 100000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_valid,
    input  wire [7:0] tx_data,
    output wire       tx_ready,
    output wire       tx
);
    localparam integer CLKS_PER_BIT = (BAUD > 0) ? (CLOCK_HZ / BAUD) : 0;

    reg        busy;
    reg [9:0]  frame;
    reg [3:0]  bit_index;
    integer    clock_count;

    assign tx_ready = ~busy;
    assign tx = busy ? frame[bit_index] : 1'b1;

    generate
        if ((CLOCK_HZ <= 0) || (BAUD <= 0) || (CLKS_PER_BIT < 4)) begin : invalid_parameters
            initial begin
                $error("uart_tx requires positive rates and CLOCK_HZ/BAUD >= 4");
                $finish;
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            busy        <= 1'b0;
            frame       <= 10'h3ff;
            bit_index   <= 4'd0;
            clock_count <= 0;
        end else if (!busy) begin
            clock_count <= 0;
            bit_index   <= 4'd0;
            if (tx_valid) begin
                frame <= {1'b1, tx_data, 1'b0};
                busy  <= 1'b1;
            end
        end else if (clock_count == CLKS_PER_BIT - 1) begin
            clock_count <= 0;
            if (bit_index == 4'd9) begin
                busy      <= 1'b0;
                bit_index <= 4'd0;
            end else begin
                bit_index <= bit_index + 1'b1;
            end
        end else begin
            clock_count <= clock_count + 1;
        end
    end
endmodule
