`timescale 1ns/1ps
module tb_mars_program;
reg clk=0,rst=1;
always #5 clk=~clk;
reg [31:0] rom[0:1023],ram[0:1023];
wire [31:0] pc,da,dw,trace_pc,trace_instr,trace_wdata;
wire [3:0] strb;
wire valid,we,illegal;
wire [4:0] rd;
wire imem_in_range=(pc>=32'h00400000 && pc<32'h00401000);
wire dmem_in_range=(da>=32'h10010000 && da<32'h10011000);
integer i,fd,failures=0,cycles=0,stores=0;
reg [31:0] f0,f1,next_f;
single_cycle_cpu #(.RESET_PC(32'h00400000)) dut(.clk(clk),.rst(rst),
 .imem_addr(pc),.imem_rdata(imem_in_range?rom[pc[11:2]]:32'b0),.dmem_addr(da),.dmem_wdata(dw),
 .dmem_wstrb(strb),.dmem_rdata(dmem_in_range?ram[da[11:2]]:32'b0),.trace_valid(valid),
 .trace_pc(trace_pc),.trace_instr(trace_instr),.trace_we(we),.trace_rd(rd),
 .trace_wdata(trace_wdata),.illegal(illegal));
always @(posedge clk) if(!rst) begin
 cycles=cycles+1;
 if(!imem_in_range)begin failures=failures+1;$display("FAIL instruction address outside ROM pc=%h",pc);end
 if(illegal)begin failures=failures+1;$display("FAIL unexpected illegal pc=%h",pc);end
 if(|strb)begin
  if(!dmem_in_range)begin failures=failures+1;$display("FAIL store address outside RAM addr=%h",da);end
  if(strb!==4'b1111)begin failures=failures+1;$display("FAIL non-word store addr=%h strobes=%h",da,strb);end
  if(da!==32'h10010000+stores*4)begin failures=failures+1;$display("FAIL store[%0d] addr=%h expected=%h",stores,da,32'h10010000+stores*4);end
  stores=stores+1;
 end
 if(dmem_in_range)for(integer lane=0;lane<4;lane=lane+1)if(strb[lane])ram[da[11:2]][lane*8+:8]<=dw[lane*8+:8];
 $fdisplay(fd,"%0d,%08h,%08h,%0d,%0d,%08h,%08h,%08h,%01h",cycles,trace_pc,trace_instr,we,rd,trace_wdata,da,dw,strb);
end
initial begin
 $readmemh("../mars/rom.hex",rom);
 for(i=0;i<1024;i=i+1)ram[i]=0;
 fd=$fopen("trace.csv","w");
 $fdisplay(fd,"cycle,pc,instruction,reg_we,reg_rd,reg_data,mem_addr,mem_data,mem_strobes");
 repeat(3)@(negedge clk);rst=0;
 repeat(150)@(negedge clk);
 f0=0;f1=1;
 for(i=0;i<12;i=i+1)begin
  if(ram[i]!==f0)begin failures=failures+1;$display("FAIL F[%0d] actual=%h expected=%h",i,ram[i],f0);end
  next_f=f0+f1;f0=f1;f1=next_f;
 end
 if(stores!=12)begin failures=failures+1;$display("FAIL store count %0d",stores);end
 if(failures==0)$display("PASS MARS_TO_RTL fibonacci_words=12 stores=%0d cycles=%0d",stores,cycles);
 else $display("FAIL MARS_TO_RTL failures=%0d",failures);
 $fclose(fd);$finish;
end
endmodule
