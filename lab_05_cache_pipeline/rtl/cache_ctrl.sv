module cache_ctrl #(
    parameter int SETS       = 1,
    parameter int WAYS       = 1,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 30,

    localparam int SET_FIELD_WIDTH   = (SETS != 1) ? $clog2(SETS) : 1,
    localparam int TAG_FIELD_WIDTH   = (SETS != 1) ? ADDR_WIDTH - SET_FIELD_WIDTH : ADDR_WIDTH,
    localparam int WAY_IDX_WIDTH     = (WAYS != 1) ? $clog2(WAYS) : 1,
    localparam int LRU_CNT_WIDTH     = (WAYS != 1) ? $clog2(WAYS) : 1,
    localparam int CACHE_CELL_WIDTH  = WAYS * (TAG_FIELD_WIDTH + DATA_WIDTH),
    localparam int STATE_WAY_WIDTH   = 1 + LRU_CNT_WIDTH,
    localparam int STATE_CELL_WIDTH  = WAYS * STATE_WAY_WIDTH
) (
    input  logic                            clk_i,
    input  logic                            rstn_i,

    // Slave request
    input  logic                            s_valid_i,
    output logic                            s_ready_o,

    // Master response
    output logic                            m_valid_o,
    input  logic                            m_ready_i,

    input  logic [ADDR_WIDTH - 1 : 0]       addr_i,
    output logic [DATA_WIDTH - 1 : 0]       data_o,
    output logic                            hit_valid_o,
    output logic                            hit_o,

    // Cache SRAM (single-port)
    output logic                            cache_sram_ce_o,
    output logic                            cache_sram_we_o,
    output logic [ADDR_WIDTH - 1 : 0]       cache_sram_addr_o,
    output logic [CACHE_CELL_WIDTH - 1 : 0] cache_sram_wdata_o,
    input  logic [CACHE_CELL_WIDTH - 1 : 0] cache_sram_rdata_i,

    // State SRAM Port A (read)
    output logic                            state_sram_a_ce_o,
    output logic [ADDR_WIDTH - 1 : 0]       state_sram_a_addr_o,
    input  logic [STATE_CELL_WIDTH - 1 : 0] state_sram_a_rdata_i,

    // State SRAM Port B (write)
    output logic                            state_sram_b_ce_o,
    output logic                            state_sram_b_we_o,
    output logic [ADDR_WIDTH - 1 : 0]       state_sram_b_addr_o,
    output logic [STATE_CELL_WIDTH - 1 : 0] state_sram_b_wdata_o,

    output logic                            ext_mem_req_o,
    output logic [ADDR_WIDTH - 1 : 0]       ext_mem_addr_o,
    input  logic [DATA_WIDTH - 1 : 0]       ext_mem_data_i,
    input  logic                            ext_mem_ack_i
);

    // ------------------------------------------------------------------------
    // -- Local parameters
    // ------------------------------------------------------------------------

    localparam logic [LRU_CNT_WIDTH - 1 : 0] LRU_MAX_VALUE = WAYS - 1;

    // ------------------------------------------------------------------------
    // -- Quality checks
    // ------------------------------------------------------------------------

    sets_param_range : assert property(@(posedge clk_i) SETS >= 1 && SET_FIELD_WIDTH <= ADDR_WIDTH)
    else $error("Wrong 'SETS' parameter value (%0d). It must be in range [1 : %0d]", SETS, 2 ** ADDR_WIDTH);

    ways_param_range : assert property(@(posedge clk_i) WAYS >= 1)
    else $error("Wrong 'WAYS' parameter value (%0d). It must be greater than 0.", WAYS);

    set_tag_width_sum : assert property(
        @(posedge clk_i) disable iff(SETS == 1)
        SET_FIELD_WIDTH + TAG_FIELD_WIDTH == ADDR_WIDTH)
    else $error("The sum of 'tag' and 'set' widths (%0d) is not equal to 'ADDR_WIDTH' parameter value (%0d).",
        SET_FIELD_WIDTH + TAG_FIELD_WIDTH, ADDR_WIDTH);

    set_tag_width_sum_sets_1 : assert property(
        @(posedge clk_i) disable iff(SETS != 1)
        TAG_FIELD_WIDTH == ADDR_WIDTH && SET_FIELD_WIDTH == 1)
    else $error("The 'tag' width (%0d) is not equal to 'ADDR_WIDTH' parameter value (%0d).",
        TAG_FIELD_WIDTH, ADDR_WIDTH);

    single_hit : assert property(
        @(posedge clk_i) disable iff(!rstn_i || !s1_valid)
        $onehot0(ways_hits))
    else $error("Unexpected value of 'ways_hits' ('b%b). Only single bit can be high.", ways_hits);

    addr_undefined : assert property(
        @(posedge clk_i) disable iff(!rstn_i)
        (s0_valid && s0_advancing) |-> !$isunknown(addr_i))
    else $error("The accepted 'addr_i' bus contains undefined value(-s) ('h%x).", addr_i);

    ext_mem_req_pulse : assert property(
        @(posedge clk_i) disable iff(!rstn_i)
        ext_mem_req_o |=> !ext_mem_req_o)
    else $error("'ext_mem_req_o' must be a one-cycle pulse.");

    // ------------------------------------------------------------------------
    // -- Type definitions
    // ------------------------------------------------------------------------

    typedef struct packed {
        logic [TAG_FIELD_WIDTH - 1 : 0] tag;
        logic [DATA_WIDTH      - 1 : 0] data;
    } cache_way_t;

    typedef struct packed {
        logic                           valid;
        logic [LRU_CNT_WIDTH   - 1 : 0] lru_age;
    } state_way_t;

    // ------------------------------------------------------------------------
    // -- Helper functions
    // ------------------------------------------------------------------------

    function automatic logic [LRU_CNT_WIDTH - 1 : 0] inc_lru_age(
        input logic [LRU_CNT_WIDTH - 1 : 0] age
    );
        if (age >= LRU_MAX_VALUE)
            inc_lru_age = LRU_MAX_VALUE;
        else
            inc_lru_age = age + 1'b1;
    endfunction

    function automatic logic [ADDR_WIDTH - 1 : 0] set_to_addr(
        input logic [SET_FIELD_WIDTH - 1 : 0] set_value
    );
        set_to_addr = '0;
        set_to_addr[SET_FIELD_WIDTH - 1 : 0] = set_value;
    endfunction

    // ------------------------------------------------------------------------
    // -- Init registers
    // ------------------------------------------------------------------------

    logic [SET_FIELD_WIDTH - 1 : 0] init_set_ff;
    logic                           init_active;

    // ------------------------------------------------------------------------
    // -- Stage 0 (CACHE_REQ) registers
    // ------------------------------------------------------------------------

    logic                            s0_valid;
    logic [ADDR_WIDTH      - 1 : 0]  s0_addr;
    logic [TAG_FIELD_WIDTH - 1 : 0]  s0_tag;
    logic [SET_FIELD_WIDTH - 1 : 0]  s0_set;

    // ------------------------------------------------------------------------
    // -- Stage 1 (CHECK_TAG) registers
    // ------------------------------------------------------------------------

    logic                            s1_valid;
    logic [ADDR_WIDTH      - 1 : 0]  s1_addr;
    logic [TAG_FIELD_WIDTH - 1 : 0]  s1_tag;
    logic [SET_FIELD_WIDTH - 1 : 0]  s1_set;

    // ------------------------------------------------------------------------
    // -- Stage 2 (REFILL) registers
    // ------------------------------------------------------------------------

    logic                            s2_valid;
    logic                            s2_is_miss;
    logic [ADDR_WIDTH      - 1 : 0]  s2_addr;
    logic [TAG_FIELD_WIDTH - 1 : 0]  s2_tag;
    logic [WAY_IDX_WIDTH   - 1 : 0]  s2_victim_way;
    logic [DATA_WIDTH      - 1 : 0]  s2_hit_data;
    logic                            s2_hit_flag;
    state_way_t [WAYS - 1 : 0]       s2_new_state_cell;
    cache_way_t [WAYS - 1 : 0]       s2_cache_snap;  // cache cell snapshot for REFILL write

    // ------------------------------------------------------------------------
    // -- Stage 3 (OUTPUT) registers
    // ------------------------------------------------------------------------

    logic                            s3_valid;
    logic [DATA_WIDTH - 1 : 0]       s3_data;
    logic                            s3_hit;

    // ------------------------------------------------------------------------
    // -- S1 combinational wires
    // ------------------------------------------------------------------------

    cache_way_t [WAYS - 1 : 0]       s1_cache_cell;
    state_way_t [WAYS - 1 : 0]       s1_state_cell;

    logic [WAYS - 1 : 0]             ways_hits;
    logic                            cache_hit;
    logic [WAY_IDX_WIDTH - 1 : 0]    hit_way;
    logic [DATA_WIDTH    - 1 : 0]    hit_data;
    logic [WAY_IDX_WIDTH - 1 : 0]    victim_way;
    logic                            s1_is_miss;

    state_way_t [WAYS - 1 : 0]       new_state_cell_hit;
    state_way_t [WAYS - 1 : 0]       new_state_cell_miss;
    cache_way_t [WAYS - 1 : 0]       cache_refill_wdata;

    // ------------------------------------------------------------------------
    // -- Stall and advance signals
    // ------------------------------------------------------------------------

    logic s3_stall;
    logic s2_stall;
    logic s1_stall;
    logic s0_hit_line_hazard;     // S1 hit writes state[set]; S0 reads same line
    logic s0_miss_set_hazard;     // in-flight miss owns set; hold follower in S0
    logic s0_refill_struct_hazard;// refill monopolizes single cache-SRAM port
    logic s0_stall;
    logic s0_advancing;
    logic s1_advancing;
    logic s2_advancing;

    // Set index derived from s2_addr for the S2-vs-S0 hazard check
    logic [SET_FIELD_WIDTH - 1 : 0] s2_set;

    // ------------------------------------------------------------------------
    // -- SRAM data views
    // ------------------------------------------------------------------------

    assign s1_cache_cell = cache_sram_rdata_i;
    assign s1_state_cell = state_sram_a_rdata_i;
    assign s2_set        = (SETS != 1) ? s2_addr[SET_FIELD_WIDTH - 1 : 0] : '0;

    // ------------------------------------------------------------------------
    // -- Stall / advance logic
    // ------------------------------------------------------------------------

    always_comb begin : stall_comb_logic
        s3_stall = s3_valid && !m_ready_i;
        s2_stall = s3_stall || (s2_valid && s2_is_miss && !ext_mem_ack_i);
        s1_stall = s2_stall;

        // Hazard 1 (same-line hit). On a hit S1 writes state SRAM Port B (LRU) for
        // its set. With read-first Port A, S0 reading that location in the same cycle
        // would consume a stale snapshot. Narrowed to the full line (tag+set): only a
        // request to the same line is held; different-tag/same-set requests proceed.
        // (Trade-off: their LRU ages may be computed from a one-cycle-stale base.)
        s0_hit_line_hazard = s0_valid && s1_valid && !s1_is_miss && !s2_stall &&
                             (s0_addr == s1_addr);

        // Hazard 2 (in-flight miss owns the set). A miss being resolved (detected in
        // S1, or waiting/refilling in S2) will rewrite state[set] from a snapshot
        // taken before the refill. Any follower to the SAME SET must wait in S0 so
        // that, once the refill is visible, it re-reads fresh cache + state:
        //   * same line -> now a hit (no duplicate allocation, no 2nd ext_mem_req);
        //   * same set  -> sees post-refill valid/LRU (no state corruption).
        // Set granularity is required (state is per-set) and costs no throughput: a
        // miss blocks the pipe regardless of whether the follower waits in S0 or S1.
        s0_miss_set_hazard = s0_valid &&
                             ((s1_valid && s1_is_miss && (s0_set == s1_set)) ||
                              (s2_valid && s2_is_miss && (s0_set == s2_set)));

        // Hazard 3 (structural). On the refill (ack) cycle the single-port cache SRAM
        // is busy with the refill write, so S0 cannot perform its read this cycle —
        // regardless of set. Hold S0 for that one cycle; it reads next cycle.
        s0_refill_struct_hazard = s0_valid && s2_valid && s2_is_miss && ext_mem_ack_i;

        s0_stall     = init_active || s1_stall ||
                       s0_hit_line_hazard || s0_miss_set_hazard || s0_refill_struct_hazard;
        s0_advancing = s0_valid && !s0_stall;
        s1_advancing = s1_valid && !s1_stall;
        s2_advancing = s2_valid && !s3_stall && (!s2_is_miss || ext_mem_ack_i);

        s_ready_o = !s0_stall && (!s0_valid || s0_advancing);
    end

    // ------------------------------------------------------------------------
    // -- S1: tag compare, victim select, LRU compute
    // ------------------------------------------------------------------------

    always_comb begin : hit_detect_comb_logic
        ways_hits = '0;
        hit_way   = '0;
        hit_data  = '0;

        if (s1_valid) begin
            for (int way = 0; way < WAYS; way++) begin
                ways_hits[way] = s1_state_cell[way].valid &&
                                 (s1_cache_cell[way].tag == s1_tag);
                if (ways_hits[way]) begin
                    hit_way  = WAY_IDX_WIDTH'(way);
                    hit_data = s1_cache_cell[way].data;
                end
            end
        end
    end

    assign cache_hit  = |ways_hits;
    assign s1_is_miss = s1_valid && !cache_hit;

    always_comb begin : victim_select_comb_logic
        logic                          invalid_found;
        logic [LRU_CNT_WIDTH - 1 : 0]  max_age;

        victim_way    = '0;
        invalid_found = 1'b0;
        max_age       = '0;

        if (s1_valid) begin
            for (int way = 0; way < WAYS; way++) begin
                if (!s1_state_cell[way].valid && !invalid_found) begin
                    victim_way    = WAY_IDX_WIDTH'(way);
                    invalid_found = 1'b1;
                end
            end
            if (!invalid_found) begin
                max_age    = s1_state_cell[0].lru_age;
                victim_way = '0;
                for (int way = 1; way < WAYS; way++) begin
                    if (s1_state_cell[way].lru_age > max_age) begin
                        max_age    = s1_state_cell[way].lru_age;
                        victim_way = WAY_IDX_WIDTH'(way);
                    end
                end
            end
        end
    end

    always_comb begin : lru_compute_comb_logic
        new_state_cell_hit  = s1_state_cell;
        new_state_cell_miss = s1_state_cell;

        for (int way = 0; way < WAYS; way++) begin
            // Hit update
            if (WAY_IDX_WIDTH'(way) == hit_way) begin
                new_state_cell_hit[way].valid   = 1'b1;
                new_state_cell_hit[way].lru_age = '0;
            end else if (s1_state_cell[way].valid &&
                         s1_state_cell[way].lru_age < s1_state_cell[hit_way].lru_age) begin
                new_state_cell_hit[way].lru_age = inc_lru_age(s1_state_cell[way].lru_age);
            end

            // Miss update
            if (WAY_IDX_WIDTH'(way) == victim_way) begin
                new_state_cell_miss[way].valid   = 1'b1;
                new_state_cell_miss[way].lru_age = '0;
            end else if (s1_state_cell[way].valid) begin
                new_state_cell_miss[way].lru_age = inc_lru_age(s1_state_cell[way].lru_age);
                new_state_cell_miss[way].valid    = 1'b1;
            end else begin
                new_state_cell_miss[way].valid   = 1'b0;
                new_state_cell_miss[way].lru_age = '0;
            end
        end
    end

    // Refill write data: snapshot of cache cell with victim way overwritten
    always_comb begin : cache_refill_wdata_comb_logic
        cache_refill_wdata                     = s2_cache_snap;
        cache_refill_wdata[s2_victim_way].tag  = s2_tag;
        cache_refill_wdata[s2_victim_way].data = ext_mem_data_i;
    end

    // ------------------------------------------------------------------------
    // -- Cache SRAM control (single always_comb, no multiple drivers)
    // ------------------------------------------------------------------------

    always_comb begin : cache_sram_ctrl_comb_logic
        // Default: S0 read
        cache_sram_ce_o    = s0_valid && s0_advancing;
        cache_sram_we_o    = 1'b0;
        cache_sram_addr_o  = s0_addr;
        cache_sram_wdata_o = '0;

        // REFILL write overrides (miss-in-flight stalls S0, so no conflict)
        if (s2_valid && s2_is_miss && ext_mem_ack_i) begin
            cache_sram_ce_o    = 1'b1;
            cache_sram_we_o    = 1'b1;
            cache_sram_addr_o  = s2_addr;
            cache_sram_wdata_o = cache_refill_wdata;
        end
    end

    // ------------------------------------------------------------------------
    // -- State SRAM Port A control (read)
    // ------------------------------------------------------------------------

    always_comb begin : state_sram_a_ctrl_comb_logic
        state_sram_a_ce_o   = s0_valid && s0_advancing;
        state_sram_a_addr_o = s0_addr;
    end

    // ------------------------------------------------------------------------
    // -- State SRAM Port B control (write)
    // ------------------------------------------------------------------------

    always_comb begin : state_sram_b_ctrl_comb_logic
        state_sram_b_ce_o    = 1'b0;
        state_sram_b_we_o    = 1'b0;
        state_sram_b_addr_o  = '0;
        state_sram_b_wdata_o = '0;

        if (init_active) begin
            // Priority 1: zero-fill all state SRAM entries after reset
            state_sram_b_ce_o    = 1'b1;
            state_sram_b_we_o    = 1'b1;
            state_sram_b_addr_o  = set_to_addr(init_set_ff);
            state_sram_b_wdata_o = '0;
        end else if (s2_valid && s2_is_miss && ext_mem_ack_i) begin
            // Priority 2: REFILL miss — write pre-computed LRU state
            // (S1 was stalled during miss wait, so S1 cannot simultaneously write Port B)
            state_sram_b_ce_o    = 1'b1;
            state_sram_b_we_o    = 1'b1;
            state_sram_b_addr_o  = s2_addr;
            state_sram_b_wdata_o = s2_new_state_cell;
        end else if (s1_valid && !s1_is_miss && s1_advancing) begin
            // Priority 3: CHECK_TAG hit — write LRU update immediately
            state_sram_b_ce_o    = 1'b1;
            state_sram_b_we_o    = 1'b1;
            state_sram_b_addr_o  = s1_addr;
            state_sram_b_wdata_o = new_state_cell_hit;
        end
    end

    // ------------------------------------------------------------------------
    // -- External memory signals
    // ------------------------------------------------------------------------

    always_comb begin : ext_mem_comb_logic
        // ext_mem_req fires exactly when S1 detects a miss and is advancing to S2
        ext_mem_req_o  = s1_valid && s1_is_miss && s1_advancing;
        // Hold miss address: use S2 while waiting; S1 addr otherwise
        ext_mem_addr_o = (s2_valid && s2_is_miss) ? s2_addr : s1_addr;
    end

    // ------------------------------------------------------------------------
    // -- Output assignments
    // ------------------------------------------------------------------------

    assign m_valid_o   = s3_valid;
    assign hit_valid_o = s3_valid;
    assign data_o      = s3_data;
    assign hit_o       = s3_hit;

    // ------------------------------------------------------------------------
    // -- Sequential logic
    // ------------------------------------------------------------------------

    always_ff @(posedge clk_i) begin : init_seq_logic
        if (!rstn_i) begin
            init_set_ff <= '0;
            init_active <= 1'b1;
        end else if (init_active) begin
            if (init_set_ff == SET_FIELD_WIDTH'(SETS - 1))
                init_active <= 1'b0;
            else
                init_set_ff <= init_set_ff + 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin : s0_seq_logic
        if (!rstn_i) begin
            s0_valid <= 1'b0;
            s0_addr  <= '0;
            s0_tag   <= '0;
            s0_set   <= '0;
        end else begin
            if (s_valid_i && s_ready_o) begin
                s0_valid <= 1'b1;
                s0_addr  <= addr_i;
                if (SETS == 1) begin
                    s0_tag <= addr_i;
                    s0_set <= '0;
                end else begin
                    {s0_tag, s0_set} <= addr_i;
                end
            end else if (s0_advancing) begin
                // Moved to S1, no new request
                s0_valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i) begin : s1_seq_logic
        if (!rstn_i) begin
            s1_valid <= 1'b0;
            s1_addr  <= '0;
            s1_tag   <= '0;
            s1_set   <= '0;
        end else begin
            if (s0_advancing) begin
                s1_valid <= s0_valid;
                s1_addr  <= s0_addr;
                s1_tag   <= s0_tag;
                s1_set   <= s0_set;
            end else if (s1_advancing) begin
                s1_valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i) begin : s2_seq_logic
        if (!rstn_i) begin
            s2_valid          <= 1'b0;
            s2_is_miss        <= 1'b0;
            s2_addr           <= '0;
            s2_tag            <= '0;
            s2_victim_way     <= '0;
            s2_hit_data       <= '0;
            s2_hit_flag       <= 1'b0;
            s2_new_state_cell <= '0;
            s2_cache_snap     <= '0;
        end else begin
            if (s1_advancing) begin
                s2_valid          <= s1_valid;
                s2_is_miss        <= s1_is_miss;
                s2_addr           <= s1_addr;
                s2_tag            <= s1_tag;
                s2_victim_way     <= victim_way;
                s2_hit_data       <= hit_data;
                s2_hit_flag       <= cache_hit;
                s2_new_state_cell <= new_state_cell_miss;
                s2_cache_snap     <= s1_cache_cell;
            end else if (s2_advancing) begin
                s2_valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i) begin : s3_seq_logic
        if (!rstn_i) begin
            s3_valid <= 1'b0;
            s3_data  <= '0;
            s3_hit   <= 1'b0;
        end else begin
            if (s2_advancing) begin
                s3_valid <= s2_valid;
                s3_data  <= s2_hit_flag ? s2_hit_data : ext_mem_data_i;
                s3_hit   <= s2_hit_flag;
            end else if (!s3_stall) begin
                s3_valid <= 1'b0;
            end
        end
    end

endmodule : cache_ctrl
