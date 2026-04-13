import cache_param_pkg::*;

`include "cache_if.sv"

module tb_cache();

    `define STRINGIFY(DEFINE) `"DEFINE`"

    parameter CLK_PERIOD = 10;          // 10 ns
    parameter MEM_LATENCY = 2;          // external memory response delay in cycles
    parameter RTL_READ_LATENCY = 2;     // cache hit latency

    typedef struct packed {
        logic [TAG_WIDTH  - 1 : 0] tag;
        logic [DATA_WIDTH - 1 : 0] data;
    } sram_cell_t;

    string cache_ini_file = `STRINGIFY(`CACHE_INI_FILE);

    // DUT interface
    logic clk;
    logic rstn;
    cache_if #(ADDR_WIDTH, DATA_WIDTH) cache_if_h (clk, rstn);

    // External memory model
    logic [DATA_WIDTH-1:0] ext_mem [0 : (2 ** (ADDR_WIDTH - 1)) - 1];
    logic [DATA_WIDTH-1:0] ext_mem_rdata;
    logic                  ext_mem_ack;
    logic                  ext_mem_req;
    int                    ext_mem_ack_delay;

    // Test control
    int                    error_cnt = 0;
    int                    test_phase = 0;
    bit                    test_done = 0;

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Reset generation
    task automatic reset_gen();
        rstn <= 1'b0;
        repeat(5) @(posedge clk);
        rstn <= 1'b1;
        repeat(2) @(posedge clk);
    endtask

    // Drive interface signals from testbench
    always_comb begin
        cache_if_h.ext_mem_ack  = ext_mem_ack;
        cache_if_h.ext_mem_data = ext_mem_rdata;
        cache_if_h.m_ready      = 1'b1;   // always ready
    end

    // Initialize external memory with some pattern (e.g., data = address)
    initial begin
        for (int i = 0; i < 2**ADDR_WIDTH; i++) begin
            ext_mem[i] = i;
        end
    end

    task automatic read_request(input  logic [ADDR_WIDTH-1:0] addr);
        cache_if_h.addr    <= addr;
        cache_if_h.s_valid <= 1'b1;
        @(posedge clk);
        while (!cache_if_h.s_ready) @(posedge clk);
        cache_if_h.s_valid <= 1'b0;
    endtask

    task automatic wait_ext_mem_req();
        do begin
            @(posedge clk);
        end while(cache_if_h.ext_mem_req !== 1);
    endtask

    task automatic gen_ext_mem_ack(int delay = 2);
        ext_mem_ack_delay = delay;
        repeat(ext_mem_ack_delay) @(posedge clk);
        ext_mem_ack   <= 1'b1;
        ext_mem_rdata <= ext_mem[cache_if_h.ext_mem_addr];
        @(posedge clk);
        ext_mem_ack   <= 1'b0;
        ext_mem_rdata <= 0;
    endtask

    task automatic wait_hit_valid(output logic hit, output logic [DATA_WIDTH - 1 : 0] rdata);
        do begin
            @(posedge clk);
        end while(cache_if_h.hit_valid !== 1);
        hit   = cache_if_h.hit;
        rdata = cache_if_h.data;
    endtask

    task automatic check_result(
        input string                 msg,
        input logic                  exp_hit,
        input logic [DATA_WIDTH-1:0] exp_data,
        input logic                  rec_hit,
        input logic [DATA_WIDTH-1:0] rec_data
    );
        if (rec_hit !== exp_hit) begin
            error_cnt++;
            $error("[%0t] %s: Hit mismatch. Expected %0b, got %0b",
                   $time(), msg, exp_hit, rec_hit);
        end else if (exp_hit && rec_data !== exp_data) begin
            error_cnt++;
            $error("[%0t] %s: Data mismatch. Expected 0x%08x, got 0x%08x",
                   $time(), msg, exp_data, rec_data);
        end else begin
            $display("[%0t] %s: OK (hit=%0b data=0x%08x)", $time(), msg, rec_hit, rec_data);
        end
    endtask

    // DUT instantiation
    cache_top #(
        .SETS        (SETS),
        .WAYS        (WAYS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) u_cache_top (
        .clk_i          (cache_if_h.clk),
        .rstn_i         (cache_if_h.rstn),
        .s_valid_i      (cache_if_h.s_valid),
        .s_ready_o      (cache_if_h.s_ready),
        .m_valid_o      (cache_if_h.m_valid),
        .m_ready_i      (cache_if_h.m_ready),
        .addr_i         (cache_if_h.addr),
        .data_o         (cache_if_h.data),
        .hit_valid_o    (cache_if_h.hit_valid),
        .hit_o          (cache_if_h.hit),
        .ext_mem_req_o  (cache_if_h.ext_mem_req),
        .ext_mem_addr_o (cache_if_h.ext_mem_addr),
        .ext_mem_data_i (cache_if_h.ext_mem_data),
        .ext_mem_ack_i  (cache_if_h.ext_mem_ack)
    );

    // Main test sequence
    initial begin
        logic [DATA_WIDTH - 1 : 0] cache_rdata;
        logic cache_hit;

        $display("==============================================");
        $display(" Starting Cache Test with LRU (SETS=%0d, WAYS=%0d)", SETS, WAYS);
        $display("==============================================");

        if (0) begin
            mem_list_gen #(TAG_WIDTH, DATA_WIDTH, CELL_AMOUNT, WAYS) mem_list_gen_h;
            sram_cell_t [CELL_AMOUNT - 1 : 0][WAYS - 1 : 0] generated_cells;
            logic [CELL_AMOUNT - 1 : 0][WAYS - 1 : 0] expected_valids;
            mem_list_gen_h = new();
            assert(mem_list_gen_h.generate_file(cache_ini_file, "%h", 1));
            mem_list_gen_h.get_generated_cells(expected_valids, generated_cells);
            // Initialize cache memory
            $readmemh(cache_ini_file, u_cache_top.u_cache_sram.sram);
        end

        cache_if_h.s_valid <= 1'b0;
        cache_if_h.addr    <= '0;

        reset_gen();

        repeat(5) @(posedge clk);

        read_request('h01);
        wait_ext_mem_req();
        fork
            gen_ext_mem_ack(3);
            wait_hit_valid(cache_hit, cache_rdata);
        join

        check_result("Addr = 0x1", 1'b1, ext_mem['h01], cache_hit, cache_rdata);

        // Finish
        repeat(10) @(posedge clk);
        $display("\n==============================================");
        if (error_cnt == 0)
            $display(" TEST PASSED");
        else
            $display(" TEST FAILED with %0d errors", error_cnt);
        $display("==============================================");
        test_done = 1;
        $finish;
    end

    initial begin
        repeat(1000) begin
            @(posedge clk);
        end
        if(!test_done) begin
            $display("\n==============================================");
            $error(" TEST TIMEOUTED with %0d errors!", error_cnt);
            $display("\n==============================================");
        end
        $finish;
    end

endmodule
