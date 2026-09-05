`timescale 1ns/1ps
module tb_cp0;
reg clk=0,rst=1;
always #5 clk=~clk;
reg [4:0] read_addr=0,write_addr=0,exception_code=0;
reg [31:0] write_data=0,exception_pc=0,exception_badvaddr=0;
reg write_valid=0,exception_valid=0,exception_bd=0,eret=0;
reg [5:0] hw_irq=0;
wire [31:0] read_data,status,cause,epc,badvaddr;
wire irq_pending;
integer checks=0,failures=0;
cp0 dut(.*);
task check(input bit condition,input [511:0] label);
begin checks=checks+1;if(!condition) begin failures=failures+1;$display("FAIL %s",label);end end
endtask
task wr(input [4:0] addr,input [31:0] data);
begin @(negedge clk);write_valid=1;write_addr=addr;write_data=data;@(negedge clk);write_valid=0;end
endtask
task fault(input [4:0] code,input [31:0] pc,input bit bd,input [31:0] bad);
begin @(negedge clk);exception_valid=1;exception_code=code;exception_pc=pc;
exception_bd=bd;exception_badvaddr=bad;@(negedge clk);exception_valid=0;end
endtask
task reset_cp0;
begin @(negedge clk);rst=1;@(negedge clk);rst=0;#1;end
endtask
initial begin
repeat(3) @(negedge clk);rst=0;#1;
check(status==32'h00400000,"reset status");check(!irq_pending,"reset interrupts masked");
wr(12,32'h00000401);hw_irq=6'b000001;#1;check(irq_pending,"enabled external interrupt");
fault(0,32'hbfc00080,0,0);#1;
check(status[1] && !irq_pending,"EXL masks interrupt");check(epc==32'hbfc00080,"interrupt EPC");
fault(4,32'hbfc000a0,1,32'h00000103);#1;
check(epc==32'hbfc00080 && !cause[31],"nested exception preserves first EPC BD");
check(badvaddr==32'h103 && cause[6:2]==4,"AdEL updates bad address code");
@(negedge clk);eret=1;@(negedge clk);eret=0;hw_irq=0;#1;check(!status[1],"eret clears EXL");
fault(5,32'hbfc00100,1,32'h105);#1;
check(epc==32'hbfc00100 && cause[31],"delay slot branch EPC and BD");
check(badvaddr==32'h105,"AdES bad address");
wr(14,32'h12345678);check(epc==32'h12345678,"MTC0 EPC");
read_addr=14;#1;check(read_data==epc,"MFC0 EPC");
wr(12,32'h00000101);wr(13,32'h00000100);#1;
check(irq_pending && cause[8],"software interrupt pending");
wr(13,0);#1;check(!irq_pending,"software pending clear");
wr(12,32'h00008001);wr(9,0);wr(11,12);
repeat(14) @(negedge clk);#1;check(irq_pending && cause[30] && cause[15],"Count Compare timer");
wr(11,100);#1;check(!irq_pending && !cause[30],"Compare write acknowledges timer");
read_addr=31;#1;check(read_data==0,"unsupported register read");
reset_cp0;
check(epc==0 && badvaddr==0 && !cause[30],"reset clears exception state");

@(negedge clk);write_valid=1;write_addr=11;write_data=100;
@(negedge clk);write_addr=9;write_data=99;
@(negedge clk);write_data=0;
@(negedge clk);write_valid=0;read_addr=9;#1;
check(read_data==0,"Count write commits value away from imminent match");
check(!cause[30],"Count write away from Compare does not set timer");

reset_cp0;
wr(11,100);wr(9,100);read_addr=9;#1;
check(read_data==100 && cause[30],"Count write equal to Compare sets timer");

reset_cp0;
wr(11,0);wr(9,32'hffffffff);@(negedge clk);read_addr=9;#1;
check(read_data==0 && cause[30],"normal Count increment wraps and matches Compare");

reset_cp0;
wr(11,100);wr(9,100);wr(11,102);read_addr=9;#1;
check(read_data==102 && !cause[30],"Compare write clears timer at equal committed Count");

reset_cp0;
wr(9,10);
exception_valid=1;exception_code=0;exception_pc=32'h1000;
write_valid=1;write_addr=9;write_data=777;
@(negedge clk);exception_valid=0;write_valid=0;read_addr=9;#1;
check(read_data==11,"exception suppresses Count write but not increment");

reset_cp0;
wr(9,20);eret=1;write_valid=1;write_addr=9;write_data=777;
@(negedge clk);eret=0;write_valid=0;read_addr=9;#1;
check(read_data==21,"eret suppresses Count write but not increment");
if(failures==0)$display("PASS CP0 checks=%0d",checks);
else $display("FAIL CP0 failures=%0d",failures);
$finish;
end
initial begin #10000;$fatal(1,"CP0 timeout");end
endmodule
