`timescale 1ns/1ps
module tb_soc;
 reg clk=0,rst=1,rx=1;
 reg [7:0] switches=0;
 wire tx,buzz,done;
 wire [7:0] led,dn,sn;
 wire [31:0] pc,result,stores;
 localparam CPB=16;
 always #5 clk=~clk;
 lab_soc #(.CLOCK_HZ(160000),.BAUD(10000)) dut(
 .clk(clk),.rst(rst),.uart_rx_pin(rx),.switches(switches),.uart_tx_pin(tx),.led(led),
 .digit_n(dn),.segment_n(sn),.buzzer_pin(buzz),.debug_pc(pc),.debug_result(result),.debug_stores(stores),.debug_done(done));
 task check(input logic ok,input string message);
  if(ok!==1'b1)begin $display("FAIL SOC %s",message);$fatal(1,"SOC assertion");end
 endtask
 task send(input [7:0] data);
  @(negedge clk);rx=0;repeat(CPB)@(negedge clk);
  for(integer b=0;b<8;b++)begin rx=data[b];repeat(CPB)@(negedge clk);end
  rx=1;repeat(CPB)@(negedge clk);
 endtask
 task receive(output reg [7:0] data);
  @(negedge tx);repeat(CPB/2)@(posedge clk);#1;
  check(tx==0,"TX start");
  for(integer b=0;b<8;b++)begin repeat(CPB)@(posedge clk);#1;data[b]=tx;end
  repeat(CPB)@(posedge clk);#1;check(tx==1,"TX stop");
 endtask
 reg [7:0] packet[0:39];
 reg [31:0] values[0:8];
 reg reset_seen,reset_cleared;
 integer restart_wait;
 initial begin
  repeat(5)@(negedge clk);rst=0;
  repeat(200)@(negedge clk);
  check(done && result==89 && stores==12,"Fibonacci architectural outcome");
  check(led==89,"CPU LED MMIO");
  check(dut.display_value==89,"CPU display MMIO");
  @(negedge clk);force dut.da=32'h1f000100;#1;
  check(dut.dr==0,"MMIO address outside documented page reads zero");
  force dut.da=32'h1f000104;force dut.dw=32'ha5;force dut.strb=4'b0001;
  @(posedge clk);#1;check(dut.led_value==89,"MMIO address outside documented page cannot alias LED");
  @(negedge clk);release dut.da;release dut.dw;release dut.strb;
  switches=8'h3c;repeat(40)@(negedge clk);
  check(led==(8'h59^8'h3c),"switch-to-CPU-to-LED");
  check(dut.display_value==32'h003c0059,"switch-to-display");
  fork
   send(8'h3f);
   begin for(integer j=0;j<40;j++)receive(packet[j]);end
  join
  check({packet[3],packet[2],packet[1],packet[0]}==32'h5550434d,"packet signature");
  for(integer j=0;j<9;j++)values[j]={packet[j*4+7],packet[j*4+6],packet[j*4+5],packet[j*4+4]};
  check(values[0]==1 && values[2]==89 && values[4]==12 && values[8]==0,"atomic telemetry");
  check(values[5]==32'h003c0059 && values[6]==32'h00003c65,"telemetry GPIO");
  send(8'h30);repeat(8)@(negedge clk);check(led==0,"UART LEDs off");
  send(8'h31);repeat(8)@(negedge clk);check(led==255,"UART LEDs on");
  send(8'h61);repeat(8)@(negedge clk);check(led==8'h65,"UART auto mode");
  send(8'h62);repeat(8)@(negedge clk);check(dut.beep,"UART beep trigger");
  reset_seen=0;reset_cleared=0;
  fork
   send(8'h72);
   begin
    repeat(CPB*12)begin
     @(posedge clk);
     if(dut.core_rst)begin
      reset_seen=1;#1;
      if(pc==32'h00400000 && dut.cycles==0 && dut.retired==0 && stores==0 && !done && result==0)
       reset_cleared=1;
     end
    end
   end
  join
  check(reset_seen,"UART restart asserts CPU reset");
  check(reset_cleared,"UART restart clears PC and CPU telemetry");
  restart_wait=0;
  while(!(done && stores==12 && result==89) && restart_wait<250)begin
   @(negedge clk);restart_wait=restart_wait+1;
  end
  check(done && stores==12 && result==89,"UART restart recomputes Fibonacci outcome");
  check(dut.errors==0,"no illegal instructions");
  $display("PASS SOC fibonacci=12 uart_packet=40 gpio=3 restart=1");$finish;
 end
 initial begin #3000000;$display("FAIL SOC timeout");$fatal(1,"timeout");end
endmodule
