`timescale 1ns/1ps
// Behavioral substitutes for unavailable generated vendor IP, not timing models.
module clk_pll(input wire clk_in1, output wire soc_clk);
 assign soc_clk=clk_in1;
endmodule

module inst_ram(input wire clka, ena, input wire [3:0] wea,
 input wire [15:0] addra, input wire [31:0] dina, output reg [31:0] douta);
 reg [31:0] mem[0:65535];
 initial begin
  douta=0;
  $readmemh("upstream_rom.hex",mem);
 end
 // One synchronous read, retaining output when disabled; read-before-write.
 always @(posedge clka) if(ena) begin
  douta<=mem[addra];
  for(integer lane=0;lane<4;lane=lane+1)
   if(wea[lane]) mem[addra][lane*8+:8]<=dina[lane*8+:8];
 end
endmodule

module data_ram(input wire clka, ena, input wire [3:0] wea,
 input wire [11:0] addra, input wire [31:0] dina, output reg [31:0] douta);
 reg [31:0] mem[0:4095];
 initial begin
  douta=0;
  for(integer word=0;word<4096;word=word+1) mem[word]=0;
 end
 always @(posedge clka) if(ena) begin
  douta<=mem[addra];
  for(integer lane=0;lane<4;lane=lane+1)
   if(wea[lane]) mem[addra][lane*8+:8]<=dina[lane*8+:8];
 end
endmodule
