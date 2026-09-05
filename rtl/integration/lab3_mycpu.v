`timescale 1ns/1ps
// Drop-in missing mycpu for lab3/single_cycle. Course address layout and
// active-low reset retained. The course bus supports aligned WORD stores only.
module mycpu(
 input wire rstn,clk,
 output wire [31:0] inst_rom_addr,input wire [31:0] inst_rom_rdata,
 output wire [31:0] data_ram_addr,data_ram_wdata,
 output wire data_ram_wen,input wire [31:0] data_ram_rdata
);
 wire [3:0] wstrb;
 wire illegal;
 single_cycle_cpu #(.RESET_PC(32'hbfc00000)) core(
  .clk(clk),.rst(~rstn),.imem_addr(inst_rom_addr),.imem_rdata(inst_rom_rdata),
  .dmem_addr(data_ram_addr),.dmem_wdata(data_ram_wdata),.dmem_wstrb(wstrb),
  .dmem_rdata(data_ram_rdata),.trace_valid(),.trace_pc(),.trace_instr(),
  .trace_we(),.trace_rd(),.trace_wdata(),.illegal(illegal));
 assign data_ram_wen=rstn && (wstrb==4'b1111);
 // Byte/halfword stores cannot be represented by the original single-bit WE.
 // They are deliberately not converted to destructive full-word stores.
endmodule
