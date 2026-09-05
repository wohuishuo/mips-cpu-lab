`timescale 1ns/1ps

module data_cache #(
    parameter integer SETS = 16,
    parameter integer WORDS_PER_LINE = 4
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        cpu_valid,
    input  wire        cpu_write,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_wstrb,
    output wire        cpu_ready,
    output reg  [31:0] cpu_rdata,

    output wire        mem_valid,
    output wire        mem_write,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,

    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count,
    output reg  [31:0] writeback_count
);
    localparam integer SET_INDEX_BITS = (SETS > 1) ? $clog2(SETS) : 1;
    localparam integer WORD_INDEX_BITS =
        (WORDS_PER_LINE > 1) ? $clog2(WORDS_PER_LINE) : 1;
    localparam integer LINE_OFFSET_BITS = $clog2(WORDS_PER_LINE) + 2;
    localparam integer DATA_WORDS = SETS * WORDS_PER_LINE;

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_LOOKUP    = 3'd1;
    localparam [2:0] STATE_WRITEBACK = 3'd2;
    localparam [2:0] STATE_REFILL    = 3'd3;
    localparam [2:0] STATE_COMPLETE  = 3'd4;

    reg [2:0] state;

    reg [31:0] tag_way0 [0:SETS-1];
    reg [31:0] tag_way1 [0:SETS-1];
    reg        valid_way0 [0:SETS-1];
    reg        valid_way1 [0:SETS-1];
    reg        dirty_way0 [0:SETS-1];
    reg        dirty_way1 [0:SETS-1];
    reg        lru_way [0:SETS-1];
    reg [31:0] data_way0 [0:DATA_WORDS-1];
    reg [31:0] data_way1 [0:DATA_WORDS-1];

    reg        request_write;
    reg [31:0] request_addr;
    reg [31:0] request_wdata;
    reg [3:0]  request_wstrb;

    reg        victim_way;
    reg [31:0] victim_line_number;
    reg [WORD_INDEX_BITS-1:0] transfer_word;
    reg [31:0] refill_cpu_word;

    wire [31:0] request_line_number;
    wire [SET_INDEX_BITS-1:0] request_set;
    wire [WORD_INDEX_BITS-1:0] request_word;
    wire [31:0] request_line_base;
    wire hit_way0;
    wire hit_way1;
    wire selected_victim_way;
    wire selected_victim_valid;
    wire selected_victim_dirty;
    wire [31:0] selected_victim_line;
    wire [31:0] writeback_line_base;
    wire [31:0] transfer_byte_offset;
    wire [31:0] selected_writeback_data;

    integer reset_index;

    generate
        if ((SETS <= 0) || ((SETS & (SETS - 1)) != 0)) begin : invalid_sets
            initial begin
                $display("DATA_CACHE_PARAMETER_ERROR SETS=%0d expected positive power of two",
                         SETS);
                $error("data_cache has an invalid SETS parameter");
                $finish;
            end
        end else if ((WORDS_PER_LINE <= 0)
                     || ((WORDS_PER_LINE & (WORDS_PER_LINE - 1)) != 0)) begin : invalid_words_per_line
            initial begin
                $display("DATA_CACHE_PARAMETER_ERROR WORDS_PER_LINE=%0d expected positive power of two",
                         WORDS_PER_LINE);
                $error("data_cache has an invalid WORDS_PER_LINE parameter");
                $finish;
            end
        end
    endgenerate

    function [31:0] merge_bytes;
        input [31:0] previous;
        input [31:0] replacement;
        input [3:0] strobes;
        integer byte_lane;
        begin
            merge_bytes = previous;
            for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1) begin
                if (strobes[byte_lane])
                    merge_bytes[byte_lane*8 +: 8] =
                        replacement[byte_lane*8 +: 8];
            end
        end
    endfunction

    assign request_line_number = request_addr >> LINE_OFFSET_BITS;
    assign request_set = request_line_number & (SETS - 1);
    assign request_word = (request_addr >> 2) & (WORDS_PER_LINE - 1);
    assign request_line_base = request_line_number << LINE_OFFSET_BITS;

    assign hit_way0 = valid_way0[request_set]
                   && (tag_way0[request_set] == request_line_number);
    assign hit_way1 = valid_way1[request_set]
                   && (tag_way1[request_set] == request_line_number);

    assign selected_victim_way = !valid_way0[request_set] ? 1'b0
                               : !valid_way1[request_set] ? 1'b1
                               : lru_way[request_set];
    assign selected_victim_valid = selected_victim_way
                                 ? valid_way1[request_set]
                                 : valid_way0[request_set];
    assign selected_victim_dirty = selected_victim_way
                                 ? dirty_way1[request_set]
                                 : dirty_way0[request_set];
    assign selected_victim_line = selected_victim_way
                                ? tag_way1[request_set]
                                : tag_way0[request_set];

    assign writeback_line_base = victim_line_number << LINE_OFFSET_BITS;
    assign transfer_byte_offset = transfer_word << 2;
    assign selected_writeback_data = victim_way
        ? data_way1[request_set * WORDS_PER_LINE + transfer_word]
        : data_way0[request_set * WORDS_PER_LINE + transfer_word];

    assign cpu_ready = !rst && (state == STATE_COMPLETE);
    assign mem_valid = !rst
                    && ((state == STATE_WRITEBACK) || (state == STATE_REFILL));
    assign mem_write = (state == STATE_WRITEBACK);
    assign mem_addr = (state == STATE_WRITEBACK)
                    ? (writeback_line_base + transfer_byte_offset)
                    : (request_line_base + transfer_byte_offset);
    assign mem_wdata = (state == STATE_WRITEBACK)
                     ? selected_writeback_data : 32'b0;
    assign mem_wstrb = (state == STATE_WRITEBACK) ? 4'b1111 : 4'b0000;

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            request_write <= 1'b0;
            request_addr <= 32'b0;
            request_wdata <= 32'b0;
            request_wstrb <= 4'b0;
            victim_way <= 1'b0;
            victim_line_number <= 32'b0;
            transfer_word <= {WORD_INDEX_BITS{1'b0}};
            refill_cpu_word <= 32'b0;
            cpu_rdata <= 32'b0;
            hit_count <= 32'b0;
            miss_count <= 32'b0;
            writeback_count <= 32'b0;
            for (reset_index = 0; reset_index < SETS;
                 reset_index = reset_index + 1) begin
                valid_way0[reset_index] <= 1'b0;
                valid_way1[reset_index] <= 1'b0;
                dirty_way0[reset_index] <= 1'b0;
                dirty_way1[reset_index] <= 1'b0;
                lru_way[reset_index] <= 1'b0;
            end
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (cpu_valid) begin
                        request_write <= cpu_write;
                        request_addr <= cpu_addr;
                        request_wdata <= cpu_wdata;
                        request_wstrb <= cpu_wstrb;
                        state <= STATE_LOOKUP;
                    end
                end

                STATE_LOOKUP: begin
                    if (hit_way0) begin
                        hit_count <= hit_count + 1'b1;
                        lru_way[request_set] <= 1'b1;
                        if (request_write) begin
                            data_way0[request_set * WORDS_PER_LINE
                                      + request_word] <=
                                merge_bytes(
                                    data_way0[request_set * WORDS_PER_LINE
                                              + request_word],
                                    request_wdata, request_wstrb);
                            dirty_way0[request_set] <= 1'b1;
                        end else begin
                            cpu_rdata <= data_way0[
                                request_set * WORDS_PER_LINE + request_word];
                        end
                        state <= STATE_COMPLETE;
                    end else if (hit_way1) begin
                        hit_count <= hit_count + 1'b1;
                        lru_way[request_set] <= 1'b0;
                        if (request_write) begin
                            data_way1[request_set * WORDS_PER_LINE
                                      + request_word] <=
                                merge_bytes(
                                    data_way1[request_set * WORDS_PER_LINE
                                              + request_word],
                                    request_wdata, request_wstrb);
                            dirty_way1[request_set] <= 1'b1;
                        end else begin
                            cpu_rdata <= data_way1[
                                request_set * WORDS_PER_LINE + request_word];
                        end
                        state <= STATE_COMPLETE;
                    end else begin
                        miss_count <= miss_count + 1'b1;
                        victim_way <= selected_victim_way;
                        victim_line_number <= selected_victim_line;
                        transfer_word <= {WORD_INDEX_BITS{1'b0}};
                        if (selected_victim_valid && selected_victim_dirty)
                            state <= STATE_WRITEBACK;
                        else
                            state <= STATE_REFILL;
                    end
                end

                STATE_WRITEBACK: begin
                    if (mem_ready) begin
                        if (transfer_word == WORDS_PER_LINE - 1) begin
                            writeback_count <= writeback_count + 1'b1;
                            transfer_word <= {WORD_INDEX_BITS{1'b0}};
                            state <= STATE_REFILL;
                        end else begin
                            transfer_word <= transfer_word + 1'b1;
                        end
                    end
                end

                STATE_REFILL: begin
                    if (mem_ready) begin
                        if (victim_way) begin
                            data_way1[request_set * WORDS_PER_LINE
                                      + transfer_word] <=
                                (request_write && (request_word == transfer_word))
                                ? merge_bytes(mem_rdata, request_wdata,
                                              request_wstrb)
                                : mem_rdata;
                        end else begin
                            data_way0[request_set * WORDS_PER_LINE
                                      + transfer_word] <=
                                (request_write && (request_word == transfer_word))
                                ? merge_bytes(mem_rdata, request_wdata,
                                              request_wstrb)
                                : mem_rdata;
                        end

                        if (request_word == transfer_word)
                            refill_cpu_word <= mem_rdata;

                        if (transfer_word == WORDS_PER_LINE - 1) begin
                            if (victim_way) begin
                                tag_way1[request_set] <= request_line_number;
                                valid_way1[request_set] <= 1'b1;
                                dirty_way1[request_set] <= request_write;
                            end else begin
                                tag_way0[request_set] <= request_line_number;
                                valid_way0[request_set] <= 1'b1;
                                dirty_way0[request_set] <= request_write;
                            end
                            lru_way[request_set] <= ~victim_way;
                            if (!request_write) begin
                                cpu_rdata <= (request_word == transfer_word)
                                           ? mem_rdata : refill_cpu_word;
                            end
                            state <= STATE_COMPLETE;
                        end else begin
                            transfer_word <= transfer_word + 1'b1;
                        end
                    end
                end

                STATE_COMPLETE: begin
                    state <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
