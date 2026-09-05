`timescale 1ns/1ps
module tb_pipeline;
reg clk=0;always #5 clk=~clk;
reg rst=1;wire [31:0] ia,da,dw;reg [31:0] rom[0:4095],mem[0:255];wire [3:0] ds;wire dv,write;
integer cycle=0,mode=0;reg force_wait=0;wire ready=!force_wait&&((mode==0)||(mode==1&&cycle%7<2)||(mode>=2&&cycle%13==5));reg [5:0] irq=0;
wire tv,tw;wire [31:0] tp,ti,td;wire [4:0] tr;wire [3:0] tm;wire [31:0] tma,tmd;wire ev,eb;wire[4:0] ec;wire[31:0] ee,cc,rc,sc;
pipeline_cpu #(.RESET_PC(0),.EXCEPTION_PC(32'h1000)) dut(.clk(clk),.rst(rst),.imem_addr(ia),.imem_rdata(rom[ia[13:2]]),.dmem_valid(dv),.dmem_write(write),.dmem_addr(da),.dmem_wdata(dw),.dmem_wstrb(ds),.dmem_ready(ready),.dmem_rdata(mem[da[9:2]]),.hw_irq(irq),.trace_valid(tv),.trace_pc(tp),.trace_instr(ti),.trace_we(tw),.trace_rd(tr),.trace_wdata(td),.trace_mem_we(tm),.trace_mem_addr(tma),.trace_mem_wdata(tmd),.exception_valid(ev),.exception_code(ec),.exception_epc(ee),.exception_bd(eb),.cycle_count(cc),.retired_count(rc),.stall_count(sc));
integer fd,n,i,j,k,got,stagefile,retirefile,scenario,excount,stores,store_counts[0:63],irqcase;reg[31:0] ep,ei,ew,er,ed,em,ema,emd;reg held=0;reg[68:0] request;
reg fault_testing=0;reg[4:0] expected_code;reg[31:0] expected_epc,expected_bad;reg expected_bd;
reg irq_testing=0,irq_armed=0;reg[31:0] irq_epc;
function[31:0] encI(input[5:0] op,input[4:0] rs,rt,input[15:0] imm);encI={op,rs,rt,imm};endfunction
task reset_case;
 begin
  rst=1;irq=0;repeat(3)@(negedge clk);
  for(i=0;i<4096;i=i+1)rom[i]=0;
  for(i=0;i<256;i=i+1)mem[i]=0;
  for(i=0;i<64;i=i+1)store_counts[i]=0;
  excount=0;stores=0;
 end
endtask
always @(posedge clk) begin
 cycle<=cycle+1;
 if(!rst)begin
  if(held && (!dv || {write,da,dw,ds}!==request))$fatal(1,"FAIL request unstable");
  held<=dv&&!ready;request<={write,da,dw,ds};
  if(dv&&ready&&write)begin
   if(da==0)stores=stores+1;
   if(irq_testing)store_counts[da[7:2]]=store_counts[da[7:2]]+1;
   for(k=0;k<4;k=k+1)if(ds[k])mem[da[9:2]][k*8+:8]<=dw[k*8+:8];
  end
  if(ev&&fault_testing)begin
   excount=excount+1;
   if(scenario==12)irq<=0;
   if(ec!==expected_code||ee!==expected_epc||eb!==expected_bd)$fatal(1,"FAIL exception case %d code %d/%d EPC %h/%h BD %d/%d",scenario,ec,expected_code,ee,expected_epc,eb,expected_bd);
  end
  if(tv)$fwrite(retirefile,"%0d,%0d,%h,%h,%b,%0d,%h,%h,%h,%h\n",mode,cycle,tp,ti,tw,tr,td,tm,tma,tmd);
  if(ev&&irq_testing)begin
   excount=excount+1;irq_epc=ee;irq<=0;
   if(ec!=0||eb||excount!=1)$fatal(1,"FAIL interrupt precision case %d",irqcase);
   if(irqcase==0&&ee!=28)$fatal(1,"FAIL interrupted store restart EPC %h",ee);
   if(irqcase==1&&ee!=40)$fatal(1,"FAIL delay-slot IRQ EPC %h",ee);
  end
  $fwrite(stagefile,"%0d,%0d,%b,%h,%h,%b,%h,%h,%b,%h,%h,%b,%h,%h,%b,%h,%h,%b,%b\n",mode,cycle,dut.if_valid,ia,dut.if_instr,dut.id_valid,dut.id_pc,dut.id_instr,dut.ex_valid,dut.ex_pc,dut.ex_instr,dut.mem_valid,dut.mem_pc,dut.mem_instr,dut.wb_valid,dut.wb_pc,dut.wb_instr,dv,ready);
 end else held<=0;
end
always @(negedge clk)begin
 if(!rst&&irq_testing&&irq_armed)begin
  if((irqcase==0&&dv&&write&&da==0&&!ready)||(irqcase==1&&dut.ex_valid&&dut.ex_bd))begin irq=1;irq_armed=0;end
 end
end
initial begin
 stagefile=$fopen("pipeline_stages.csv","w");$fwrite(stagefile,"mode,cycle,if_valid,if_pc,if_instr,id_valid,id_pc,id_instr,ex_valid,ex_pc,ex_instr,mem_valid,mem_pc,mem_instr,wb_valid,wb_pc,wb_instr,dmem_valid,dmem_ready\n");
 retirefile=$fopen("pipeline_retirements.csv","w");$fwrite(retirefile,"mode,cycle,pc,instr,we,rd,wdata,mem_strobe,mem_addr,mem_data\n");
 for(i=0;i<4096;i=i+1)rom[i]=0;
 $readmemh("pipeline_program.hex",rom);
 for(mode=0;mode<3;mode=mode+1)begin
  rst=1;repeat(3)@(negedge clk);for(i=0;i<256;i=i+1)mem[i]=0;rst=0;
  fd=$fopen("pipeline_expected.txt","r");got=$fscanf(fd,"%d\n",n);
  for(j=0;j<n;j=j+1)begin
   got=$fscanf(fd,"%h %h %h %h %h %h %h %h\n",ep,ei,ew,er,ed,em,ema,emd);
   @(posedge clk);while(!tv)begin if(ev)$fatal(1,"FAIL unexpected exception %d PC %h",ec,ee);@(posedge clk);end
   if(tp!==ep||ti!==ei||tw!==ew[0]||(tw&&(tr!==er[4:0]||td!==ed))||tm!==em[3:0]||(tm&&(tma!==ema||tmd!==emd)))$fatal(1,"FAIL row %d mode %d PC %h/%h data %h/%h we %d/%d mem %h/%h",j,mode,tp,ep,td,ed,tw,ew,tm,em);
  end
  $fclose(fd);@(negedge clk);
  if(rc!=n)$fatal(1,"FAIL retired counter");
  $display("TRACE mode=%0d retirements=%0d cycles=%0d stalls=%0d",mode,rc,cc,sc);
 end
 // Real exception handlers read CP0, change EPC, ERET and execute a marker store.
 fault_testing=1;mode=2;
 for(scenario=0;scenario<13;scenario=scenario+1)begin
  reset_case();
  expected_code=8;expected_epc=8;expected_bd=0;expected_bad=0;
  rom[0]=encI(9,0,1,55);rom[1]=encI(43,0,1,0);rom[2]=32'h0000000c;
  rom[3]=encI(43,0,1,4);rom[4]=encI(9,0,2,77);rom[5]=encI(43,0,2,8);
  case(scenario)
   1:begin rom[2]=32'h0000000d;expected_code=9;end
   2:begin rom[2]=32'hfc000000;expected_code=10;end
   3:begin rom[2]=encI(35,0,3,1);expected_code=4;expected_bad=1;end
   4:begin rom[2]=encI(43,0,1,2);expected_code=5;expected_bad=2;end
   5:begin rom[0]=encI(15,0,1,16'h8000);rom[2]=encI(8,1,3,16'hffff);expected_code=12;end
   6:begin
    rom[2]=encI(4,1,1,2);rom[3]=32'h0000000c;rom[4]=encI(43,0,1,4);rom[5]=encI(9,0,2,77);rom[6]=encI(43,0,2,8);expected_bd=1;
   end
   7:begin rom[2]=encI(4,1,1,2);rom[3]=32'h08000008;rom[4]=encI(43,0,1,4);rom[5]=encI(9,0,2,77);rom[6]=encI(43,0,2,8);expected_bd=1;expected_code=10;end
   8:begin rom[0]=encI(9,0,1,26);rom[2]=32'h00200008;rom[3]=0;rom[6]=encI(43,0,1,4);rom[8]=encI(9,0,2,77);rom[9]=encI(43,0,2,8);expected_epc=26;expected_code=4;expected_bad=26;end
   9:begin rom[0]=encI(15,0,1,16'h8000);rom[2]=32'h00211820;expected_code=12;end
   10:begin rom[0]=encI(15,0,1,16'h8000);rom[1]=encI(9,0,2,1);rom[2]=32'h00221822;expected_code=12;end
   11:begin rom[2]=encI(33,0,3,3);expected_code=4;expected_bad=3;end
   12:begin rom[0]=encI(13,0,2,16'h0401);rom[1]=32'h40826000;irq=1;end
  endcase
  rom[1024]=32'h40146800; // mfc0 r20,Cause
  rom[1025]=32'h40157000; // mfc0 r21,EPC
  rom[1026]=32'h40164000; // mfc0 r22,BadVAddr
  rom[1027]=32'h40176000; // mfc0 r23,Status
  rom[1028]=encI(9,0,24,scenario==8?32:(expected_bd?20:16));
  rom[1029]=32'h40987000; // mtc0 r24,EPC
  rom[1030]=32'h42000018;
  rst=0;
  while(mem[2]!==77)@(negedge clk);
  if(excount!=1||mem[1]!==0||dut.regs[21]!==expected_epc||dut.regs[20][6:2]!==expected_code||dut.regs[20][31]!==expected_bd||!dut.regs[23][1]||dut.status[1])$fatal(1,"FAIL handler case %d count %d",scenario,excount);
  if((expected_code==4||expected_code==5)&&dut.regs[22]!==expected_bad)$fatal(1,"FAIL badvaddr");
  if(scenario!=10&&scenario!=12&&stores!=1)$fatal(1,"FAIL older store repeated");
 end
 fault_testing=0;irq_testing=1;
 for(irqcase=0;irqcase<3;irqcase=irqcase+1)begin
  reset_case();irq_armed=irqcase!=2;
  rom[0]=encI(9,0,1,1);rom[1]=32'h40804800; // mtc0 zero,Count
  rom[2]=encI(9,0,2,80);rom[3]=32'h40825800; // Compare=80
  rom[4]=encI(13,0,2,irqcase==2?16'h8001:16'h0401);rom[5]=32'h40826000;
  rom[6]=encI(43,0,1,0);rom[7]=encI(9,1,1,1);rom[8]=encI(43,0,1,4);rom[9]=encI(9,1,1,1);
  if(irqcase==1)begin
   rom[6]=encI(4,1,1,3);rom[7]=encI(43,0,1,0);rom[8]=encI(43,0,1,200);rom[9]=0;
   rom[10]=encI(9,1,1,1);rom[11]=encI(43,0,1,4);rom[12]=encI(9,1,1,1);
  end
  for(j=2;j<20;j=j+1)begin
   rom[(irqcase==1?13:10)+(j-2)*2]=encI(43,0,1,j*4);
   rom[(irqcase==1?14:11)+(j-2)*2]=encI(9,1,1,1);
  end
  rom[50]=encI(9,0,3,77);rom[51]=encI(43,0,3,252);rom[52]=32'h08000034;
  rom[1024]=32'h40157000;rom[1025]=32'h40146800;
  rom[1026]=32'h40805800; // Clear timer by Compare write.
  rom[1027]=32'h42000018; // Return to original, uncommitted EPC.
  rst=0;
  while(mem[63]!==77)@(negedge clk);
  if(excount!=1||dut.regs[21]!==irq_epc||dut.status[1])$fatal(1,"FAIL IRQ resume case %d count %d",irqcase,excount);
  for(j=0;j<20;j=j+1)if(mem[j]!==j+1||store_counts[j]!=1)$fatal(1,"FAIL duplicate/lost store case %d word %d value %h count %d",irqcase,j,mem[j],store_counts[j]);
  if(mem[50]!=0)$fatal(1,"FAIL forbidden branch store");
  @(negedge clk);
 end
 irq_testing=0;reset_case();
 // A taken backward branch targets address zero exactly; its delay slot runs twice.
 rom[0]=encI(9,1,1,1);rom[1]=encI(10,1,2,2);rom[2]=encI(5,2,0,16'hfffd);rom[3]=encI(9,3,3,1);rom[4]=encI(43,0,3,0);
 rst=0;while(mem[0]!==2)@(negedge clk);
 if(dut.regs[1]!=2||dut.regs[3]!=2)$fatal(1,"FAIL target zero/delay slot");
 reset_case();force_wait=1;
 rom[0]=encI(9,0,1,123);rom[1]=encI(43,0,1,0);rst=0;
 while(!dv)@(negedge clk);
 repeat(4)@(negedge clk);
 rst=1;repeat(3)@(negedge clk);
 if(dv||tv||ev||cc||rc||sc||dut.regs[1]||ia)$fatal(1,"FAIL reset during memory wait");
 if(mem[0]!==0)$fatal(1,"FAIL unaccepted store during reset");
 force_wait=0;rst=0;
 while(mem[0]!==123)@(negedge clk);
 $display("PASS pipeline independent traces, waits, 13 precise exception handlers, external/timer IRQ and active reset");$finish;
end
initial begin #2000000;$fatal(1,"FAIL timeout");end
endmodule
