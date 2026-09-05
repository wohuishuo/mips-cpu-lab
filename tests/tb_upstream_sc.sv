`timescale 1ns/1ps
// Preliminary supplied lab5 trace replay, zero-cycle SC memory model.
// The synchronous teach_soc adapter is a separate acceptance test.
module tb_upstream_sc;
 reg clk=0,rst=1;
 always #5 clk=~clk;
 reg [31:0] rom[0:65535],ram[0:4095];
 wire [31:0] ia,da,dw,dr;
 wire [3:0] st;
 wire tv,tw,illegal;
 wire [31:0] pc,instr,value;
 wire [4:0] rd;
 reg [31:0] display=0,led=0;
 wire conf=da[28:16]==13'h1faf;
 wire [31:0] mmio=(da[15:0]==16'h8004) ? 32'hff : (da[15:0]==16'h8000) ? display : (da[15:0]==16'h8008) ? led : 0;
 assign dr=conf?mmio:ram[da[13:2]];
 single_cycle_cpu cpu(.clk(clk),.rst(rst),.imem_addr(ia),.imem_rdata(rom[ia[17:2]]),
 .dmem_addr(da),.dmem_wdata(dw),.dmem_wstrb(st),.dmem_rdata(dr),
 .trace_valid(tv),.trace_pc(pc),.trace_instr(instr),.trace_we(tw),.trace_rd(rd),.trace_wdata(value),.illegal(illegal));
 integer ref_file,rows=0,cycles=0,got,flag;
 reg [31:0] ref_pc,ref_data;
 reg [4:0] ref_rd;
 initial begin
  $readmemh("upstream_rom.hex",rom);
  for(integer i=0;i<4096;i++)ram[i]=0;
  ref_file=$fopen("golden_trace.txt","r");
  if(!ref_file)$fatal(1,"FAIL UPSTREAM missing golden trace");
  repeat(5)@(negedge clk);rst=0;
 end
 always @(posedge clk)if(!rst)begin
  cycles=cycles+1;
  if(illegal)$fatal(1,"FAIL UPSTREAM illegal pc=%h instruction=%h",ia,instr);
  if(tw && rd!=0)begin
   got=$fscanf(ref_file,"%h %h %h %h",flag,ref_pc,ref_rd,ref_data);
   if(got!=4 || flag!=1 || pc!==ref_pc || rd!==ref_rd || value!==ref_data)
    $fatal(1,"FAIL UPSTREAM row=%0d actual=%h/%h/%h expected=%h/%h/%h",rows,pc,rd,value,ref_pc,ref_rd,ref_data);
   rows=rows+1;
  end
  if(|st)begin
   if(conf)begin
    if(da[15:0]==16'h8000)display<=dw;
    if(da[15:0]==16'h8008)led<=dw;
   end else for(integer b=0;b<4;b++)if(st[b])ram[da[13:2]][8*b+:8]<=dw[8*b+:8];
  end
  if(pc==32'hbfc00100)begin
   if(led!=15)$fatal(1,"FAIL UPSTREAM final LED=%h display=%h",led,display);
   $display("PASS UPSTREAM_SC rows=%0d cycles=%0d display=%h led=%h",rows,cycles,display,led);$finish;
  end
  if(cycles>200000)$fatal(1,"FAIL UPSTREAM timeout pc=%h",pc);
 end
endmodule
