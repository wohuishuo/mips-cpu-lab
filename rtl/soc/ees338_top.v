`timescale 1ns/1ps
module ees338_top(input wire clk100,reset_n,uart_rx,
 input wire [7:0] switches,
 output wire uart_tx,output wire [7:0] led,digit,segment0,segment1,
 output wire buzzer_out);
 reg [2:0] divider=0;
 reg divided_clock=0;
 always @(posedge clk100) begin
  if(divider==4)begin divider<=0;divided_clock<=~divided_clock;end
  else divider<=divider+1'b1;
 end
 wire clk;
 BUFG clock_buffer(.I(divided_clock),.O(clk));
 (* ASYNC_REG="TRUE" *) reg [2:0] reset_sync=0;
 always @(posedge clk or negedge reset_n)
  if(!reset_n)reset_sync<=0;else reset_sync<={reset_sync[1:0],1'b1};
 (* ASYNC_REG="TRUE" *) reg [7:0] switch_meta=0,switch_sync=0;
 always @(posedge clk)begin switch_meta<=switches;switch_sync<=switch_meta;end
 wire [7:0] dn,sn;
 lab_soc soc(.clk(clk),.rst(!reset_sync[2]),.uart_rx_pin(uart_rx),.switches(switch_sync),
 .uart_tx_pin(uart_tx),.led(led),.digit_n(dn),.segment_n(sn),.buzzer_pin(buzzer_out),
 .debug_pc(),.debug_result(),.debug_stores(),.debug_done());
 assign digit=~dn;
 assign segment0=~sn;
 assign segment1=~sn;
endmodule
