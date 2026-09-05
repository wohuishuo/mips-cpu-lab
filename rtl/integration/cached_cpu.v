`timescale 1ns/1ps
// Blocking CPU/cache composition. MMIO is a separate, uncached handshake port.
module cached_cpu #(
 parameter RESET_PC=32'hbfc00000, EXCEPTION_PC=32'hbfc00380,
 parameter integer SETS=16, WORDS_PER_LINE=4,
 parameter MMIO_BASE=32'hffff0000, MMIO_MASK=32'hffff0000
)(
 input wire clk,rst,
 output wire [31:0] imem_addr,input wire [31:0] imem_rdata,
 input wire [5:0] hw_irq,
 output wire mem_valid,mem_write,output wire [31:0] mem_addr,mem_wdata,
 output wire [3:0] mem_wstrb,input wire mem_ready,input wire [31:0] mem_rdata,
 output wire mmio_valid,mmio_write,output wire [31:0] mmio_addr,mmio_wdata,
 output wire [3:0] mmio_wstrb,input wire mmio_ready,input wire [31:0] mmio_rdata,
 output wire trace_valid,output wire [31:0] trace_pc,trace_instr,
 output wire trace_we,output wire [4:0] trace_rd,output wire [31:0] trace_wdata,
 output wire [3:0] trace_mem_we,output wire [31:0] trace_mem_addr,trace_mem_wdata,
 output wire exception_valid,output wire [4:0] exception_code,
 output wire [31:0] exception_epc,output wire exception_bd,
 output wire [31:0] cycle_count,retired_count,stall_count,
 output wire [31:0] hit_count,miss_count,writeback_count
);
 wire cpu_valid,cpu_write,cpu_ready,cache_ready;
 wire [31:0] cpu_addr,cpu_wdata,cpu_rdata,cache_rdata;
 wire [3:0] cpu_wstrb;
 wire uncached=(cpu_addr&MMIO_MASK)==(MMIO_BASE&MMIO_MASK);
 assign mmio_valid=cpu_valid&&uncached;
 assign mmio_write=cpu_write;
 assign mmio_addr=cpu_addr;
 assign mmio_wdata=cpu_wdata;
 assign mmio_wstrb=mmio_valid?cpu_wstrb:4'b0;
 assign cpu_ready=uncached?mmio_ready:cache_ready;
 assign cpu_rdata=uncached?mmio_rdata:cache_rdata;
 pipeline_cpu #(.RESET_PC(RESET_PC),.EXCEPTION_PC(EXCEPTION_PC)) core(
  .clk(clk),.rst(rst),.imem_addr(imem_addr),.imem_rdata(imem_rdata),.hw_irq(hw_irq),
  .dmem_valid(cpu_valid),.dmem_write(cpu_write),.dmem_addr(cpu_addr),.dmem_wdata(cpu_wdata),
  .dmem_wstrb(cpu_wstrb),.dmem_ready(cpu_ready),.dmem_rdata(cpu_rdata),
  .trace_valid(trace_valid),.trace_pc(trace_pc),.trace_instr(trace_instr),
  .trace_we(trace_we),.trace_rd(trace_rd),.trace_wdata(trace_wdata),
  .trace_mem_we(trace_mem_we),.trace_mem_addr(trace_mem_addr),.trace_mem_wdata(trace_mem_wdata),
  .exception_valid(exception_valid),.exception_code(exception_code),
  .exception_epc(exception_epc),.exception_bd(exception_bd),
  .cycle_count(cycle_count),.retired_count(retired_count),.stall_count(stall_count));
 data_cache #(.SETS(SETS),.WORDS_PER_LINE(WORDS_PER_LINE)) cache(
  .clk(clk),.rst(rst),.cpu_valid(cpu_valid&&!uncached),.cpu_write(cpu_write),
  .cpu_addr(cpu_addr),.cpu_wdata(cpu_wdata),.cpu_wstrb(cpu_wstrb),
  .cpu_ready(cache_ready),.cpu_rdata(cache_rdata),
  .mem_valid(mem_valid),.mem_write(mem_write),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
  .mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),
  .hit_count(hit_count),.miss_count(miss_count),.writeback_count(writeback_count));
endmodule
