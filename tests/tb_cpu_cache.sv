`timescale 1ns/1ps
module tb_cpu_cache;
`ifdef JOINT_SMALL
localparam SETS=4, WORDS=2;
`else
localparam SETS=16, WORDS=4;
`endif
reg clk=0;always #5 clk=~clk;
reg rst=1;
reg [31:0] rom[0:1023],memory[0:8191],expected_memory[0:8191];
wire [31:0] ia,ba,bw,br,ma,mw,mr;
wire bv,bwrite,mv,mwrite;wire [3:0] bs,ms;
reg ready_back=0,ready_mmio=0;
wire tv,tw,ev,eb;wire [31:0] tp,ti,td,tma,tmd,ee,cycles,retired,stalls,hits,misses,writebacks;
wire [4:0] tr,ec;wire [3:0] tm;
assign br=memory[ba[14:2]];
assign mr=32'h13579bdf;
cached_cpu #(.RESET_PC(0),.SETS(SETS),.WORDS_PER_LINE(WORDS)) dut(
 .clk(clk),.rst(rst),.imem_addr(ia),.imem_rdata(rom[ia[11:2]]),.hw_irq(6'b0),
 .mem_valid(bv),.mem_write(bwrite),.mem_addr(ba),.mem_wdata(bw),.mem_wstrb(bs),.mem_ready(ready_back),.mem_rdata(br),
 .mmio_valid(mv),.mmio_write(mwrite),.mmio_addr(ma),.mmio_wdata(mw),.mmio_wstrb(ms),.mmio_ready(ready_mmio),.mmio_rdata(mr),
 .trace_valid(tv),.trace_pc(tp),.trace_instr(ti),.trace_we(tw),.trace_rd(tr),.trace_wdata(td),
 .trace_mem_we(tm),.trace_mem_addr(tma),.trace_mem_wdata(tmd),
 .exception_valid(ev),.exception_code(ec),.exception_epc(ee),.exception_bd(eb),
 .cycle_count(cycles),.retired_count(retired),.stall_count(stalls),
 .hit_count(hits),.miss_count(misses),.writeback_count(writebacks));
integer mode=0,tick=0,i,j,k,n,got,trace_fd,request_fd,counts_fd;
integer expected_requests,requests_done=0,mmio_stores=0,back_reads=0,back_writes=0;
integer eh,emiss,ewb,emmio,adjacent=0,trace_file,bus_file;
reg [31:0] ep,ei,ewe,erd,ed,ems,ema,emd;
reg [31:0] qwrite,qaddr,qdata,qstrobe,qread;
reg [31:0] random_state=32'hc01dcafe;
reg held_cpu=0,held_back=0,held_mmio=0,last_back=0;
reg [68:0] request_cpu,request_back,request_mmio;

always @(negedge clk)begin
 if(rst)begin ready_back=0;ready_mmio=0;random_state=32'hc01dcafe;end
 else begin
  random_state=random_state^(random_state<<13);
  random_state=random_state^(random_state>>17);
  random_state=random_state^(random_state<<5);
  ready_back=(mode==0)||(mode==1&&random_state[1:0]==0)||(mode==2&&tick%13==5);
  ready_mmio=(mode==0)||(random_state[5:3]==3);
 end
end

