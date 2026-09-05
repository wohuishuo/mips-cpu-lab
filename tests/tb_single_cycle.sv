`timescale 1ns/1ps
module tb_single_cycle;
  reg clk=0, rst=1;
  always #5 clk=~clk;
  reg [31:0] instruction=0;
  wire [31:0] pc, da, dw, tp, ti, tw;
  wire [3:0] ds;
  wire tv, te, bad;
  wire [4:0] tr;
  reg [31:0] memory [0:255];
  wire [31:0] dr=memory[da[9:2]];
  integer checks=0, i, lane;
  reg [31:0] a,b,expected;
  integer trace_file;
  reg high_rst=1;
  reg [31:0] high_instr=0;
  wire [31:0] high_pc,high_wdata;
  wire [31:0] high_da,high_dw,high_tp,high_ti;
  wire [3:0] high_ds;
  wire high_we,high_tv,high_bad;
  wire [4:0] high_rd;
  single_cycle_cpu #(.RESET_PC(32'h8ffffffc)) high_dut(
    .clk(clk),.rst(high_rst),.imem_addr(high_pc),.imem_rdata(high_instr),
    .dmem_rdata(32'b0),.dmem_addr(high_da),.dmem_wdata(high_dw),.dmem_wstrb(high_ds),
    .trace_valid(high_tv),.trace_pc(high_tp),.trace_instr(high_ti),.illegal(high_bad),
    .trace_we(high_we),.trace_rd(high_rd),.trace_wdata(high_wdata));
  single_cycle_cpu #(.RESET_PC(0)) dut(
    .clk(clk),.rst(rst),.imem_addr(pc),.imem_rdata(instruction),
    .dmem_addr(da),.dmem_wdata(dw),.dmem_wstrb(ds),.dmem_rdata(dr),
    .trace_valid(tv),.trace_pc(tp),.trace_instr(ti),.trace_we(te),
    .trace_rd(tr),.trace_wdata(tw),.illegal(bad));
  always @(posedge clk) if(!rst)
    for(integer k=0;k<4;k=k+1) if(ds[k]) memory[da[9:2]][8*k+:8]<=dw[8*k+:8];
  always @(posedge clk) if(!rst && tv)
    $fdisplay(trace_file,"%08h,%08h,%0d,%0d,%08h,%08h,%08h,%01h,%0d",tp,ti,te,tr,tw,da,dw,ds,bad);
  function [31:0] ri(input [5:0] fn,input [4:0] rs,rt,rd,sa);
    ri={6'd0,rs,rt,rd,sa,fn};
  endfunction
  function [31:0] ii(input [5:0] op,input [4:0] rs,rt,input [15:0] imm);
    ii={op,rs,rt,imm};
  endfunction
  task reset_core;
    begin
      rst=1;instruction=0;
      @(posedge clk);#1;
      if(tv!==0 || ds!==0 || te!==0) $fatal(1,"FAIL reset side effect");
      @(negedge clk);rst=0;
    end
  endtask
  task jump_boundary;
    begin
      @(negedge clk);high_rst=0;high_instr={6'd3,26'd16};#1;
      if(high_pc!==32'h8ffffffc || !high_we || high_rd!==31 || high_wdata!==32'h90000004)
        $fatal(1,"FAIL high reset/link");
      @(posedge clk);#1;
      if(high_pc!==32'h90000000)$fatal(1,"FAIL high delay PC");
      @(negedge clk);high_instr=0;
      @(posedge clk);#1;
      if(high_pc!==32'h90000040)$fatal(1,"FAIL jump PC+4 region boundary");
      @(negedge clk);high_rst=1;checks=checks+2;
    end
  endtask
  task step(input [31:0] ins,input we,input [4:0] rd,input [31:0] value,
            input illegal_expected,input [31:0] nextpc);
    reg [31:0] before_pc;
    begin
      instruction=ins;before_pc=pc;#1;
      if(tv!==1 || tp!==before_pc || ti!==ins || te!==we || bad!==illegal_expected)
        $fatal(1,"FAIL trace pc=%h ins=%h we=%b expected=%b illegal=%b expected=%b",pc,ins,te,we,bad,illegal_expected);
      if(we && (tr!==rd || tw!==value))
        $fatal(1,"FAIL result pc=%h ins=%h r%0d=%h expected r%0d=%h",pc,ins,tr,tw,rd,value);
      if(illegal_expected && ds!==0) $fatal(1,"FAIL illegal store");
      if(ins[31:26]!=40 && ins[31:26]!=41 && ins[31:26]!=43 && ds!==0)
        $fatal(1,"FAIL unexpected memory write ins=%h",ins);
      @(posedge clk);#1;
      if(pc!==nextpc) $fatal(1,"FAIL next PC %h expected %h ins=%h",pc,nextpc,ins);
      checks=checks+1;
      @(negedge clk);
    end
  endtask
  task seq(input [31:0] ins,input we,input [4:0] rd,input [31:0] value);
    step(ins,we,rd,value,0,pc+4);
  endtask
  task setreg(input [4:0] rd,input [31:0] value);
    begin
      seq(ii(15,0,rd,value[31:16]),rd!=0,rd,{value[31:16],16'd0});
      seq(ii(13,rd,rd,value[15:0]),rd!=0,rd,value);
    end
  endtask
  task store(input [5:0] op,input [15:0] offset,input [31:0] addr,data,input [3:0] strobes);
    begin
      instruction=ii(op,1,2,offset);#1;
      if(da!==addr || dw!==data || ds!==strobes)
        $fatal(1,"FAIL store addr=%h data=%h strobe=%h",da,dw,ds);
      seq(instruction,0,0,0);
    end
  endtask
  task branch_case(input [5:0] op,input [4:0] rt,input [31:0] value,input taken,link);
    reg [31:0] branch_pc;
    begin
      reset_core;setreg(1,value);branch_pc=pc;
      step(ii(op,1,rt,2),link,31,branch_pc+8,0,branch_pc+4);
      step(ii(9,0,3,17),1,3,17,0,taken ? branch_pc+12 : branch_pc+8);
      // Conditional link writes are observable even on the untaken path.
      seq(ri(33,31,0,4,0),1,4,link ? branch_pc+8 : 0);
    end
  endtask
  initial begin
    trace_file=$fopen("retirements.csv","w");
    $fdisplay(trace_file,"pc,instruction,reg_we,reg_rd,reg_data,mem_addr,mem_data,mem_strobes,illegal");
    for(i=0;i<256;i=i+1) memory[i]=0;
    reset_core;
    setreg(0,32'hffffffff);
    seq(ii(9,0,3,0),1,3,0);
    setreg(1,32'h80000000);setreg(2,32'hffffffff);
    seq(ri(42,1,2,3,0),1,3,1);
    seq(ri(43,1,2,3,0),1,3,1);
    seq(ri(42,2,0,3,0),1,3,1);
    seq(ri(43,2,0,3,0),1,3,0);
    seq(ii(10,1,3,16'hffff),1,3,1);
    seq(ii(11,1,3,16'hffff),1,3,1);
    setreg(1,32'h7fffffff);setreg(2,1);
    seq(ri(32,1,2,3,0),1,3,32'h80000000);
    seq(ii(8,1,3,1),1,3,32'h80000000);
    setreg(1,32'h80000000);
    seq(ri(34,1,2,3,0),1,3,32'h7fffffff);
    setreg(1,32'hffffffff);
    seq(ii(11,1,3,16'hffff),1,3,0);
    seq(ii(10,1,3,16'h8000),1,3,0);
    setreg(1,0);
    seq(ii(11,1,3,16'h8000),1,3,1);
    seq(ii(10,1,3,16'h8000),1,3,0);
    // Random operand pairs and every shift count detect signedness/width bugs.
    a=32'h814523af;b=32'h7fffffff;
    for(i=0;i<64;i=i+1) begin
      a={a[30:0],a[31]^a[21]^a[1]^a[0]};b=b*1664525+1013904223;
      setreg(1,a);setreg(2,b);
      seq(ri(32,1,2,3,0),1,3,a+b);
      seq(ri(33,1,2,3,0),1,3,a+b);
      seq(ri(34,1,2,3,0),1,3,a-b);
      seq(ri(35,1,2,3,0),1,3,a-b);
      seq(ri(36,1,2,3,0),1,3,a&b);
      seq(ri(37,1,2,3,0),1,3,a|b);
      seq(ri(38,1,2,3,0),1,3,a^b);
      seq(ri(39,1,2,3,0),1,3,~(a|b));
      seq(ri(42,1,2,3,0),1,3,$signed(a)<$signed(b));
      seq(ri(43,1,2,3,0),1,3,a<b);
      seq(ri(0,0,2,3,i%32),1,3,b<<(i%32));
      seq(ri(2,0,2,3,i%32),1,3,b>>(i%32));
      seq(ri(3,0,2,3,i%32),1,3,$signed(b)>>>(i%32));
      seq(ri(4,1,2,3,0),1,3,b<<a[4:0]);
      seq(ri(6,1,2,3,0),1,3,b>>a[4:0]);
      seq(ri(7,1,2,3,0),1,3,$signed(b)>>>a[4:0]);
      seq(ii(8,1,3,16'hfffe),1,3,a-2);
      seq(ii(9,1,3,16'hfffe),1,3,a-2);
      seq(ii(12,1,3,16'h8001),1,3,a&32'h8001);
      seq(ii(13,1,3,16'h8001),1,3,a|32'h8001);
      seq(ii(14,1,3,16'h8001),1,3,a^32'h8001);
    end
    setreg(2,32'h80000001);
    for(i=0;i<32;i=i+1)begin
      setreg(1,32'hffffffe0|i);
      seq(ri(4,1,2,3,0),1,3,32'h80000001<<i);
      seq(ri(6,1,2,3,0),1,3,32'h80000001>>i);
      seq(ri(7,1,2,3,0),1,3,$signed(32'h80000001)>>>i);
    end
    setreg(1,32'h104);setreg(2,32'h89abcdef);
    store(43,16'hfffc,32'h100,32'h89abcdef,4'b1111);
    seq(ii(35,1,3,16'hfffc),1,3,32'h89abcdef);
    for(lane=0;lane<4;lane=lane+1) begin
      expected=(32'h89abcdef>>(lane*8))&255;
      seq(ii(36,1,3,16'hfffc+lane),1,3,expected);
      seq(ii(32,1,3,16'hfffc+lane),1,3,expected|32'hffffff00);
    end
    seq(ii(33,1,3,16'hfffc),1,3,32'hffffcdef);
    seq(ii(37,1,3,16'hfffe),1,3,32'h89ab);
    setreg(2,32'h12345678);
    for(lane=0;lane<4;lane=lane+1) store(40,16'hfffc+lane,32'h100+lane,32'h12345678<<(lane*8),1<<lane);
    if(memory[64]!==32'h78787878) $fatal(1,"FAIL byte lanes");
    store(41,16'hfffc,32'h100,32'h12345678,4'b0011);
    store(41,16'hfffe,32'h102,32'h56780000,4'b1100);
    if(memory[64]!==32'h56785678) $fatal(1,"FAIL half lanes");
    memory[65]=32'h7f018000;
    seq(ii(32,1,3,3),1,3,32'h7f);
    seq(ii(32,1,3,1),1,3,32'hffffff80);
    seq(ii(33,1,3,2),1,3,32'h7f01);
    seq(ii(33,1,3,0),1,3,32'hffff8000);
    seq(ii(37,1,3,0),1,3,32'h8000);
    seq(ii(35,1,0,0),0,0,0);
    step(ii(35,1,3,1),0,0,0,1,pc+4);
    step(ii(41,1,2,1),0,0,0,1,pc+4);
    step(32'hffffffff,0,0,0,1,pc+4);
    step(ri(63,1,2,3,0),0,0,0,1,pc+4);
    step(ii(43,1,2,2),0,0,0,1,pc+4);
    step(ii(33,1,3,1),0,0,0,1,pc+4);
    step(ii(37,1,3,1),0,0,0,1,pc+4);
    step(ri(12,0,0,0,0),0,0,0,1,pc+4); // syscall
    step(ri(13,0,0,0,0),0,0,0,1,pc+4); // break
    step(ri(24,1,2,0,0),0,0,0,1,pc+4); // mult
    step(32'h40026000,0,0,0,1,pc+4); // mfc0
    step(ri(0,1,2,3,0),0,0,0,1,pc+4); // reserved shift encoding
    step(ri(33,1,2,3,1),0,0,0,1,pc+4); // reserved arithmetic encoding
    step(ii(15,1,3,0),0,0,0,1,pc+4); // reserved lui
    step(ii(6,1,3,0),0,0,0,1,pc+4); // reserved blez
    step(ii(1,1,3,0),0,0,0,1,pc+4); // unsupported regimm
    setreg(1,3);
    step(ri(8,1,0,0,0),0,0,0,1,pc+4); // unaligned jr
    // Taken and untaken branch delay slots and backward sign extension.
    reset_core;setreg(1,1);setreg(2,2);
    step(ii(4,1,1,2),0,0,0,0,20);step(ii(9,0,3,7),1,3,7,0,28);
    step(ii(5,1,1,16'hfffc),0,0,0,0,32);step(0,0,0,0,0,36);
    step(ii(5,1,2,16'hfffc),0,0,0,0,40);step(0,0,0,0,0,24);
    step({6'd3,26'd32},1,31,32,0,28);step(ii(9,0,3,9),1,3,9,0,128);
    step(ri(8,31,0,0,0),0,0,0,0,132);step(0,0,0,0,0,32);
    setreg(1,256);
    step(ri(9,1,0,4,0),1,4,48,0,44);step(0,0,0,0,0,256);
    step({6'd2,26'd72},0,0,0,0,260);
    step({6'd2,26'd80},0,0,0,1,288); // control in delay slot rejected
    setreg(1,32'hffffffff);
    step(ii(1,1,0,2),0,0,0,0,300);step(0,0,0,0,0,308);
    step(ii(1,1,1,2),0,0,0,0,312);step(0,0,0,0,0,316);
    step(ii(6,1,0,2),0,0,0,0,320);step(0,0,0,0,0,328);
    step(ii(7,1,0,2),0,0,0,0,332);step(0,0,0,0,0,336);
    step(ii(1,1,16,2),1,31,344,0,340);step(0,0,0,0,0,348);
    setreg(1,1);
    step(ii(1,1,17,2),1,31,364,0,360);step(0,0,0,0,0,368);
    // Reset cancels an outstanding redirect and erases register state.
    step({6'd2,26'd100},0,0,0,0,372);reset_core;
    seq(ri(33,31,0,3,0),1,3,0);
    for(i=1;i<32;i=i+1)seq(ri(33,i,0,3,0),1,3,0);
    branch_case(4,0,0,1,0);branch_case(4,0,1,0,0);
    branch_case(5,0,0,0,0);branch_case(5,0,1,1,0);
    branch_case(6,0,32'h80000000,1,0);branch_case(6,0,0,1,0);branch_case(6,0,1,0,0);
    branch_case(7,0,32'hffffffff,0,0);branch_case(7,0,0,0,0);branch_case(7,0,1,1,0);
    branch_case(1,0,32'hffffffff,1,0);branch_case(1,0,0,0,0);
    branch_case(1,1,32'hffffffff,0,0);branch_case(1,1,0,1,0);
    branch_case(1,16,32'hffffffff,1,1);branch_case(1,16,0,0,1);
    branch_case(1,17,32'hffffffff,0,1);branch_case(1,17,0,1,1);
    reset_core;setreg(1,128);
    step(ri(9,1,0,1,0),1,1,16,0,12);step(0,0,0,0,0,128);
    seq(ri(33,1,0,3,0),1,3,16); // JALR uses old source when rd==rs
    fibonacci;
    rst=1;jump_boundary;
    $fclose(trace_file);
    $display("PASS single_cycle checks=%0d fibonacci_words=12",checks);$finish;
  end
  reg [31:0] rom[0:16];
  reg [31:0] fib[0:11];
  integer cycles, writes;
  task fibonacci;
    begin
      $readmemh("../../software/singlecycle_fibonacci.hex",rom);
      fib[0]=0;fib[1]=1;for(integer n=2;n<12;n=n+1)fib[n]=fib[n-1]+fib[n-2];
      reset_core;cycles=0;writes=0;
      while(pc!=60 && cycles<200)begin
        instruction=rom[pc[5:2]];#1;
        if(bad || !tv) $fatal(1,"FAIL fibonacci decode pc=%h",pc);
        if(ds!=0)begin
          if(ds!==15 || da!==(writes*4) || dw!==fib[writes])$fatal(1,"FAIL fibonacci store %0d addr=%h data=%h expected=%h",writes,da,dw,fib[writes]);
          writes=writes+1;
        end
        @(posedge clk);#1;@(negedge clk);cycles=cycles+1;
      end
      if(cycles>=200 || writes!=12) $fatal(1,"FAIL fibonacci completion");
      for(integer n=0;n<12;n=n+1)if(memory[n]!==fib[n])$fatal(1,"FAIL fibonacci memory %0d",n);
      step(rom[15],0,0,0,0,64);step(rom[16],0,0,0,0,60);
      step(rom[15],0,0,0,0,64);step(rom[16],0,0,0,0,60);
      checks=checks+cycles;
    end
  endtask
  initial begin #100000;$fatal(1,"FAIL timeout");end
endmodule
