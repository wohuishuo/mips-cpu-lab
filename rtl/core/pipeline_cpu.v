`timescale 1ns/1ps
// Five stage, in-order MIPS teaching pipeline. See docs/pipeline.md.
module pipeline_cpu #(parameter RESET_PC=32'hbfc00000, EXCEPTION_PC=32'hbfc00380)(
 input wire clk,rst,
 output wire [31:0] imem_addr,input wire [31:0] imem_rdata,
 output wire dmem_valid,dmem_write,output wire [31:0] dmem_addr,dmem_wdata,
 output wire [3:0] dmem_wstrb,input wire dmem_ready,input wire [31:0] dmem_rdata,
 input wire [5:0] hw_irq,
 output wire trace_valid,output wire [31:0] trace_pc,trace_instr,
 output wire trace_we,output wire [4:0] trace_rd,output wire [31:0] trace_wdata,
 output wire [3:0] trace_mem_we,output wire [31:0] trace_mem_addr,trace_mem_wdata,
 output wire exception_valid,output wire [4:0] exception_code,
 output wire [31:0] exception_epc,output wire exception_bd,
 output reg [31:0] cycle_count,retired_count,stall_count
);
 reg [31:0] regs[0:31];integer n;
 reg [31:0] if_pc;
 reg id_valid,ex_valid,mem_valid,wb_valid;
 reg [31:0] id_pc,id_instr,ex_pc,ex_instr,mem_pc,mem_instr,wb_pc,wb_instr;
 reg ex_bd;reg [31:0] ex_branch_pc;
 reg mem_we,mem_load,mem_store,mem_fault,mem_bd,mem_cpwrite,mem_eret;
 reg [4:0] mem_rd,mem_code,mem_cpaddr;reg [31:0] mem_value,mem_addr,mem_data,mem_epc,mem_bad;
 reg [3:0] mem_strobe;
 reg wb_we,wb_fault,wb_bd,wb_cpwrite,wb_eret;
 reg [4:0] wb_rd,wb_code,wb_cpaddr;reg [31:0] wb_value,wb_addr,wb_data,wb_epc,wb_bad;
 reg [3:0] wb_strobe;
 reg trap_wait;
 wire if_valid=!rst&&!trap_wait;
 wire [31:0] if_instr=imem_rdata;
 wire [5:0] op=ex_instr[31:26],fn=ex_instr[5:0];
 wire [4:0] rs=ex_instr[25:21],rt=ex_instr[20:16],rd=ex_instr[15:11],sa=ex_instr[10:6];
 wire [31:0] simm={{16{ex_instr[15]}},ex_instr[15:0]},zimm={16'b0,ex_instr[15:0]};
 reg [31:0] a,b;
 always @* begin
  a=rs==0?0:regs[rs];b=rt==0?0:regs[rt];
  if(wb_valid&&wb_we&&!wb_fault&&wb_rd!=0)begin if(wb_rd==rs)a=wb_value;if(wb_rd==rt)b=wb_value;end
  if(mem_valid&&mem_we&&!mem_load&&!mem_fault&&mem_rd!=0)begin if(mem_rd==rs)a=mem_value;if(mem_rd==rt)b=mem_value;end
 end
 wire [31:0] pc4=ex_pc+4,pc8=ex_pc+8,effective_addr=a+simm;
 reg write_reg,control_transfer,take_branch,illegal,is_load,is_store,cpwrite,is_eret,fault;
 reg [4:0] write_rd,fault_code;
 reg [31:0] write_data,transfer_target,store_data,fault_bad;
 reg [3:0] store_strobe;
 wire [31:0] cpread,status,cause,epc,badvaddr;wire irq_pending;
 cp0 system_control(.clk(clk),.rst(rst),.read_addr(rd),.read_data(cpread),
  .write_valid(wb_valid&&wb_cpwrite&&!wb_fault&&!rst),.write_addr(wb_cpaddr),.write_data(wb_data),
  .exception_valid(exception_valid),.exception_code(wb_code),.exception_pc(wb_epc),
  .exception_bd(wb_bd),.exception_badvaddr(wb_bad),.eret(wb_valid&&wb_eret&&!wb_fault&&!rst),
  .hw_irq(hw_irq),.status(status),.cause(cause),.epc(epc),.badvaddr(badvaddr),.irq_pending(irq_pending));
 always @* begin
  write_reg=0;write_rd=rt;write_data=0;control_transfer=0;take_branch=0;transfer_target=pc8;
  illegal=0;is_load=0;is_store=0;cpwrite=0;is_eret=0;fault=0;fault_code=0;fault_bad=effective_addr;
  store_data=b<<{effective_addr[1:0],3'b0};store_strobe=0;
  case(op)
   0:begin
    write_reg=1;write_rd=rd;
    case(fn)
     0:begin write_data=b<<sa;if(rs!=0)illegal=1;end
     2:begin write_data=b>>sa;if(rs!=0)illegal=1;end
     3:begin write_data=$signed(b)>>>sa;if(rs!=0)illegal=1;end
     4:begin write_data=b<<a[4:0];if(sa!=0)illegal=1;end
     6:begin write_data=b>>a[4:0];if(sa!=0)illegal=1;end
     7:begin write_data=$signed(b)>>>a[4:0];if(sa!=0)illegal=1;end
     8:begin write_reg=0;control_transfer=1;transfer_target=a;if(rt!=0||rd!=0||sa!=0)illegal=1;end
     9:begin write_data=pc8;control_transfer=1;transfer_target=a;if(rt!=0||sa!=0)illegal=1;end
     6'h0c:begin fault=1;fault_code=8;end
     6'h0d:begin fault=1;fault_code=9;end
     6'h20,6'h21:begin write_data=a+b;if(sa!=0)illegal=1;if(fn==6'h20&&a[31]==b[31]&&write_data[31]!=a[31])begin fault=1;fault_code=12;end end
     6'h22,6'h23:begin write_data=a-b;if(sa!=0)illegal=1;if(fn==6'h22&&a[31]!=b[31]&&write_data[31]!=a[31])begin fault=1;fault_code=12;end end
     6'h24:begin write_data=a&b;if(sa!=0)illegal=1;end
     6'h25:begin write_data=a|b;if(sa!=0)illegal=1;end
     6'h26:begin write_data=a^b;if(sa!=0)illegal=1;end
     6'h27:begin write_data=~(a|b);if(sa!=0)illegal=1;end
     6'h2a:begin write_data={31'b0,$signed(a)<$signed(b)};if(sa!=0)illegal=1;end
     6'h2b:begin write_data={31'b0,a<b};if(sa!=0)illegal=1;end
     default:illegal=1;
    endcase
   end
   1:begin
    control_transfer=1;
    case(rt)
     0:take_branch=$signed(a)<0;
     1:take_branch=$signed(a)>=0;
     16:begin take_branch=$signed(a)<0;write_reg=1;write_rd=31;write_data=pc8;end
     17:begin take_branch=$signed(a)>=0;write_reg=1;write_rd=31;write_data=pc8;end
     default:illegal=1;
    endcase
    transfer_target=take_branch?pc4+(simm<<2):pc8;
   end
   2,3:begin control_transfer=1;transfer_target={pc4[31:28],ex_instr[25:0],2'b00};if(op==3)begin write_reg=1;write_rd=31;write_data=pc8;end end
   4,5,6,7:begin
    control_transfer=1;
    case(op)
     4:take_branch=a==b;
     5:take_branch=a!=b;
     6:begin take_branch=$signed(a)<=0;if(rt!=0)illegal=1;end
     7:begin take_branch=$signed(a)>0;if(rt!=0)illegal=1;end
    endcase
    transfer_target=take_branch?pc4+(simm<<2):pc8;
   end
   8,9:begin write_reg=1;write_data=a+simm;if(op==8&&a[31]==simm[31]&&write_data[31]!=a[31])begin fault=1;fault_code=12;end end
   10:begin write_reg=1;write_data={31'b0,$signed(a)<$signed(simm)};end
   11:begin write_reg=1;write_data={31'b0,a<simm};end
   12:begin write_reg=1;write_data=a&zimm;end
   13:begin write_reg=1;write_data=a|zimm;end
   14:begin write_reg=1;write_data=a^zimm;end
   15:begin write_reg=1;write_data={ex_instr[15:0],16'b0};if(rs!=0)illegal=1;end
   16:begin
    if(ex_instr==32'h42000018)is_eret=1;
    else if(rs==0&&ex_instr[10:0]==0)begin write_reg=1;write_data=cpread;end
    else if(rs==4&&ex_instr[10:0]==0)cpwrite=1;
    else illegal=1;
   end
   32,33,35,36,37:begin
    write_reg=1;is_load=1;
    if(((op==33||op==37)&&effective_addr[0])||(op==35&&effective_addr[1:0]!=0))begin fault=1;fault_code=4;end
   end
   40,41,43:begin
    is_store=1;
    case(op)
     40:store_strobe=4'b0001<<effective_addr[1:0];
     41:begin store_strobe=4'b0011<<effective_addr[1:0];if(effective_addr[0])begin fault=1;fault_code=5;end end
     43:begin store_strobe=15;if(effective_addr[1:0]!=0)begin fault=1;fault_code=5;end end
    endcase
   end
   default:illegal=1;
  endcase
  if(ex_bd&&(control_transfer||is_eret))illegal=1;
  if(illegal)begin fault=1;fault_code=10;end
  if(ex_pc[1:0]!=0)begin fault=1;fault_code=4;fault_bad=ex_pc;end
  // Synchronous faults win; defer IRQ until a non-delay instruction boundary.
  if(!fault&&irq_pending&&!ex_bd)begin fault=1;fault_code=0;end
  if(fault)begin write_reg=0;is_load=0;is_store=0;store_strobe=0;cpwrite=0;is_eret=0;control_transfer=0;end
 end
 wire mem_wait=mem_valid&&(mem_load||mem_store)&&!dmem_ready;
 wire id_cp=id_instr[31:26]==16;
 wire serial_active=(ex_valid&&ex_instr[31:26]==16)||(mem_valid&&mem_instr[31:26]==16)||(wb_valid&&wb_instr[31:26]==16);
 // Conservative source matching also stalls unused encoded fields; correctness
 // does not depend on optimizing these occasional extra bubbles.
 wire load_use=ex_valid&&is_load&&write_rd!=0&&id_valid&&(write_rd==id_instr[25:21]||write_rd==id_instr[20:16]);
 wire serial_stall=serial_active||(id_valid&&id_cp&&(ex_valid||mem_valid||wb_valid));
 wire front_stall=load_use||serial_stall;
 assign imem_addr=if_pc;
 assign dmem_valid=!rst&&mem_valid&&!mem_fault&&(mem_load||mem_store);
 assign dmem_write=mem_store;
 assign dmem_addr=mem_addr;assign dmem_wdata=mem_data;assign dmem_wstrb=dmem_valid&&mem_store?mem_strobe:4'b0;
 assign trace_valid=!rst&&wb_valid&&!wb_fault;
 assign trace_pc=wb_pc;assign trace_instr=wb_instr;
 assign trace_we=trace_valid&&wb_we&&wb_rd!=0;assign trace_rd=wb_rd;assign trace_wdata=wb_value;
 assign trace_mem_we=trace_valid?wb_strobe:4'b0;assign trace_mem_addr=wb_addr;assign trace_mem_wdata=wb_data;
 assign exception_valid=!rst&&wb_valid&&wb_fault;assign exception_code=wb_code;assign exception_epc=wb_epc;assign exception_bd=wb_bd;
 wire [31:0] lane=dmem_rdata>>{mem_addr[1:0],3'b0};reg [31:0] load_value;
 always @* begin
  case(mem_instr[31:26])
   32:load_value={{24{lane[7]}},lane[7:0]};33:load_value={{16{lane[15]}},lane[15:0]};
   36:load_value={24'b0,lane[7:0]};37:load_value={16'b0,lane[15:0]};default:load_value=dmem_rdata;
  endcase
 end
 always @(posedge clk)begin
  if(rst)begin
   if_pc<=RESET_PC;id_valid<=0;ex_valid<=0;mem_valid<=0;wb_valid<=0;trap_wait<=0;
   id_pc<=0;id_instr<=0;ex_pc<=0;ex_instr<=0;mem_pc<=0;mem_instr<=0;wb_pc<=0;wb_instr<=0;ex_bd<=0;ex_branch_pc<=0;
   mem_we<=0;mem_load<=0;mem_store<=0;mem_fault<=0;mem_bd<=0;mem_cpwrite<=0;mem_eret<=0;mem_rd<=0;mem_code<=0;mem_cpaddr<=0;mem_value<=0;mem_addr<=0;mem_data<=0;mem_epc<=0;mem_bad<=0;mem_strobe<=0;
   wb_we<=0;wb_fault<=0;wb_bd<=0;wb_cpwrite<=0;wb_eret<=0;wb_rd<=0;wb_code<=0;wb_cpaddr<=0;wb_value<=0;wb_addr<=0;wb_data<=0;wb_epc<=0;wb_bad<=0;wb_strobe<=0;
   cycle_count<=0;retired_count<=0;stall_count<=0;
   for(n=0;n<32;n=n+1)regs[n]<=0;
  end else begin
   cycle_count<=cycle_count+1;if(trace_valid)retired_count<=retired_count+1;
   if(mem_wait||front_stall||trap_wait)stall_count<=stall_count+1;
   if(trace_we)regs[wb_rd]<=wb_value;regs[0]<=0;
   // WB drains even while MEM waits; no repeated architectural retirement.
   wb_valid<=0;
   if(exception_valid||(wb_valid&&wb_eret))begin
    if_pc<=exception_valid?EXCEPTION_PC:epc;id_valid<=0;ex_valid<=0;mem_valid<=0;trap_wait<=0;
   end else if(!mem_wait)begin
    wb_valid<=mem_valid;wb_pc<=mem_pc;wb_instr<=mem_instr;wb_we<=mem_we;wb_rd<=mem_rd;
    wb_value<=mem_load?load_value:mem_value;wb_addr<=mem_addr;wb_data<=mem_data;wb_strobe<=mem_store?mem_strobe:4'b0;
    wb_fault<=mem_fault;wb_code<=mem_code;wb_epc<=mem_epc;wb_bd<=mem_bd;wb_bad<=mem_bad;wb_cpwrite<=mem_cpwrite;wb_cpaddr<=mem_cpaddr;wb_eret<=mem_eret;
    mem_valid<=ex_valid;mem_pc<=ex_pc;mem_instr<=ex_instr;mem_we<=write_reg;mem_rd<=write_rd;mem_value<=write_data;
    mem_load<=is_load;mem_store<=is_store;mem_addr<=effective_addr;mem_data<=cpwrite?b:store_data;mem_strobe<=store_strobe;
    mem_fault<=fault;mem_code<=fault_code;mem_epc<=ex_bd?ex_branch_pc:ex_pc;mem_bd<=ex_bd;mem_bad<=fault_bad;
    mem_cpwrite<=cpwrite;mem_cpaddr<=rd;mem_eret<=is_eret;
    ex_valid<=0;
    if(ex_valid&&fault)begin id_valid<=0;trap_wait<=1;end
    else if(!trap_wait)begin
     if(ex_valid&&control_transfer)begin
      ex_valid<=id_valid;ex_pc<=id_pc;ex_instr<=id_instr;ex_bd<=1;ex_branch_pc<=ex_pc;
      id_valid<=0;if_pc<=transfer_target;
     end else if(!front_stall)begin
      ex_valid<=id_valid;ex_pc<=id_pc;ex_instr<=id_instr;ex_bd<=0;
      id_valid<=1;id_pc<=if_pc;id_instr<=imem_rdata;if_pc<=if_pc+4;
     end
    end
   end
  end
 end
endmodule