always @(posedge clk)begin
 tick<=tick+1;
 if(rst)begin held_cpu<=0;held_back<=0;held_mmio<=0;last_back<=0;end
 else begin
  if(ev)$fatal(1,"FAIL unexpected exception code=%0d EPC=%h",ec,ee);
  if(held_cpu&&(!dut.cpu_valid||{dut.cpu_write,dut.cpu_addr,dut.cpu_wdata,dut.cpu_wstrb}!==request_cpu))$fatal(1,"FAIL unstable CPU request");
  if(held_back&&(!bv||{bwrite,ba,bw,bs}!==request_back))$fatal(1,"FAIL unstable backing request");
  if(held_mmio&&(!mv||{mwrite,ma,mw,ms}!==request_mmio))$fatal(1,"FAIL unstable MMIO request");
  held_cpu<=dut.cpu_valid&&!dut.cpu_ready;request_cpu<={dut.cpu_write,dut.cpu_addr,dut.cpu_wdata,dut.cpu_wstrb};
  held_back<=bv&&!ready_back;request_back<={bwrite,ba,bw,bs};
  held_mmio<=mv&&!ready_mmio;request_mmio<={mwrite,ma,mw,ms};
  if(mv&&bv)$fatal(1,"FAIL cache and MMIO active together");
  if(bv&&ba>=32'h8000)$fatal(1,"FAIL backing address outside RAM %h",ba);
  if(mv&&ma[31:16]!=16'hffff)$fatal(1,"FAIL MMIO decode %h",ma);
  if(bv&&ready_back)begin
   if(last_back)adjacent=adjacent+1;
   if(ba[1:0]!=0||bs!==(bwrite?4'hf:4'h0))$fatal(1,"FAIL backing word protocol");
   if(bwrite)begin
    back_writes=back_writes+1;
    for(k=0;k<4;k=k+1)if(bs[k])memory[ba[14:2]][k*8+:8]<=bw[k*8+:8];
   end else back_reads=back_reads+1;
  end
  last_back<=bv&&ready_back;
  if(mv&&ready_mmio&&mwrite)mmio_stores=mmio_stores+1;
  if(dut.cpu_valid&&dut.cpu_ready)begin
   if(requests_done>=expected_requests)$fatal(1,"FAIL duplicate CPU/MMIO completion");
   got=$fscanf(request_fd,"%h %h %h %h %h\n",qwrite,qaddr,qdata,qstrobe,qread);
   if(got!=5)$fatal(1,"FAIL request oracle truncated");
   if(dut.cpu_write!==qwrite[0]||dut.cpu_addr!==qaddr||dut.cpu_wstrb!==qstrobe[3:0]||
      (qwrite&&(dut.cpu_wdata!==qdata))||(!qwrite&&dut.cpu_rdata!==qread))
      $fatal(1,"FAIL CPU request row=%0d addr=%h/%h read=%h/%h",requests_done,dut.cpu_addr,qaddr,dut.cpu_rdata,qread);
   requests_done=requests_done+1;
  end
  if(tv)$fwrite(trace_file,"%0d,%0d,%h,%h,%b,%0d,%h,%h,%h,%h\n",mode,cycles,tp,ti,tw,tr,td,tm,tma,tmd);
  $fwrite(bus_file,"%0d,%0d,%b,%b,%h,%b,%b,%b,%h,%b,%b,%h,%0d,%0d,%0d\n",mode,cycles,dut.cpu_valid,dut.cpu_ready,dut.cpu_addr,bv,ready_back,bwrite,ba,mv,ready_mmio,ma,hits,misses,writebacks);
 end
end

initial begin
 $readmemh("cache_program.hex",rom);$readmemh("cache_memory.hex",expected_memory);
 trace_file=$fopen($sformatf("cache_retirements_%0d_%0d.csv",SETS,WORDS),"w");
 bus_file=$fopen($sformatf("cache_bus_%0d_%0d.csv",SETS,WORDS),"w");
 $fwrite(trace_file,"mode,cycle,pc,instr,we,rd,wdata,mem_strobe,mem_addr,mem_data\n");
 $fwrite(bus_file,"mode,cycle,cpu_valid,cpu_ready,cpu_addr,back_valid,back_ready,back_write,back_addr,mmio_valid,mmio_ready,mmio_addr,hits,misses,writebacks\n");
 counts_fd=$fopen("cache_counts.txt","r");got=$fscanf(counts_fd,"%d %d %d %d\n",eh,emiss,ewb,emmio);$fclose(counts_fd);
 if(got!=4)$fatal(1,"FAIL counts oracle truncated");
 for(mode=0;mode<3;mode=mode+1)begin
  rst=1;repeat(4)@(negedge clk);
  for(i=0;i<8192;i=i+1)memory[i]=0;
  requests_done=0;mmio_stores=0;back_reads=0;back_writes=0;adjacent=0;
  trace_fd=$fopen("cache_trace.txt","r");got=$fscanf(trace_fd,"%d\n",n);
  request_fd=$fopen("cache_requests.txt","r");got=$fscanf(request_fd,"%d\n",expected_requests);
  #1;rst=0;
  for(j=0;j<n;j=j+1)begin
   got=$fscanf(trace_fd,"%h %h %h %h %h %h %h %h\n",ep,ei,ewe,erd,ed,ems,ema,emd);
   if(got!=8)$fatal(1,"FAIL trace oracle truncated");
   @(posedge clk);while(!tv)@(posedge clk);
   if(tp!==ep||ti!==ei||tw!==ewe[0]||(tw&&(tr!==erd[4:0]||td!==ed))||tm!==ems[3:0]||(tm&&(tma!==ema||tmd!==emd)))
    $fatal(1,"FAIL retirement row=%0d mode=%0d PC=%h/%h data=%h/%h",j,mode,tp,ep,td,ed);
  end
  @(negedge clk);
  if(retired!=n||requests_done!=expected_requests)$fatal(1,"FAIL retirement/request count");
  if(hits!=eh||misses!=emiss||writebacks!=ewb)$fatal(1,"FAIL counters hit=%0d/%0d miss=%0d/%0d wb=%0d/%0d",hits,eh,misses,emiss,writebacks,ewb);
  if(back_reads!=emiss*WORDS||back_writes!=ewb*WORDS)$fatal(1,"FAIL backing transaction count");
  if(mmio_stores!=emmio)$fatal(1,"FAIL MMIO duplicate/missing %0d/%0d",mmio_stores,emmio);
  if(mode==0&&adjacent==0)$fatal(1,"FAIL continuous ready coverage absent");
  for(i=0;i<8192;i=i+1)if(memory[i]!==expected_memory[i])$fatal(1,"FAIL final backing memory word=%0d actual=%h expected=%h",i,memory[i],expected_memory[i]);
  $display("JOINT sets=%0d words=%0d mode=%0d retirements=%0d cycles=%0d stalls=%0d hits=%0d misses=%0d writebacks=%0d MMIO_stores=%0d back_reads=%0d back_writes=%0d adjacent=%0d",SETS,WORDS,mode,retired,cycles,stalls,hits,misses,writebacks,mmio_stores,back_reads,back_writes,adjacent);
  $fclose(trace_fd);$fclose(request_fd);
 end
 rst=1;$fclose(trace_file);$fclose(bus_file);
 $display("PASS cpu-cache SETS=%0d WORDS=%0d",SETS,WORDS);$finish;
end
initial begin #2000000;$fatal(1,"FAIL cpu-cache watchdog");end
endmodule
