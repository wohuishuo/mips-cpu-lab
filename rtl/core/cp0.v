`timescale 1ns/1ps
module cp0(
 input wire clk,rst,
 input wire [4:0] read_addr,write_addr,
 input wire [31:0] write_data,
 input wire write_valid,
 output wire [31:0] read_data,
 input wire exception_valid,
 input wire [4:0] exception_code,
 input wire [31:0] exception_pc,exception_badvaddr,
 input wire exception_bd,eret,
 input wire [5:0] hw_irq,
 output wire [31:0] status,cause,epc,badvaddr,
 output wire irq_pending
);
reg [31:0] status_reg,epc_reg,badvaddr_reg,count_reg,compare_reg;
reg [4:0] code_reg;
reg bd_reg,timer_pending;
reg [1:0] software_pending;
wire [7:0] pending={hw_irq[5] | timer_pending,hw_irq[4:0],software_pending};
wire software_write_accepted=write_valid && !exception_valid && !eret;
wire count_write_accepted=software_write_accepted && write_addr==9;
wire compare_write_accepted=software_write_accepted && write_addr==11;
wire [31:0] count_next=count_write_accepted?write_data:count_reg+32'd1;
assign status=status_reg;
assign epc=epc_reg;
assign badvaddr=badvaddr_reg;
assign cause={bd_reg,timer_pending,14'b0,pending,1'b0,code_reg,2'b0};
assign irq_pending=status_reg[0] && !status_reg[1] && |(pending & status_reg[15:8]);
assign read_data=(read_addr==8)?badvaddr_reg:
                 (read_addr==9)?count_reg:
                 (read_addr==11)?compare_reg:
                 (read_addr==12)?status_reg:
                 (read_addr==13)?cause:
                 (read_addr==14)?epc_reg:
                 (read_addr==15)?32'h00018000:32'b0;
always @(posedge clk) begin
 if(rst) begin
  status_reg<=32'h00400000;epc_reg<=0;badvaddr_reg<=0;
  count_reg<=0;compare_reg<=0;code_reg<=0;bd_reg<=0;
 timer_pending<=0;software_pending<=0;
 end else begin
  count_reg<=count_next;
  if(compare_write_accepted)timer_pending<=0;
  else if(count_next==compare_reg)timer_pending<=1;
  if(exception_valid) begin
   status_reg[1]<=1;
   code_reg<=exception_code;
   if(!status_reg[1]) begin epc_reg<=exception_pc;bd_reg<=exception_bd;end
   if(exception_code==4 || exception_code==5)badvaddr_reg<=exception_badvaddr;
  end else if(eret) begin
   status_reg[1]<=0;
  end else if(write_valid) begin
   case(write_addr)
    9: begin end
    11: compare_reg<=write_data;
    12: status_reg<=write_data;
    13: software_pending<=write_data[9:8];
    14: epc_reg<=write_data;
    default: begin end
   endcase
  end
 end
end
endmodule
