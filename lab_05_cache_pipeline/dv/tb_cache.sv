import cache_param_pkg::*;

`include "cache_if.sv"

module tb_cache();

    parameter int CLK_PERIOD           = 2;
    parameter int RESPONSE_TIMEOUT     = 200;
    parameter int DEFAULT_EXT_MEM_WAIT = 3;

    // Number of back-to-back requests in the throughput test.
    // For SETS > 1: use full cache capacity (SETS * WAYS) so all burst addresses
    // fit simultaneously. Addresses cycle sets (i % SETS) with unique tags → no
    // s0_same_set_hazard between adjacent requests → 1 hit/cycle throughput.
    // For SETS = 1: same-set hazard is unavoidable; use 2 requests for correctness.
    localparam int BURST_LEN = (SETS > 1) ? SETS * WAYS : 2;

    typedef logic [ADDR_WIDTH - 1 : 0] addr_t;
    typedef logic [DATA_WIDTH - 1 : 0] data_t;
    typedef logic [TAG_WIDTH  - 1 : 0] tag_t;
    typedef logic [SET_WIDTH  - 1 : 0] set_idx_t;

    int unsigned error_cnt       = 0;
    int unsigned ext_mem_req_cnt = 0;
    int unsigned ext_mem_delay   = DEFAULT_EXT_MEM_WAIT;
    bit          ext_mem_req_prev;

    logic clk;
    logic rstn;

    // Interface signals
    cache_if #(ADDR_WIDTH, DATA_WIDTH) cache_if_h (
        .clk  (clk),
        .rstn (rstn)
    );

    virtual cache_if #(ADDR_WIDTH, DATA_WIDTH) cache_vif_h;

    // DUT
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

    function automatic addr_t make_addr(
        input tag_t    tag_value,
        input set_idx_t set_value
    );
        if(SETS == 1) begin
            make_addr = tag_value;
        end else begin
            make_addr = {tag_value, set_value};
        end
    endfunction

    function automatic set_idx_t test_set(input int unsigned idx);
        if(SETS == 1) begin
            test_set = '0;
        end else begin
            test_set = set_idx_t'(idx % SETS);
        end
    endfunction

    function automatic tag_t test_tag(input int unsigned idx);
        test_tag = tag_t'(idx + 1);
    endfunction

    function automatic data_t ext_mem_data_for_addr(input addr_t addr);
        ext_mem_data_for_addr = data_t'(addr) ^ data_t'(32'hcace_0001);
    endfunction

    task automatic report_error(input string msg);
        error_cnt++;
        $error("[%0t] %s (#%0d)", $time(), msg, error_cnt);
    endtask

    task automatic wait_for_s_ready(input int unsigned timeout = RESPONSE_TIMEOUT);
        int unsigned cycles = 0;
        while(cache_vif_h.s_ready !== 1'b1) begin
            @(negedge cache_vif_h.clk);
            cycles++;
            if(cycles >= timeout) begin
                report_error("Timeout while waiting for s_ready_o");
                break;
            end
        end
    endtask

    task automatic apply_reset();
        @(negedge cache_vif_h.clk);
        cache_vif_h.s_valid      <= 1'b0;
        cache_vif_h.addr         <= '0;
        cache_vif_h.m_ready      <= 1'b1;
        cache_vif_h.ext_mem_ack  <= 1'b0;
        cache_vif_h.ext_mem_data <= '0;
        rstn                     <= 1'b0;

        repeat(5) @(posedge cache_vif_h.clk);

        @(negedge cache_vif_h.clk);
        rstn <= 1'b1;
        wait_for_s_ready(RESPONSE_TIMEOUT);
    endtask

    task automatic send_read_request(input addr_t req_addr);
        @(negedge cache_vif_h.clk);
        cache_vif_h.addr    <= req_addr;
        cache_vif_h.s_valid <= 1'b1;

        forever begin
            if(cache_vif_h.s_ready === 1'b1) begin
                @(posedge cache_vif_h.clk);
                break;
            end
            @(negedge cache_vif_h.clk);
        end

        @(negedge cache_vif_h.clk);
        cache_vif_h.s_valid <= 1'b0;
    endtask

    task automatic wait_for_response(
        output logic hit,
        output data_t data,
        input  int unsigned timeout = RESPONSE_TIMEOUT,
        input  bit consume_response = 1'b1
    );
        int unsigned cycles = 0;

        while(cache_vif_h.m_valid !== 1'b1) begin
            @(posedge cache_vif_h.clk);
            cycles++;
            if(cycles >= timeout) begin
                report_error("Timeout while waiting for m_valid_o");
                break;
            end
        end

        @(negedge cache_vif_h.clk);
        hit  = cache_vif_h.hit;
        data = cache_vif_h.data;

        if(cache_vif_h.hit_valid !== cache_vif_h.m_valid) begin
            report_error("hit_valid_o is not aligned with m_valid_o");
        end

        if(consume_response) begin
            @(posedge cache_vif_h.clk);
        end
    endtask

    task automatic check_read(
        input addr_t req_addr,
        input bit    exp_hit,
        input string check_name = ""
    );
        logic        hit_rec;
        data_t       data_rec;
        data_t       data_exp;
        int unsigned req_cnt_before;
        int unsigned req_delta;

        data_exp       = ext_mem_data_for_addr(req_addr);
        req_cnt_before = ext_mem_req_cnt;

        send_read_request(req_addr);
        wait_for_response(hit_rec, data_rec);

        req_delta = ext_mem_req_cnt - req_cnt_before;

        if(hit_rec !== exp_hit) begin
            report_error($sformatf("%s: wrong hit value. received=%0b expected=%0b",
                check_name, hit_rec, exp_hit));
        end

        if(data_rec !== data_exp) begin
            report_error($sformatf("%s: wrong data value. received=0x%x expected=0x%x",
                check_name, data_rec, data_exp));
        end

        if(req_delta != (exp_hit ? 0 : 1)) begin
            report_error($sformatf("%s: wrong ext_mem_req pulse count. received=%0d expected=%0d",
                check_name, req_delta, (exp_hit ? 0 : 1)));
        end
    endtask

    task automatic check_delayed_miss_stall();
        addr_t       req_addr;
        logic        hit_rec;
        data_t       data_rec;
        int unsigned req_cnt_before;
        int unsigned cycles;

        $display("\n[%0t] CHECK: delayed miss stalls input", $time());
        apply_reset();
        ext_mem_delay = 6;
        req_addr = make_addr(test_tag(10), test_set(0));
        req_cnt_before = ext_mem_req_cnt;

        send_read_request(req_addr);

        // In the pipeline the miss takes 2 cycles to reach REFILL (S2).
        // Wait for ext_mem_req pulse — it fires when CHECK_TAG (S1) detects the miss
        // and is advancing the request into REFILL. Sample at negedge for settled
        // combinational value (ext_mem_req is combinatorial, not registered).
        begin : wait_miss_inflight
            int unsigned pre_cycles;
            pre_cycles = 0;
            // send_read_request already returned at a negedge; check immediately
            while (cache_vif_h.ext_mem_req !== 1'b1) begin
                @(posedge cache_vif_h.clk);
                @(negedge cache_vif_h.clk);
                pre_cycles++;
                if (pre_cycles >= RESPONSE_TIMEOUT) begin
                    report_error("ext_mem_req_o never fired for delayed miss");
                    break;
                end
            end
        end
        // ext_mem_req seen high at negedge; on the next posedge S1 advances to S2
        @(posedge cache_vif_h.clk);

        cycles = 0;
        while(cache_vif_h.m_valid !== 1'b1) begin
            @(posedge cache_vif_h.clk);
            cycles++;
            @(negedge cache_vif_h.clk);
            // ext_mem_ack arriving drops s2_stall combinatorially → s_ready goes high
            // one cycle before m_valid (pipeline behaviour). Exclude the ack cycle.
            if(cache_vif_h.m_valid !== 1'b1 && cache_vif_h.s_ready !== 1'b0
               && cache_vif_h.ext_mem_ack !== 1'b1) begin
                report_error("s_ready_o is high while delayed miss is in flight");
            end
            if(cycles >= RESPONSE_TIMEOUT) begin
                report_error("Timeout in delayed miss stall check");
                break;
            end
        end

        hit_rec  = cache_vif_h.hit;
        data_rec = cache_vif_h.data;

        if(cache_vif_h.hit_valid !== cache_vif_h.m_valid) begin
            report_error("hit_valid_o is not aligned with m_valid_o during delayed miss");
        end

        @(posedge cache_vif_h.clk);

        if(hit_rec !== 1'b0) begin
            report_error("Delayed first access must be reported as miss");
        end
        if(data_rec !== ext_mem_data_for_addr(req_addr)) begin
            report_error("Delayed miss returned wrong data");
        end
        if((ext_mem_req_cnt - req_cnt_before) != 1) begin
            report_error("Delayed miss must produce exactly one ext_mem_req pulse");
        end

        ext_mem_delay = DEFAULT_EXT_MEM_WAIT;
    endtask

    task automatic check_first_miss_then_hit();
        addr_t req_addr;

        $display("\n[%0t] CHECK: first access misses, second access hits", $time());
        apply_reset();
        ext_mem_delay = DEFAULT_EXT_MEM_WAIT;
        req_addr = make_addr(test_tag(1), test_set(0));

        check_read(req_addr, 1'b0, "first access");
        check_read(req_addr, 1'b1, "second access");
    endtask

    task automatic check_invalid_first_replacement();
        tag_t     tags [0 : WAYS - 1];
        set_idx_t set_value;
        addr_t    req_addr;

        $display("\n[%0t] CHECK: invalid ways are used before eviction", $time());
        apply_reset();
        set_value = test_set(0);

        for(int way = 0; way < WAYS; way++) begin
            tags[way] = test_tag(100 + way);
        end

        for(int way = 0; way < WAYS; way++) begin
            req_addr = make_addr(tags[way], set_value);
            check_read(req_addr, 1'b0, $sformatf("fill invalid way %0d", way));

            for(int prev = 0; prev <= way; prev++) begin
                req_addr = make_addr(tags[prev], set_value);
                check_read(req_addr, 1'b1, $sformatf("filled way %0d remains valid", prev));
            end
        end
    endtask

    task automatic check_lru_replacement();
        tag_t     tags [0 : WAYS];
        tag_t     evicted_tag;
        set_idx_t set_value;
        addr_t    req_addr;

        $display("\n[%0t] CHECK: exact LRU replacement", $time());
        apply_reset();
        set_value = test_set(0);

        for(int way = 0; way <= WAYS; way++) begin
            tags[way] = test_tag(200 + way);
        end

        for(int way = 0; way < WAYS; way++) begin
            req_addr = make_addr(tags[way], set_value);
            check_read(req_addr, 1'b0, $sformatf("LRU fill way %0d", way));
        end

        req_addr = make_addr(tags[0], set_value);
        check_read(req_addr, 1'b1, "make tag0 most-recently-used");

        req_addr = make_addr(tags[WAYS], set_value);
        check_read(req_addr, 1'b0, "insert new tag and evict LRU");
        check_read(req_addr, 1'b1, "new tag remains cached");

        if(WAYS == 1) begin
            evicted_tag = tags[0];
        end else begin
            evicted_tag = tags[1];
        end

        req_addr = make_addr(evicted_tag, set_value);
        check_read(req_addr, 1'b0, "previous LRU tag was evicted");
    endtask

    task automatic check_output_backpressure();
        addr_t req_addr;
        logic  hit_rec;
        data_t data_rec;
        logic  hit_hold;
        data_t data_hold;
        int unsigned req_cnt_before;

        $display("\n[%0t] CHECK: output backpressure holds response stable", $time());
        apply_reset();
        req_addr = make_addr(test_tag(300), test_set(0));

        check_read(req_addr, 1'b0, "prefill for backpressure hit");

        @(negedge cache_vif_h.clk);
        cache_vif_h.m_ready <= 1'b0;
        req_cnt_before = ext_mem_req_cnt;

        send_read_request(req_addr);
        wait_for_response(hit_rec, data_rec, RESPONSE_TIMEOUT, 1'b0);

        if(hit_rec !== 1'b1) begin
            report_error("Backpressure request must hit in cache");
        end
        if(data_rec !== ext_mem_data_for_addr(req_addr)) begin
            report_error("Backpressure response has wrong data");
        end

        hit_hold  = hit_rec;
        data_hold = data_rec;

        repeat(3) begin
            @(posedge cache_vif_h.clk);
            @(negedge cache_vif_h.clk);
            if(cache_vif_h.m_valid !== 1'b1) begin
                report_error("m_valid_o dropped while m_ready_i is low");
            end
            if(cache_vif_h.hit !== hit_hold || cache_vif_h.data !== data_hold) begin
                report_error("Response changed while m_ready_i is low");
            end
            if(cache_vif_h.s_ready !== 1'b0) begin
                report_error("s_ready_o is high while output response is backpressured");
            end
        end

        @(negedge cache_vif_h.clk);
        cache_vif_h.m_ready <= 1'b1;
        @(posedge cache_vif_h.clk);
        @(negedge cache_vif_h.clk);

        if(cache_vif_h.m_valid !== 1'b0) begin
            report_error("m_valid_o did not clear after m_ready_i became high");
        end
        if((ext_mem_req_cnt - req_cnt_before) != 0) begin
            report_error("Backpressured hit must not request external memory");
        end

        wait_for_s_ready(RESPONSE_TIMEOUT);
    endtask

    task automatic check_pipeline_throughput();
        addr_t burst_addrs [BURST_LEN];
        logic  got_hit;
        data_t got_data;

        $display("\n[%0t] CHECK: pipeline throughput (back-to-back hits, BURST_LEN=%0d)",
            $time(), BURST_LEN);
        apply_reset();

        // Build addresses: set index cycles (i % SETS) so adjacent requests
        // target different sets → no s0_same_set_hazard when SETS > 1.
        // Each address has a UNIQUE tag to avoid collisions between iterations.
        // set cycles as (i % SETS): adjacent requests go to different sets (SETS > 1).
        for (int i = 0; i < BURST_LEN; i++)
            burst_addrs[i] = make_addr(test_tag(400 + i), test_set(i % SETS));

        // Phase 1: sequential pre-fill so every address is in cache
        for (int i = 0; i < BURST_LEN; i++)
            check_read(burst_addrs[i], 1'b0, $sformatf("throughput prefill [%0d]", i));

        // Phase 2: burst send — keep s_valid=1, change addr each accepted cycle.
        // This puts BURST_LEN requests into the pipeline without waiting for responses.
        @(negedge cache_vif_h.clk);
        for (int i = 0; i < BURST_LEN; i++) begin
            cache_vif_h.addr    <= burst_addrs[i];
            cache_vif_h.s_valid <= 1'b1;
            // Wait at negedge until s_ready (combinatorial — already settled here)
            while (cache_vif_h.s_ready !== 1'b1)
                @(negedge cache_vif_h.clk);
            @(posedge cache_vif_h.clk);         // handshake posedge
            if (i < BURST_LEN - 1)
                @(negedge cache_vif_h.clk);     // align for next address
        end
        @(negedge cache_vif_h.clk);
        cache_vif_h.s_valid <= 1'b0;

        // Phase 3: collect all BURST_LEN responses.
        //
        // First response: arrived after 3-cycle hit latency; wait normally.
        // After wait_for_response consumes it (at the consume posedge), the
        // pipeline loads the next result into S3 in the same posedge.
        // All subsequent responses are read at the following negedge.
        //
        // Expected timing for SETS > 1 (no same-set stalls):
        //   gap between consecutive m_valid pulses = 1 cycle exactly.

        wait_for_response(got_hit, got_data, RESPONSE_TIMEOUT, 1'b1);
        if (got_hit !== 1'b1)
            report_error("Throughput [0]: expected hit");
        if (got_data !== ext_mem_data_for_addr(burst_addrs[0]))
            report_error("Throughput [0]: wrong data");

        for (int i = 1; i < BURST_LEN; i++) begin
            // The consume posedge of the previous iteration loaded the next result
            // into S3 simultaneously. It is valid at this negedge.
            @(negedge cache_vif_h.clk);

            if (SETS > 1 && cache_vif_h.m_valid !== 1'b1)
                report_error($sformatf(
                    "Throughput [%0d]: pipeline gap — m_valid=0 between consecutive hits", i));

            if (cache_vif_h.m_valid === 1'b1) begin
                got_hit  = cache_vif_h.hit;
                got_data = cache_vif_h.data;
                if (got_hit !== 1'b1)
                    report_error($sformatf("Throughput [%0d]: expected hit", i));
                if (got_data !== ext_mem_data_for_addr(burst_addrs[i]))
                    report_error($sformatf("Throughput [%0d]: wrong data", i));
                @(posedge cache_vif_h.clk);     // consume; next result loads into S3
            end else begin
                // SETS = 1: same-set hazard inserts a stall cycle. Just wait.
                wait_for_response(got_hit, got_data, RESPONSE_TIMEOUT, 1'b1);
                if (got_hit !== 1'b1)
                    report_error($sformatf("Throughput [%0d]: expected hit (SETS=1)", i));
                if (got_data !== ext_mem_data_for_addr(burst_addrs[i]))
                    report_error($sformatf("Throughput [%0d]: wrong data (SETS=1)", i));
            end
        end
    endtask

    task automatic ext_mem_model_proc();
        addr_t pending_addr;

        forever begin
            @(posedge cache_vif_h.clk);
            cache_vif_h.ext_mem_ack <= 1'b0;

            if(cache_vif_h.rstn && cache_vif_h.ext_mem_req) begin
                pending_addr = cache_vif_h.ext_mem_addr;

                for(int wait_cycle = 0; wait_cycle < ext_mem_delay; wait_cycle++) begin
                    @(posedge cache_vif_h.clk);
                    cache_vif_h.ext_mem_ack <= 1'b0;
                end

                cache_vif_h.ext_mem_data <= ext_mem_data_for_addr(pending_addr);
                cache_vif_h.ext_mem_ack  <= 1'b1;

                @(posedge cache_vif_h.clk);
                cache_vif_h.ext_mem_ack <= 1'b0;
            end
        end
    endtask

    always @(posedge cache_if_h.clk) begin : ext_mem_req_monitor
        if(!cache_if_h.rstn) begin
            ext_mem_req_prev <= 1'b0;
        end else begin
            if(cache_if_h.ext_mem_req) begin
                ext_mem_req_cnt++;
                if(ext_mem_req_prev) begin
                    report_error("ext_mem_req_o is wider than one cycle");
                end
            end
            ext_mem_req_prev <= cache_if_h.ext_mem_req;
        end
    end

    initial begin : main_tb_proc
        cache_vif_h = cache_if_h;

        rstn                     = 1'b0;
        cache_vif_h.s_valid      = 1'b0;
        cache_vif_h.addr         = '0;
        cache_vif_h.m_ready      = 1'b1;
        cache_vif_h.ext_mem_ack  = 1'b0;
        cache_vif_h.ext_mem_data = '0;

        fork
            ext_mem_model_proc();
        join_none

        check_first_miss_then_hit();
        check_delayed_miss_stall();
        check_invalid_first_replacement();
        check_lru_replacement();
        check_output_backpressure();
        check_pipeline_throughput();

        repeat(10) @(posedge cache_vif_h.clk);

        if(error_cnt) begin
            $display("\n\t\tTEST FAILED! (error counter = %0d)\n", error_cnt);
        end else begin
            $display("\n\t\tTEST PASSED!\n");
        end
        $finish();
    end

    initial begin : clk_gen_proc
        clk = 1'b0;
        forever begin
            #(CLK_PERIOD / 2.0) clk = ~clk;
        end
    end

endmodule : tb_cache
