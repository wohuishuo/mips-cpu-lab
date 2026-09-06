`timescale 1ns/1ps
// Executed instruction is sampled before the edge; state after NBA updates.
module tb_exhibit_soc;
 reg clk=0,rst=1;
 wire tx,buzz,done;
 wire [7:0] led,digit_n,segment_n;
 wire [31:0] pc,result,stores;
 always #5 clk=~clk;
 lab_soc dut(.clk(clk),.rst(rst),.uart_rx_pin(1'b1),.switches(8'h81),
 .uart_tx_pin(tx),.led(led),.digit_n(digit_n),.segment_n(segment_n),
 .buzzer_pin(buzz),.debug_pc(pc),.debug_result(result),.debug_stores(stores),.debug_done(done));
 integer fd,cycle,i,ram_stores=0;
 reg [31:0] expected[0:11];
 reg [31:0] sampled_pc,sampled_instr,sampled_value,sampled_address,sampled_store,sampled_read;
 reg sampled_we;
 reg [4:0] sampled_rd;
 reg [3:0] sampled_strb;
 task check(input logic ok,input string message);
  if(ok!==1'b1)begin $display("FAIL EXHIBIT %s",message);$fatal(1,"exhibit assertion");end
 endtask
 initial begin
  expected[0]=0;expected[1]=1;
  for(i=2;i<12;i=i+1)expected[i]=expected[i-1]+expected[i-2];
  fd=$fopen("board-trace.csv","w");
  check(fd!=0,"open trace");
  $fwrite(fd,"cycle,pc,instr,regWrite,rd,value,memWrite,address,storeValue,readValue,display,led,done");
  for(i=0;i<32;i=i+1)$fwrite(fd,",r%0d",i);
  for(i=0;i<12;i=i+1)$fwrite(fd,",ram%0d",i);
  $fwrite(fd,"\n");
  repeat(5)@(negedge clk);
  for(i=0;i<32;i=i+1)check(dut.cpu.regs[i]===0,"register reset");
  for(i=0;i<12;i=i+1)check($isunknown({dut.ram3[i],dut.ram2[i],dut.ram1[i],dut.ram0[i]}),"RAM has no reset initialization");
  rst=0;
  for(cycle=1;cycle<=160;cycle=cycle+1)begin
   @(posedge clk);
   check(dut.trace_valid && !dut.illegal,"legal executed instruction");
   sampled_pc=dut.trace_pc;sampled_instr=dut.trace_instr;
   sampled_we=dut.trace_we;sampled_rd=dut.trace_rd;sampled_value=dut.trace_data;
   sampled_strb=dut.strb;sampled_address=dut.da;sampled_store=dut.dw;sampled_read=dut.dr;
   if(dut.ram_select && |dut.strb)begin
    check(ram_stores<12,"no extra RAM store");
    check(dut.strb==4'hf && dut.da==32'h10010000+ram_stores*4,"sequential full-word RAM stores");
    check(dut.dw==expected[ram_stores],"independent Fibonacci store value");
    ram_stores=ram_stores+1;
   end
   #1;
   $fwrite(fd,"%0d,%08h,%08h,%0d,%0d,%08h,%0d,%08h,%08h,%08h,%08h,%02h,%0d",
    cycle,sampled_pc,sampled_instr,sampled_we,sampled_rd,sampled_value,|sampled_strb,
    sampled_address,sampled_store,sampled_read,dut.display_value,led,done);
   for(i=0;i<32;i=i+1)$fwrite(fd,",%08h",dut.cpu.regs[i]);
   for(i=0;i<12;i=i+1)$fwrite(fd,",%08h",{dut.ram3[i],dut.ram2[i],dut.ram1[i],dut.ram0[i]});
   $fwrite(fd,"\n");
  end
  $fclose(fd);
  check(stores==12 && ram_stores==12,"exactly twelve RAM stores");
  for(i=0;i<12;i=i+1)check({dut.ram3[i],dut.ram2[i],dut.ram1[i],dut.ram0[i]}===expected[i],"final RAM Fibonacci sequence");
  check(done && result==89,"done and result");
  check(dut.display_value==32'h00810059 && led==8'hd8,"switch display and LED");
  check(dut.errors==0,"no CPU errors");
  $display("PASS EXHIBIT cycles=160 fibonacci=12 stores=12 result=89 display=00810059 led=d8");
  $finish;
 end
 initial begin #100000;$fatal(1,"FAIL EXHIBIT timeout");end
endmodule
