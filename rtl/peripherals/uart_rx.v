`timescale 1ns/1ps

module uart_rx #(
    parameter integer CLOCK_HZ = 100000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg        rx_valid,
    output reg  [7:0] rx_data,
    output reg        frame_error
);
    localparam integer CLKS_PER_BIT = (BAUD > 0) ? (CLOCK_HZ / BAUD) : 0;
    localparam integer HALF_CLKS = CLKS_PER_BIT / 2;
    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg       rx_meta;
    reg       rx_sync;
    reg [1:0] state;
    reg [2:0] bit_index;
    integer   clock_count;

    generate
        if ((CLOCK_HZ <= 0) || (BAUD <= 0) || (CLKS_PER_BIT < 4)) begin : invalid_parameters
            initial begin
                $error("uart_rx requires positive rates and CLOCK_HZ/BAUD >= 4");
                $finish;
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rx_valid    <= 1'b0;
            rx_data     <= 8'h00;
            frame_error <= 1'b0;
            state       <= IDLE;
            bit_index   <= 3'd0;
            clock_count <= 0;
        end else begin
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;

            case (state)
                IDLE: begin
                    clock_count <= 0;
                    bit_index   <= 3'd0;
                    if (!rx_sync) begin
                        state       <= START;
                        clock_count <= HALF_CLKS - 1;
                    end
                end

                START: begin
                    if (clock_count == 0) begin
                        if (!rx_sync) begin
                            state       <= DATA;
                            clock_count <= CLKS_PER_BIT - 1;
                            bit_index   <= 3'd0;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clock_count <= clock_count - 1;
                    end
                end

                DATA: begin
                    if (clock_count == 0) begin
                        rx_data[bit_index] <= rx_sync;
                        clock_count       <= CLKS_PER_BIT - 1;
                        if (bit_index == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clock_count <= clock_count - 1;
                    end
                end

                STOP: begin
                    if (clock_count == 0) begin
                        if (rx_sync)
                            rx_valid <= 1'b1;
                        else
                            frame_error <= 1'b1;
                        state       <= IDLE;
                        clock_count <= 0;
                    end else begin
                        clock_count <= clock_count - 1;
                    end
                end

                default: begin
                    state       <= IDLE;
                    clock_count <= 0;
                end
            endcase
        end
    end
endmodule
