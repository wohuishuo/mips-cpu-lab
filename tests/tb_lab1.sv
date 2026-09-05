`timescale 1ns/1ps
`ifndef LAB1_DUT
`define LAB1_DUT lab1_num_led
`endif
module tb_lab1;
 reg clk=0,rst=0,center_btn_key=0;
 reg [7:0] switch=0;
 wire [6:0] digital_num0,digital_num1;
 wire [7:0] digital_cs;
 reg [31:0] expected=0;
 integer byte_index=0, checks=0;
 always #5 clk=~clk;
 `LAB1_DUT #(.COUNTER_WIDTH(4)) dut(.*);
 // Independent oracle: lit segment letters, in the course abcdefg order.
 function [6:0] glyph(input integer n);
  case(n)
   0:glyph=126;1:glyph=48;2:glyph=109;3:glyph=121;
   4:glyph=51;5:glyph=91;6:glyph=95;7:glyph=112;
   8:glyph=127;9:glyph=123;10:glyph=119;11:glyph=31;
   12:glyph=78;13:glyph=61;14:glyph=79;15:glyph=71;
  endcase
 endfunction
 task check_display;
  integer seen,phase;
  begin
   seen=0;
   repeat(32)begin
    @(negedge clk);
    case(digital_cs)
     8'h11:phase=0;8'h22:phase=1;8'h44:phase=2;8'h88:phase=3;
     default:$fatal(1,"FAIL LAB1 invalid select %h",digital_cs);
    endcase
    if(digital_num0!==glyph((expected>>(phase*4))&15) ||
       digital_num1!==glyph((expected>>(16+phase*4))&15))
     $fatal(1,"FAIL LAB1 value=%h phase=%0d segments=%h/%h",expected,phase,digital_num0,digital_num1);
    seen=seen|(1<<phase);checks=checks+1;
   end
   if(seen!=15)$fatal(1,"FAIL LAB1 missing scan phase");
  end
 endtask
 task press(input [7:0] value);
  begin
   @(negedge clk);switch=value;center_btn_key=1;
   repeat(50)@(negedge clk);
   expected[byte_index*8+:8]=value;byte_index=(byte_index+1)%4;
   check_display(); // prolonged hold must write exactly one byte
   center_btn_key=0;
   repeat(50)@(negedge clk);
   check_display();
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);
  if(digital_cs!==0 || digital_num0!==0 || digital_num1!==0)$fatal(1,"FAIL LAB1 reset outputs");
  rst=1;repeat(5)@(negedge clk);check_display();
  switch=8'hff;center_btn_key=1;@(negedge clk);center_btn_key=0;
  repeat(50)@(negedge clk);check_display(); // reject a short pulse
  press(8'h10);press(8'h32);press(8'h54);press(8'h76);
  press(8'h98);press(8'hba);press(8'hdc);press(8'hfe);
  rst=0;center_btn_key=1;repeat(5)@(negedge clk);
  if(digital_cs!==0)$fatal(1,"FAIL LAB1 active reset");
  center_btn_key=0;expected=0;byte_index=0;rst=1;
  repeat(50)@(negedge clk);check_display();press(8'h1a);
  $display("PASS LAB1 checks=%0d all16glyphs fourphases bytewrap debounce heldbutton reset",checks);$finish;
 end
 initial begin #100000;$fatal(1,"FAIL LAB1 timeout");end
endmodule
