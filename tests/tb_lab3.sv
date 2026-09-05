`timescale 1ns/1ps
module tb_lab3;
 reg clk=0,rstn=0;
 reg [7:0] switch=0;
 reg mid_btn_key=0,left_btn_key=0,right_btn_key=0,up_btn_key=0,down_btn_key=0;
 wire [6:0] digital_num0,digital_num1;
 wire [7:0] digital_cs,led;
 single_cycle dut(.*);
 always #5 clk=~clk;
 integer mode=0,cycles=0,stores=0,displays=0,cases=0,expected_sum=0;
 integer golden[0:19];
 integer boundaries[0:5];
 reg checking_sum=0;
 integer display_writes=0;
 task reset_cpu;
  begin
   @(negedge clk);rstn=0;mid_btn_key=0;right_btn_key=0;up_btn_key=0;
   repeat(5)@(negedge clk);rstn=1;
  end
 endtask
 task await_reg(input integer regno,input integer expected);
  integer wait_cycles;
  begin
   wait_cycles=0;
   while(dut.mycpu0.core.regs[regno]!==expected && wait_cycles<3000000)begin
    @(negedge clk);wait_cycles=wait_cycles+1;
   end
   if(wait_cycles==3000000)$fatal(1,"FAIL LAB3 input r%0d expected=%0d",regno,expected);
   if(led!==expected[7:0])begin
    repeat(3)@(negedge clk);
    if(led!==expected[7:0])$fatal(1,"FAIL LAB3 input LED");
   end
  end
 endtask
 task add_case(input integer a,b);
  integer before_writes,wait_cycles;
  begin
   reset_cpu();repeat(30)@(negedge clk);
   switch=a;up_btn_key=1;
   // For zero inputs, await_reg could already match reset; wait for actual
   // debounced input and one full program polling loop before changing switch.
   wait(dut.confreg0.up_btn_key_r===1);repeat(mode==3 ? 100 : 600000)@(negedge clk);await_reg(11,a);
   up_btn_key=0;wait(dut.confreg0.up_btn_key_r===0);
   switch=b;right_btn_key=1;
   wait(dut.confreg0.right_btn_key_r===1);repeat(mode==3 ? 100 : 600000)@(negedge clk);await_reg(12,b);
   right_btn_key=0;wait(dut.confreg0.right_btn_key_r===0);
   expected_sum=a+b;checking_sum=1;before_writes=display_writes;mid_btn_key=1;wait_cycles=0;
   while(display_writes==before_writes && wait_cycles<3000000)begin
    @(negedge clk);wait_cycles=wait_cycles+1;
   end
   if(wait_cycles==3000000)$fatal(1,"FAIL LAB3 adder timeout %0d+%0d",a,b);
   repeat(20)@(negedge clk);
   if(dut.confreg0.digital_num_v!==expected_sum || led!==expected_sum[7:0])
    $fatal(1,"FAIL LAB3 adder %0d+%0d actual display=%0d led=%0d",a,b,dut.confreg0.digital_num_v,led);
   repeat(100)@(negedge clk);
   if(display_writes!=before_writes+1)$fatal(1,"FAIL LAB3 held mid repeats sum");
   mid_btn_key=0;checking_sum=0;cases=cases+1;
  end
 endtask
 initial begin
  if($test$plusargs("MODE1"))mode=1;
  if($test$plusargs("MODE2"))mode=2;
  if($test$plusargs("MODE3"))mode=3;
  golden[0]=2;golden[1]=3;
  for(integer i=2;i<20;i=i+1)golden[i]=golden[i-1]+golden[i-2];
  boundaries[0]=0;boundaries[1]=1;boundaries[2]=127;boundaries[3]=128;boundaries[4]=254;boundaries[5]=255;
  if(mode<2)begin
   reset_cpu();
   wait(displays==(mode==0 ? 1 : 20));@(negedge clk);
   if(stores!=20)$fatal(1,"FAIL LAB3 Fibonacci store count %0d",stores);
   for(integer i=0;i<20;i=i+1)
    if(dut.data_ram_4k.mem[i]!==golden[i])$fatal(1,"FAIL LAB3 Fibonacci RAM index=%0d",i);
   $display("PASS LAB3 fibonacci mode=%0d stores=%0d displays=%0d last=%0d cycles=%0d",mode,stores,displays,golden[19],cycles);$finish;
  end else begin
   if(mode==2)add_case(255,255);
   else for(integer a=0;a<6;a=a+1)for(integer b=0;b<6;b=b+1)add_case(boundaries[a],boundaries[b]);
   $display("PASS LAB3 adder mode=%0d cases=%0d cycles=%0d",mode,cases,cycles);$finish;
  end
 end
 always @(posedge clk)if(rstn)begin
  cycles=cycles+1;
  if(dut.mycpu0.illegal)$fatal(1,"FAIL LAB3 illegal pc=%h",dut.inst_rom_addr);
  if(dut.data_ram_wen)begin
   if(dut.data_ram_addr[31:16]!=16'hbfaf)begin
    if(mode>=2 || stores>=20 || dut.data_ram_addr!==32'hbfc10000+stores*4 || dut.data_ram_wdata!==golden[stores])
     $fatal(1,"FAIL LAB3 Fibonacci store index=%0d address=%h data=%h",stores,dut.data_ram_addr,dut.data_ram_wdata);
    stores=stores+1;
   end else if(dut.data_ram_addr==32'hbfaf8000)begin
    display_writes=display_writes+1;
    if(mode<2)begin
     if(displays>=20 || dut.data_ram_wdata!==golden[displays])$fatal(1,"FAIL LAB3 Fibonacci display index=%0d value=%0d",displays,dut.data_ram_wdata);
     displays=displays+1;
    end else if(checking_sum && dut.data_ram_wdata!==expected_sum)$fatal(1,"FAIL LAB3 sum expected=%0d actual=%0d",expected_sum,dut.data_ram_wdata);
   end
  end
  if(cycles>250000000)$fatal(1,"FAIL LAB3 timeout");
 end
endmodule
