`timescale 1ns/1ps

module tb_cache;
`ifdef CACHE_SMALL_VARIANT
    localparam integer SETS = 4;
    localparam integer WORDS_PER_LINE = 2;
`else
    localparam integer SETS = 16;
    localparam integer WORDS_PER_LINE = 4;
`endif
    localparam integer MEM_WORDS = 16384;

    reg clk;
    reg rst;

    reg         cpu_valid;
    reg         cpu_write;
    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    reg  [3:0]  cpu_wstrb;
    wire        cpu_ready;
    wire [31:0] cpu_rdata;

    wire        mem_valid;
    wire        mem_write;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_ready;
    wire [31:0] mem_rdata;

    wire [31:0] hit_count;
    wire [31:0] miss_count;
    wire [31:0] writeback_count;

    reg [31:0] backing_mem [0:MEM_WORDS-1];
    reg [31:0] reference_mem [0:MEM_WORDS-1];

    reg         memory_active;
    reg         held_mem_write;
    reg  [31:0] held_mem_addr;
    reg  [31:0] held_mem_wdata;
    reg  [3:0]  held_mem_wstrb;
    integer     memory_delay;
    integer     forced_delay;
    reg  [31:0] random_state;
    integer     memory_reads;
    integer     memory_writes;
    reg  [7:0]  random_delays_seen;
    integer     cpu_completions;
    integer     completions_since_reset;

    reg         cpu_stalled;
    reg         held_cpu_write;
    reg  [31:0] held_cpu_addr;
    reg  [31:0] held_cpu_wdata;
    reg  [3:0]  held_cpu_wstrb;

    integer i;
    integer random_iteration;
    integer completion_snapshot;
    integer backing_snapshot;
    integer memory_write_snapshot;
    reg [31:0] addr_a;
    reg [31:0] addr_b;
    reg [31:0] addr_c;
    reg [31:0] addr_d;
    reg [31:0] addr_e;
    reg [31:0] addr_f;
    reg [31:0] random_addr;
    reg [31:0] read_value;
    reg [31:0] write_value;
    reg [3:0]  write_mask;

    data_cache #(
        .SETS(SETS),
        .WORDS_PER_LINE(WORDS_PER_LINE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .cpu_valid(cpu_valid),
        .cpu_write(cpu_write),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_wstrb(cpu_wstrb),
        .cpu_ready(cpu_ready),
        .cpu_rdata(cpu_rdata),
        .mem_valid(mem_valid),
        .mem_write(mem_write),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .hit_count(hit_count),
        .miss_count(miss_count),
        .writeback_count(writeback_count)
    );

    function [31:0] make_addr;
        input integer tag_number;
        input integer set_number;
        input integer word_number;
        begin
            make_addr = (((tag_number * SETS) + set_number) * WORDS_PER_LINE
                         + word_number) * 4;
        end
    endfunction

    function integer memory_index;
        input [31:0] address;
        begin
            memory_index = (address >> 2) % MEM_WORDS;
        end
    endfunction

    function [31:0] merge_bytes;
        input [31:0] previous;
        input [31:0] replacement;
        input [3:0] strobes;
        integer lane;
        begin
            merge_bytes = previous;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (strobes[lane])
                    merge_bytes[lane*8 +: 8] = replacement[lane*8 +: 8];
            end
        end
    endfunction

    task automatic check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (!condition) begin
                $display("TB_CACHE_FAIL: %0s at time %0t", message, $time);
                $fatal(1);
            end
        end
    endtask

    task automatic apply_reset;
        begin
            @(negedge clk);
            rst = 1'b1;
            cpu_valid = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task automatic cpu_read_word;
        input [31:0] address;
        output [31:0] value;
        integer timeout;
        reg finished;
        begin
            @(negedge clk);
            cpu_valid = 1'b1;
            cpu_write = 1'b0;
            cpu_addr = address;
            cpu_wdata = 32'b0;
            cpu_wstrb = 4'b0000;
            timeout = 0;
            finished = 1'b0;
            while (!finished) begin
                @(posedge clk);
                timeout = timeout + 1;
                check(timeout < 1000, "CPU read timed out");
                if (cpu_ready) begin
                    value = cpu_rdata;
                    finished = 1'b1;
                end
            end
            @(negedge clk);
            cpu_valid = 1'b0;
            check(value === reference_mem[memory_index(address)],
                  "CPU read disagreed with independent reference memory");
        end
    endtask

    task automatic cpu_write_word;
        input [31:0] address;
        input [31:0] value;
        input [3:0] strobes;
        integer timeout;
        reg finished;
        begin
            @(negedge clk);
            cpu_valid = 1'b1;
            cpu_write = 1'b1;
            cpu_addr = address;
            cpu_wdata = value;
            cpu_wstrb = strobes;
            timeout = 0;
            finished = 1'b0;
            while (!finished) begin
                @(posedge clk);
                timeout = timeout + 1;
                check(timeout < 1000, "CPU write timed out");
                if (cpu_ready)
                    finished = 1'b1;
            end
            @(negedge clk);
            cpu_valid = 1'b0;
            reference_mem[memory_index(address)] =
                merge_bytes(reference_mem[memory_index(address)], value, strobes);
        end
    endtask

    assign mem_ready = memory_active && (memory_delay == 0);
    assign mem_rdata = backing_mem[memory_index(held_mem_addr)];

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            memory_active <= 1'b0;
            memory_delay <= 0;
        end else if (memory_active) begin
            check(mem_valid === 1'b1,
                  "cache dropped mem_valid before mem_ready completion");
            check(mem_write === held_mem_write,
                  "cache changed mem_write while memory request stalled");
            check(mem_addr === held_mem_addr,
                  "cache changed mem_addr while memory request stalled");
            check(mem_wdata === held_mem_wdata,
                  "cache changed mem_wdata while memory request stalled");
            check(mem_wstrb === held_mem_wstrb,
                  "cache changed mem_wstrb while memory request stalled");
            if (memory_delay != 0) begin
                memory_delay <= memory_delay - 1;
            end else begin
                if (held_mem_write) begin
                    backing_mem[memory_index(held_mem_addr)] <=
                        merge_bytes(backing_mem[memory_index(held_mem_addr)],
                                    held_mem_wdata, held_mem_wstrb);
                    memory_writes <= memory_writes + 1;
                end else begin
                    memory_reads <= memory_reads + 1;
                end
                memory_active <= 1'b0;
                random_state <= {random_state[30:0],
                                 random_state[31] ^ random_state[21]
                                 ^ random_state[1] ^ random_state[0]};
            end
        end else if (mem_valid) begin
            memory_active <= 1'b1;
            held_mem_write <= mem_write;
            held_mem_addr <= mem_addr;
            held_mem_wdata <= mem_wdata;
            held_mem_wstrb <= mem_wstrb;
            if (forced_delay >= 0)
                memory_delay <= forced_delay;
            else begin
                memory_delay <= random_state[2:0];
                random_delays_seen[random_state[2:0]] <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            cpu_stalled <= 1'b0;
            completions_since_reset <= 0;
            check(cpu_ready === 1'b0, "cpu_ready asserted during reset");
            check(mem_valid === 1'b0, "mem_valid asserted during reset");
        end else begin
            if (cpu_valid && cpu_ready) begin
                cpu_completions <= cpu_completions + 1;
                completions_since_reset <= completions_since_reset + 1;
                cpu_stalled <= 1'b0;
            end else if (cpu_valid) begin
                if (!cpu_stalled) begin
                    held_cpu_write <= cpu_write;
                    held_cpu_addr <= cpu_addr;
                    held_cpu_wdata <= cpu_wdata;
                    held_cpu_wstrb <= cpu_wstrb;
                    cpu_stalled <= 1'b1;
                end else begin
                    check(cpu_write === held_cpu_write,
                          "CPU request changed cpu_write while stalled");
                    check(cpu_addr === held_cpu_addr,
                          "CPU request changed cpu_addr while stalled");
                    check(cpu_wdata === held_cpu_wdata,
                          "CPU request changed cpu_wdata while stalled");
                    check(cpu_wstrb === held_cpu_wstrb,
                          "CPU request changed cpu_wstrb while stalled");
                end
            end else begin
                cpu_stalled <= 1'b0;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        cpu_valid = 1'b0;
        cpu_write = 1'b0;
        cpu_addr = 32'b0;
        cpu_wdata = 32'b0;
        cpu_wstrb = 4'b0;
        memory_active = 1'b0;
        memory_delay = 0;
        forced_delay = -1;
        random_state = 32'h1ace_b00c;
        memory_reads = 0;
        memory_writes = 0;
        random_delays_seen = 8'b0;
        cpu_completions = 0;
        completions_since_reset = 0;
        cpu_stalled = 1'b0;

        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            backing_mem[i] = 32'h4100_0000 ^ (i * 32'h0001_0203);
            reference_mem[i] = backing_mem[i];
        end

        addr_a = make_addr(1, 1, 0);
        addr_b = make_addr(2, 1, 0);
        addr_c = make_addr(3, 1, 0);
        addr_d = make_addr(20, 2 % SETS, WORDS_PER_LINE-1);
        addr_e = make_addr(21, 2 % SETS, WORDS_PER_LINE-1);
        addr_f = make_addr(22, 2 % SETS, WORDS_PER_LINE-1);

        apply_reset();
        check(hit_count == 0 && miss_count == 0 && writeback_count == 0,
              "reset did not clear counters");

        cpu_read_word(addr_a, read_value);
        check(miss_count == 1 && hit_count == 0,
              "cold access was not counted as one miss");
        cpu_read_word(addr_a, read_value);
        cpu_write_word(addr_a, 32'ha1b2_c3d4, 4'b0101);
        cpu_read_word(addr_a, read_value);
        cpu_read_word(addr_b, read_value);
        cpu_write_word(addr_b, 32'h89ab_cdef, 4'b1111);
        cpu_read_word(addr_a, read_value);
        cpu_read_word(addr_c, read_value);
        check(backing_mem[memory_index(addr_b)] ===
              reference_mem[memory_index(addr_b)],
              "dirty least-recently-used way was not written back");
        cpu_read_word(addr_b, read_value);
        check(backing_mem[memory_index(addr_a)] ===
              reference_mem[memory_index(addr_a)],
              "partial-byte dirty line did not persist on eviction");
        check(hit_count == 5 && miss_count == 4 && writeback_count == 2,
              "directed hit/miss/writeback counters were wrong");
        check(memory_reads == 4 * WORDS_PER_LINE,
              "directed misses issued duplicate or missing refill reads");
        check(memory_writes == 2 * WORDS_PER_LINE,
              "directed evictions issued duplicate or missing writes");

        /* Abort a refill. The request must not complete or reappear after reset. */
        forced_delay = 7;
        completion_snapshot = cpu_completions;
        @(negedge clk);
        cpu_valid = 1'b1;
        cpu_write = 1'b0;
        cpu_addr = make_addr(40, 0, 0);
        cpu_wdata = 0;
        cpu_wstrb = 0;
        wait (mem_valid && !mem_write);
        repeat (2) @(posedge clk);
        @(negedge clk);
        check(memory_active && memory_delay > 0,
              "refill was not actively stalled before reset");
        rst = 1'b1;
        cpu_valid = 1'b0;
        repeat (3) @(posedge clk);
        check(cpu_completions == completion_snapshot,
              "reset-aborted refill completed a CPU request");
        @(negedge clk);
        rst = 1'b0;
        forced_delay = -1;
        check(hit_count == 0 && miss_count == 0 && writeback_count == 0,
              "activity reset did not clear counters");
        cpu_read_word(make_addr(40, 0, 0), read_value);
        check(miss_count == 1, "reset did not invalidate cache lines");

        /* Abort an unaccepted dirty writeback and prove memory was untouched. */
        cpu_read_word(addr_d, read_value);
        cpu_write_word(addr_d, 32'h1357_9bdf, 4'b1111);
        cpu_read_word(addr_e, read_value);
        backing_snapshot = backing_mem[memory_index(addr_d)];
        memory_write_snapshot = memory_writes;
        forced_delay = 7;
        completion_snapshot = cpu_completions;
        @(negedge clk);
        cpu_valid = 1'b1;
        cpu_write = 1'b0;
        cpu_addr = addr_f;
        cpu_wdata = 0;
        cpu_wstrb = 0;
        wait (mem_valid && mem_write);
        repeat (2) @(posedge clk);
        @(negedge clk);
        check(memory_active && memory_delay > 0,
              "writeback was not actively stalled before reset");
        rst = 1'b1;
        cpu_valid = 1'b0;
        repeat (3) @(posedge clk);
        check(cpu_completions == completion_snapshot,
              "reset-aborted eviction completed a CPU request");
        check(backing_mem[memory_index(addr_d)] == backing_snapshot,
              "reset-aborted memory write changed backing memory");
        check(memory_writes == memory_write_snapshot,
              "reset-aborted memory write was accepted");
        @(negedge clk);
        rst = 1'b0;
        forced_delay = -1;
        reference_mem[memory_index(addr_d)] =
            backing_mem[memory_index(addr_d)];
        cpu_read_word(addr_d, read_value);

        cpu_write_word(addr_d, 32'h0000_00a5, 4'b0001);
        cpu_write_word(addr_d, 32'h0000_5a00, 4'b0010);
        cpu_write_word(addr_d, 32'h003c_0000, 4'b0100);
        cpu_write_word(addr_d, 32'hc300_0000, 4'b1000);
        cpu_read_word(addr_d, read_value);
        check(read_value == 32'hc33c_5aa5,
              "one or more individual byte strobes did not select its lane");

        /* Deterministic randomized traffic checks data and all byte lanes. */
        for (random_iteration = 0; random_iteration < 96;
             random_iteration = random_iteration + 1) begin
            random_state = random_state ^ (32'h9e37_79b9 + random_iteration);
            random_addr = make_addr(50 + (random_state[7:4] % 6),
                                    random_state[11:8] % SETS,
                                    random_state[15:12] % WORDS_PER_LINE);
            if (random_state[0]) begin
                write_value = random_state ^ (random_iteration * 32'h0101_0101);
                case (random_state[3:2])
                    2'd0: write_mask = 4'b0001;
                    2'd1: write_mask = 4'b0010;
                    2'd2: write_mask = 4'b0100;
                    default: write_mask = 4'b1000;
                endcase
                cpu_write_word(random_addr, write_value, write_mask);
                cpu_read_word(random_addr, read_value);
            end else begin
                cpu_read_word(random_addr, read_value);
            end
        end

        check(hit_count + miss_count == completions_since_reset,
              "hit plus miss count did not equal completed CPU requests");
        check(memory_reads > 0 && memory_writes > 0,
              "test did not exercise both backing-memory directions");
        check(random_delays_seen == 8'hff,
              "deterministic memory model did not cover delays 0 through 7");
        $display("TB_CACHE_PASS SETS=%0d WORDS_PER_LINE=%0d cpu=%0d mem_reads=%0d mem_writes=%0d hits=%0d misses=%0d writebacks=%0d",
                 SETS, WORDS_PER_LINE, cpu_completions, memory_reads,
                 memory_writes, hit_count, miss_count, writeback_count);
        $finish;
    end

    initial begin
        #2000000;
        $display("TB_CACHE_FAIL: global timeout");
        $fatal(1);
    end
endmodule
