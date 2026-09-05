`timescale 1ns/1ps
module lab_soc #(parameter integer CLOCK_HZ=10000000, BAUD=115200,
 parameter ROM_FILE="board_rom.hex")(
 input wire clk,rst,uart_rx_pin,
 input wire [7:0] switches,
 output wire uart_tx_pin,
 output wire [7:0] led,digit_n,segment_n,
 output wire buzzer_pin,
 output wire [31:0] debug_pc,debug_result,debug_stores,
 output wire debug_done
);
 reg [31:0] rom[0:1023];
 (* ram_style="distributed" *) reg [7:0] ram0[0:1023];
 (* ram_style="distributed" *) reg [7:0] ram1[0:1023];
 (* ram_style="distributed" *) reg [7:0] ram2[0:1023];
 (* ram_style="distributed" *) reg [7:0] ram3[0:1023];
 reg [31:0] last_fibonacci;
 initial $readmemh(ROM_FILE,rom);
 wire [31:0] ia,da,dw,dr,instruction;
 wire [3:0] strb;
 wire illegal,trace_valid,trace_we;
 wire [4:0] trace_rd;
 wire [31:0] trace_data,trace_instr,trace_pc;
 wire monitor_reset,override_led,beep;
 wire [7:0] override_value;
 wire core_rst=rst|monitor_reset;
 reg [31:0] cycles,retired,stores,errors,display_value,buzzer_value;
 reg [7:0] led_value;
 reg done;
 wire [31:0] rx_errors;
 wire mmio=da[31:8]==24'h1f0000;
 wire ram_select=da[31:12]==20'h10010;
 reg [31:0] mmio_read;
 assign instruction=(ia[31:12]==20'h00400)?rom[ia[11:2]]:32'hffffffff;
 assign dr=mmio?mmio_read:(ram_select?{ram3[da[11:2]],ram2[da[11:2]],ram1[da[11:2]],ram0[da[11:2]]}:32'h0);
 single_cycle_cpu #(.RESET_PC(32'h00400000)) cpu(
 .clk(clk),.rst(core_rst),.imem_addr(ia),.imem_rdata(instruction),
 .dmem_addr(da),.dmem_wdata(dw),.dmem_wstrb(strb),.dmem_rdata(dr),
 .trace_valid(trace_valid),.trace_pc(trace_pc),.trace_instr(trace_instr),.trace_we(trace_we),
 .trace_rd(trace_rd),.trace_wdata(trace_data),.illegal(illegal));
 always @* begin
  case(da[7:2])
   0:mmio_read={24'h0,switches};
   1:mmio_read={24'h0,led_value};
   2:mmio_read=display_value;
   3:mmio_read=buzzer_value;
   7:mmio_read=cycles;
   8:mmio_read={31'h0,done};
   default:mmio_read=0;
  endcase
 end
 integer k;
 always @(posedge clk) begin
  if(!core_rst && ram_select) begin
   if(strb[0])ram0[da[11:2]]<=dw[7:0];
   if(strb[1])ram1[da[11:2]]<=dw[15:8];
   if(strb[2])ram2[da[11:2]]<=dw[23:16];
   if(strb[3])ram3[da[11:2]]<=dw[31:24];
  end
 end
 always @(posedge clk) begin
  if(core_rst) begin
   cycles<=0;retired<=0;stores<=0;errors<=0;display_value<=0;led_value<=0;buzzer_value<=0;done<=0;last_fibonacci<=0;
   // RAM is intentionally not reset; software initializes its used locations.
  end else begin
   cycles<=cycles+1;
   if(trace_valid)retired<=retired+1;
   if(illegal)errors<=errors+1;
   if(|strb) begin
    if(ram_select) begin
     stores<=stores+1;
     if(da[11:2]==11)for(k=0;k<4;k=k+1)if(strb[k])last_fibonacci[8*k+:8]<=dw[8*k+:8];
    end
    if(mmio) case(da[7:2])
     1:if(strb[0])led_value<=dw[7:0];
     2:for(k=0;k<4;k=k+1)if(strb[k])display_value[8*k+:8]<=dw[8*k+:8];
     3:for(k=0;k<4;k=k+1)if(strb[k])buzzer_value[8*k+:8]<=dw[8*k+:8];
     8:if(strb[0])done<=dw[0];
     default:begin end
    endcase
   end
  end
 end
 assign debug_pc=ia;
 assign debug_result=done?last_fibonacci:0;
 assign debug_stores=stores;
 assign debug_done=done;
 assign led=override_led?override_value:led_value;
 wire [31:0] status={30'h0,(errors!=0),done};
 wire [31:0] gpio={16'h0,switches,led};
 uart_control #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) control(
 .clk(clk),.rst(rst),.rx(uart_rx_pin),.telemetry({errors+rx_errors,retired,gpio,display_value,stores,cycles,debug_result,ia,status}),
 .tx(uart_tx_pin),.led_override(override_led),.led_value(override_value),.cpu_reset(monitor_reset),.beep(beep),.rx_errors(rx_errors));
 seven_segment #(.CLOCK_HZ(CLOCK_HZ),.SCAN_HZ(1000)) display(
 .clk(clk),.rst(rst),.value(display_value),.digit_n(digit_n),.segment_n(segment_n));
 buzzer #(.CLOCK_HZ(CLOCK_HZ)) sound(
 .clk(clk),.rst(rst),.enable(beep|buzzer_value[0]),.frequency_hz(16'd2000),.wave(buzzer_pin));
endmodule
