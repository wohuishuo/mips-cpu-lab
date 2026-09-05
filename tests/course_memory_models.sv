`timescale 1ns/1ps
// lab3 XCI: distributed memories, 1024x32, non_registered input/output.
// No fabricated synchronous read latency: spo changes with address/data.
module inst_rom(input wire [9:0] a,output wire [31:0] spo);
 reg [31:0] mem[0:1023];
 initial $readmemh("program.hex",mem);
 assign spo=mem[a];
endmodule
module data_ram(input wire [9:0] a,input wire [31:0] d,
 input wire clk,we,output wire [31:0] spo);
 reg [31:0] mem[0:1023];
 integer i;
 initial for(i=0;i<1024;i=i+1)mem[i]=0;
 always @(posedge clk)if(we)mem[a]<=d;
 assign spo=mem[a];
endmodule
