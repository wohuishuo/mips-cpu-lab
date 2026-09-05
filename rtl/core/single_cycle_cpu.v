`timescale 1ns/1ps
// Single-cycle teaching reference. Combinational memories, little endian.
// ADD/ADDI/SUB wrap here; precise overflow exceptions belong to pipeline_cpu.
module single_cycle_cpu #(
    parameter RESET_PC = 32'hbfc00000
)(
    input wire clk, input wire rst,
    output wire [31:0] imem_addr, input wire [31:0] imem_rdata,
    output reg [31:0] dmem_addr, output reg [31:0] dmem_wdata,
    output reg [3:0] dmem_wstrb, input wire [31:0] dmem_rdata,
    output wire trace_valid, output wire [31:0] trace_pc,
    output wire [31:0] trace_instr, output wire trace_we,
    output wire [4:0] trace_rd, output wire [31:0] trace_wdata,
    output reg illegal
);
    reg [31:0] pc;
    reg [31:0] regs [0:31];
    // Record a redirect for every branch, including its untaken PC+8 path.
    reg delay_pending;
    reg [31:0] delay_target;
    wire [5:0] op = imem_rdata[31:26];
    wire [5:0] fn = imem_rdata[5:0];
    wire [4:0] rs = imem_rdata[25:21];
    wire [4:0] rt = imem_rdata[20:16];
    wire [4:0] rd = imem_rdata[15:11];
    wire [4:0] sa = imem_rdata[10:6];
    wire [31:0] a = rs == 0 ? 32'b0 : regs[rs];
    wire [31:0] b = rt == 0 ? 32'b0 : regs[rt];
    wire [31:0] simm = {{16{imem_rdata[15]}},imem_rdata[15:0]};
    wire [31:0] zimm = {16'b0,imem_rdata[15:0]};
    wire [31:0] pc4 = pc + 32'd4;
    wire [31:0] pc8 = pc + 32'd8;
    wire [31:0] effective_addr = a + simm;
    wire [31:0] load_lane = dmem_rdata >> {effective_addr[1:0],3'b0};
    reg write_reg, control_transfer, take_branch;
    reg [4:0] write_rd;
    reg [31:0] write_data, transfer_target;
    integer n;

    assign imem_addr = pc;
    assign trace_valid = !rst;
    assign trace_pc = pc;
    assign trace_instr = imem_rdata;
    assign trace_we = !rst && !illegal && write_reg && write_rd != 0;
    assign trace_rd = write_rd;
    assign trace_wdata = write_data;

    always @* begin
        write_reg = 0;
        write_rd = rt;
        write_data = 0;
        dmem_addr = effective_addr;
        dmem_wdata = b << {effective_addr[1:0],3'b0};
        dmem_wstrb = 0;
        control_transfer = 0;
        transfer_target = pc8;
        take_branch = 0;
        illegal = 0;
        case (op)
            6'h00: begin
                write_reg = 1;
                write_rd = rd;
                case(fn)
                    6'h00: begin write_data = b << sa; if(rs != 0) illegal=1; end
                    6'h02: begin write_data = b >> sa; if(rs != 0) illegal=1; end
                    6'h03: begin write_data = $signed(b) >>> sa; if(rs != 0) illegal=1; end
                    6'h04: begin write_data = b << a[4:0]; if(sa != 0) illegal=1; end
                    6'h06: begin write_data = b >> a[4:0]; if(sa != 0) illegal=1; end
                    6'h07: begin write_data = $signed(b) >>> a[4:0]; if(sa != 0) illegal=1; end
                    6'h08: begin
                        write_reg=0; control_transfer=1; transfer_target=a;
                        if(rt != 0 || rd != 0 || sa != 0 || a[1:0] != 0) illegal=1;
                    end
                    6'h09: begin
                        write_data=pc8; control_transfer=1; transfer_target=a;
                        if(rt != 0 || sa != 0 || a[1:0] != 0) illegal=1;
                    end
                    6'h20,6'h21: begin write_data=a+b; if(sa != 0) illegal=1; end
                    6'h22,6'h23: begin write_data=a-b; if(sa != 0) illegal=1; end
                    6'h24: begin write_data=a&b; if(sa != 0) illegal=1; end
                    6'h25: begin write_data=a|b; if(sa != 0) illegal=1; end
                    6'h26: begin write_data=a^b; if(sa != 0) illegal=1; end
                    6'h27: begin write_data=~(a|b); if(sa != 0) illegal=1; end
                    6'h2a: begin write_data={31'b0,$signed(a)<$signed(b)}; if(sa != 0) illegal=1; end
                    6'h2b: begin write_data={31'b0,a<b}; if(sa != 0) illegal=1; end
                    default: illegal=1;
                endcase
            end
            6'h01: begin
                control_transfer=1;
                case(rt)
                    5'h00: take_branch=$signed(a)<0;
                    5'h01: take_branch=$signed(a)>=0;
                    // REGIMM link variants write $31 independently of outcome.
                    5'h10: begin take_branch=$signed(a)<0; write_reg=1; write_rd=31; write_data=pc8; end
                    5'h11: begin take_branch=$signed(a)>=0; write_reg=1; write_rd=31; write_data=pc8; end
                    default: illegal=1;
                endcase
                transfer_target=take_branch ? pc4+(simm<<2) : pc8;
            end
            6'h02,6'h03: begin
                control_transfer=1;
                transfer_target={pc4[31:28],imem_rdata[25:0],2'b00};
                if(op==6'h03)begin write_reg=1;write_rd=31;write_data=pc8;end
            end
            6'h04,6'h05,6'h06,6'h07: begin
                control_transfer=1;
                case(op)
                    6'h04: take_branch=a==b;
                    6'h05: take_branch=a!=b;
                    6'h06: begin take_branch=$signed(a)<=0;if(rt!=0)illegal=1;end
                    6'h07: begin take_branch=$signed(a)>0;if(rt!=0)illegal=1;end
                endcase
                transfer_target=take_branch ? pc4+(simm<<2) : pc8;
            end
            6'h08,6'h09: begin write_reg=1;write_data=a+simm;end
            6'h0a: begin write_reg=1;write_data={31'b0,$signed(a)<$signed(simm)};end
            6'h0b: begin write_reg=1;write_data={31'b0,a<simm};end
            6'h0c: begin write_reg=1;write_data=a&zimm;end
            6'h0d: begin write_reg=1;write_data=a|zimm;end
            6'h0e: begin write_reg=1;write_data=a^zimm;end
            6'h0f: begin write_reg=1;write_data={imem_rdata[15:0],16'b0};if(rs!=0)illegal=1;end
            6'h20: begin write_reg=1;write_data={{24{load_lane[7]}},load_lane[7:0]};end
            6'h21: begin write_reg=1;write_data={{16{load_lane[15]}},load_lane[15:0]};if(effective_addr[0])illegal=1;end
            6'h23: begin write_reg=1;write_data=dmem_rdata;if(effective_addr[1:0]!=0)illegal=1;end
            6'h24: begin write_reg=1;write_data={24'b0,load_lane[7:0]};end
            6'h25: begin write_reg=1;write_data={16'b0,load_lane[15:0]};if(effective_addr[0])illegal=1;end
            6'h28: dmem_wstrb=4'b0001<<effective_addr[1:0];
            6'h29: begin dmem_wstrb=4'b0011<<effective_addr[1:0];if(effective_addr[0])illegal=1;end
            6'h2b: begin dmem_wstrb=4'b1111;if(effective_addr[1:0]!=0)illegal=1;end
            default: illegal=1;
        endcase
        // A control transfer in a delay slot is architecturally unpredictable.
        // This reference rejects it deterministically without replacing redirect.
        if(pc[1:0]!=0 || (delay_pending && control_transfer)) illegal=1;
        if(illegal || rst)begin
            write_reg=0;
            dmem_wstrb=0;
            control_transfer=0;
        end
        if(rst)illegal=0;
    end

    always @(posedge clk) begin
        if(rst)begin
            pc<=RESET_PC;
            delay_pending<=0;
            delay_target<=0;
            for(n=0;n<32;n=n+1)regs[n]<=0;
        end else begin
            pc<=delay_pending ? delay_target : pc4;
            delay_pending<=control_transfer;
            if(control_transfer)delay_target<=transfer_target;
            if(trace_we)regs[write_rd]<=write_data;
            regs[0]<=0;
        end
    end
endmodule
