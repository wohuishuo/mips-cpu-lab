`timescale 1ns/1ps
// Lab simulation compatibility adapter; see docs/teach-soc.md for clock limits.
// SRAM/bridge/confreg sample clk rising edges; CPU advances on falling edges.
// Do not include this inverted-clock adapter in the independently timed board SoC.
module mycpu_top(
 input wire clk, resetn,
 input wire [5:0] \int ,
 output wire inst_sram_en,
 output wire [3:0] inst_sram_wen,
 output wire [31:0] inst_sram_addr, inst_sram_wdata,
 input wire [31:0] inst_sram_rdata,
 output wire data_sram_en,
 output wire [3:0] data_sram_wen,
 output wire [31:0] data_sram_addr, data_sram_wdata,
 input wire [31:0] data_sram_rdata,
 output wire [31:0] debug_wb_pc,
 output wire [3:0] debug_wb_rf_wen,
 output wire [4:0] debug_wb_rf_wnum,
 output wire [31:0] debug_wb_rf_wdata
);
 wire core_clk = ~clk;
 wire [31:0] imem_addr, dmem_addr;
 wire dmem_valid, dmem_write;
 wire [3:0] dmem_wstrb;
 wire trace_valid, trace_we;
 wire [31:0] trace_instr;
 wire [3:0] trace_mem_we;
 wire [31:0] trace_mem_addr, trace_mem_wdata;
 wire exception_valid, exception_bd;
 wire [4:0] exception_code;
 wire [31:0] exception_epc, cycle_count, retired_count, stall_count;

 assign inst_sram_en = resetn;
 assign inst_sram_wen = 4'b0;
 assign inst_sram_wdata = 32'b0;
 assign inst_sram_addr = {3'b0,imem_addr[28:0]};
 assign data_sram_en = resetn && dmem_valid;
 assign data_sram_wen = (data_sram_en && dmem_write) ? dmem_wstrb : 4'b0;
 assign data_sram_addr = {3'b0,dmem_addr[28:0]};
 assign debug_wb_rf_wen = {4{resetn && trace_valid && trace_we}};

 pipeline_cpu core(
  .clk(core_clk), .rst(~resetn), .hw_irq(\int ),
  .imem_addr(imem_addr), .imem_rdata(inst_sram_rdata),
  .dmem_valid(dmem_valid), .dmem_write(dmem_write), .dmem_addr(dmem_addr),
  .dmem_wdata(data_sram_wdata), .dmem_wstrb(dmem_wstrb),
  .dmem_ready(resetn), .dmem_rdata(data_sram_rdata),
  .trace_valid(trace_valid), .trace_pc(debug_wb_pc), .trace_instr(trace_instr),
  .trace_we(trace_we), .trace_rd(debug_wb_rf_wnum), .trace_wdata(debug_wb_rf_wdata),
  .trace_mem_we(trace_mem_we), .trace_mem_addr(trace_mem_addr), .trace_mem_wdata(trace_mem_wdata),
  .exception_valid(exception_valid), .exception_code(exception_code),
  .exception_epc(exception_epc), .exception_bd(exception_bd),
  .cycle_count(cycle_count), .retired_count(retired_count), .stall_count(stall_count)
 );
endmodule
