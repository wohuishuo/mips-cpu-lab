`timescale 1ns/1ps

module buzzer #(
    parameter integer CLOCK_HZ = 100000000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [15:0] frequency_hz,
    output reg         wave
);
    localparam [32:0] CLOCK_RATE = CLOCK_HZ;

    reg [31:0] phase_accumulator;
    wire [32:0] phase_step = {16'd0, frequency_hz, 1'b0};
    wire [32:0] phase_sum = {1'b0, phase_accumulator} + phase_step;

    generate
        if (CLOCK_HZ <= 0) begin : invalid_parameters
            initial begin
                $error("buzzer requires CLOCK_HZ > 0");
                $finish;
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (rst || !enable || (frequency_hz == 0)) begin
            phase_accumulator <= 32'd0;
            wave              <= 1'b0;
        end else if (phase_step >= CLOCK_RATE) begin
            phase_accumulator <= 32'd0;
            wave              <= ~wave;
        end else if (phase_sum >= CLOCK_RATE) begin
            phase_accumulator <= phase_sum - CLOCK_RATE;
            wave              <= ~wave;
        end else begin
            phase_accumulator <= phase_sum[31:0];
        end
    end
endmodule
