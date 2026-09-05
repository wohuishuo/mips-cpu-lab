`timescale 1ns/1ps
// Reusable UART light controller and atomic telemetry transport, 8N1.
module uart_control #(parameter integer CLOCK_HZ=10000000, BAUD=115200)(
 input wire clk,rst,rx,
 input wire [287:0] telemetry,
 output wire tx,
 output reg led_override,
 output reg [7:0] led_value,
 output reg cpu_reset,
 output wire beep,
 output reg [31:0] rx_errors
);
 wire received,frame_error,tx_ready;
 wire [7:0] rx_data;
 reg [319:0] snapshot;
 reg [5:0] bytes_left;
 reg [31:0] beep_left;
 uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) receiver(
 .clk(clk),.rst(rst),.rx(rx),.rx_valid(received),.rx_data(rx_data),.frame_error(frame_error));
 uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) transmitter(
 .clk(clk),.rst(rst),.tx_valid(bytes_left!=0),.tx_data(snapshot[7:0]),.tx_ready(tx_ready),.tx(tx));
 assign beep = beep_left != 0;
 always @(posedge clk) begin
  if(rst) begin
   snapshot<=0;bytes_left<=0;beep_left<=0;led_override<=0;led_value<=0;cpu_reset<=0;rx_errors<=0;
  end else begin
   cpu_reset<=0;
   if(beep_left!=0) beep_left<=beep_left-1;
   if(frame_error) rx_errors<=rx_errors+1;
   if(bytes_left!=0 && tx_ready) begin snapshot<=snapshot>>8;bytes_left<=bytes_left-1;end
   if(received) case(rx_data)
    8'h3f: if(bytes_left==0) begin snapshot<={telemetry,32'h5550434d};bytes_left<=40;end
    8'h30: begin led_override<=1;led_value<=0;end
    8'h31: begin led_override<=1;led_value<=8'hff;end
    8'h61: led_override<=0;
    8'h62: beep_left<=CLOCK_HZ/2;
    8'h72: cpu_reset<=1;
    default: begin end
   endcase
  end
 end
endmodule
