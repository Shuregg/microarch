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

    // Slave request signals
    input  logic                            s_valid_i,
    output logic                            s_ready_o,

    // Master response signals
    output logic                            m_valid_o,
    input  logic                            m_ready_i,

    input  logic [ADDR_WIDTH - 1 : 0]       addr_i,
    output logic [DATA_WIDTH - 1 : 0]       data_o,
    output logic                            hit_valid_o,
    output logic                            hit_o,

    // Cache SRAM: one set contains tag/data for all ways
    output logic                            cache_sram_ce_o,
    output logic                            cache_sram_we_o,
    output logic [ADDR_WIDTH - 1 : 0]       cache_sram_addr_o,
    output logic [CACHE_CELL_WIDTH - 1 : 0] cache_sram_wdata_o,
    input  logic [CACHE_CELL_WIDTH - 1 : 0] cache_sram_rdata_i,

    // State SRAM: one set contains valid/LRU state for all ways
    output logic                            state_sram_ce_o,
    output logic                            state_sram_we_o,
    output logic [ADDR_WIDTH - 1 : 0]       state_sram_addr_o,
    output logic [STATE_CELL_WIDTH - 1 : 0] state_sram_wdata_o,
    input  logic [STATE_CELL_WIDTH - 1 : 0] state_sram_rdata_i,

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
        @(posedge clk_i) disable iff(!rstn_i)
        $onehot0(ways_hits))
    else $error("Unexpected value of 'ways_hits' ('b%b). Only single bit can be high.", ways_hits);

    addr_undefined : assert property(
        @(posedge clk_i) disable iff(!rstn_i)
        (s_valid_i && s_ready_o) |-> !$isunknown(addr_i))
    else $error("The accepted 'addr_i' bus contains undefined value(-s) ('h%x).", addr_i);

    ext_mem_req_pulse : assert property(
        @(posedge clk_i) disable iff(!rstn_i)
        ext_mem_req_o |=> !ext_mem_req_o)
    else $error("'ext_mem_req_o' must be a one-cycle pulse.");

    // ------------------------------------------------------------------------
    // -- Type definitions
    // ------------------------------------------------------------------------

    typedef enum logic [2 : 0] {
        ST_INIT,
        ST_READY,
        ST_CHECK_TAG,
        ST_MEM_WAIT,
        ST_OUTPUT
    } state_t;

    typedef struct packed {
        logic [TAG_FIELD_WIDTH - 1 : 0] tag;
        logic [DATA_WIDTH      - 1 : 0] data;
    } cache_way_t;

    typedef struct packed {
        logic                           valid;
        logic [LRU_CNT_WIDTH   - 1 : 0] lru_age;
    } state_way_t;

    // ------------------------------------------------------------------------
    // -- Internal registers and wires
    // ------------------------------------------------------------------------

    state_t state_ff;
    state_t state_next;

    cache_way_t [WAYS - 1 : 0] cache_cell_of_curr_set;
    cache_way_t [WAYS - 1 : 0] cache_cell_write;
    state_way_t [WAYS - 1 : 0] state_cell_of_curr_set;
    state_way_t [WAYS - 1 : 0] state_cell_write;

    logic [ADDR_WIDTH     - 1 : 0] req_addr_ff;
    logic [TAG_FIELD_WIDTH - 1 : 0] req_tag_ff;
    logic [SET_FIELD_WIDTH - 1 : 0] req_set_ff;
    logic [WAY_IDX_WIDTH   - 1 : 0] victim_way_ff;
    logic [ADDR_WIDTH      - 1 : 0] ext_mem_addr_ff;

    logic [SET_FIELD_WIDTH - 1 : 0] init_set_ff;
    logic [SET_FIELD_WIDTH - 1 : 0] init_set_next;

    logic [TAG_FIELD_WIDTH - 1 : 0] addr_tag;
    logic [SET_FIELD_WIDTH - 1 : 0] addr_set;

    logic [WAYS - 1 : 0]            ways_hits;
    logic                           cache_hit;
    logic [WAY_IDX_WIDTH - 1 : 0]   hit_way;
    logic [DATA_WIDTH - 1 : 0]      hit_data;
    logic [WAY_IDX_WIDTH - 1 : 0]   victim_way;

    logic [DATA_WIDTH - 1 : 0]      data_ff;
    logic                           hit_ff;
    logic                           m_valid_ff;

    // ------------------------------------------------------------------------
    // -- Helper functions
    // ------------------------------------------------------------------------

    function automatic logic [LRU_CNT_WIDTH - 1 : 0] inc_lru_age(
        input logic [LRU_CNT_WIDTH - 1 : 0] age
    );
        if(age >= LRU_MAX_VALUE) begin
            inc_lru_age = LRU_MAX_VALUE;
        end else begin
            inc_lru_age = age + 1'b1;
        end
    endfunction

    function automatic logic [ADDR_WIDTH - 1 : 0] set_to_addr(
        input logic [SET_FIELD_WIDTH - 1 : 0] set_value
    );
        set_to_addr = '0;
        set_to_addr[SET_FIELD_WIDTH - 1 : 0] = set_value;
    endfunction

    // ------------------------------------------------------------------------
    // -- Combinational logic
    // ------------------------------------------------------------------------

    assign cache_cell_of_curr_set = cache_sram_rdata_i;
    assign state_cell_of_curr_set = state_sram_rdata_i;

    assign m_valid_o    = m_valid_ff;
    assign hit_valid_o  = m_valid_ff;
    assign data_o       = data_ff;
    assign hit_o        = hit_ff;

    always_comb begin : addr_decode_comb_logic
        if(SETS == 1) begin
            addr_tag = addr_i;
            addr_set = '0;
        end else begin
            {addr_tag, addr_set} = addr_i;
        end
    end

    always_comb begin : hit_detect_comb_logic
        ways_hits = '0;
        hit_way   = '0;
        hit_data  = '0;

        if(state_ff == ST_CHECK_TAG) begin
            for(int way = 0; way < WAYS; way++) begin
                ways_hits[way] = state_cell_of_curr_set[way].valid &&
                    (cache_cell_of_curr_set[way].tag == req_tag_ff);
                if(ways_hits[way]) begin
                    hit_way  = WAY_IDX_WIDTH'(way);
                    hit_data = cache_cell_of_curr_set[way].data;
                end
            end
        end
    end

    assign cache_hit = |ways_hits;

    always_comb begin : victim_select_comb_logic
        logic invalid_found;
        logic [LRU_CNT_WIDTH - 1 : 0] max_age;

        victim_way    = '0;
        invalid_found = 1'b0;
        max_age       = '0;

        for(int way = 0; way < WAYS; way++) begin
            if(!state_cell_of_curr_set[way].valid && !invalid_found) begin
                victim_way    = WAY_IDX_WIDTH'(way);
                invalid_found = 1'b1;
            end
        end

        if(!invalid_found) begin
            victim_way = '0;
            max_age    = state_cell_of_curr_set[0].lru_age;
            for(int way = 1; way < WAYS; way++) begin
                if(state_cell_of_curr_set[way].lru_age > max_age) begin
                    max_age    = state_cell_of_curr_set[way].lru_age;
                    victim_way = WAY_IDX_WIDTH'(way);
                end
            end
        end
    end

    always_comb begin : lru_update_comb_logic
        state_cell_write = state_cell_of_curr_set;

        if(state_ff == ST_CHECK_TAG && cache_hit) begin
            for(int way = 0; way < WAYS; way++) begin
                if(WAY_IDX_WIDTH'(way) == hit_way) begin
                    state_cell_write[way].valid   = 1'b1;
                    state_cell_write[way].lru_age = '0;
                end else if(state_cell_of_curr_set[way].valid &&
                    (state_cell_of_curr_set[way].lru_age < state_cell_of_curr_set[hit_way].lru_age)) begin
                    state_cell_write[way].lru_age = inc_lru_age(state_cell_of_curr_set[way].lru_age);
                end
            end
        end else if(state_ff == ST_MEM_WAIT && ext_mem_ack_i) begin
            for(int way = 0; way < WAYS; way++) begin
                if(WAY_IDX_WIDTH'(way) == victim_way_ff) begin
                    state_cell_write[way].valid   = 1'b1;
                    state_cell_write[way].lru_age = '0;
                end else if(state_cell_of_curr_set[way].valid) begin
                    state_cell_write[way].lru_age = inc_lru_age(state_cell_of_curr_set[way].lru_age);
                end else begin
                    state_cell_write[way].valid   = 1'b0;
                    state_cell_write[way].lru_age = '0;
                end
            end
        end
    end

    always_comb begin : cache_write_comb_logic
        cache_cell_write = cache_cell_of_curr_set;

        if(state_ff == ST_MEM_WAIT && ext_mem_ack_i) begin
            cache_cell_write[victim_way_ff].tag  = req_tag_ff;
            cache_cell_write[victim_way_ff].data = ext_mem_data_i;
        end
    end

    always_comb begin : sram_control_comb_logic
        cache_sram_ce_o    = 1'b0;
        cache_sram_we_o    = 1'b0;
        cache_sram_addr_o  = '0;
        cache_sram_wdata_o = cache_cell_write;

        state_sram_ce_o    = 1'b0;
        state_sram_we_o    = 1'b0;
        state_sram_addr_o  = '0;
        state_sram_wdata_o = state_cell_write;

        ext_mem_req_o      = 1'b0;
        ext_mem_addr_o     = ext_mem_addr_ff;

        unique case(state_ff)
            ST_INIT: begin
                state_sram_ce_o    = 1'b1;
                state_sram_we_o    = 1'b1;
                state_sram_addr_o  = set_to_addr(init_set_ff);
                state_sram_wdata_o = '0;
            end

            ST_READY: begin
                if(s_valid_i) begin
                    cache_sram_ce_o   = 1'b1;
                    cache_sram_addr_o = addr_i;
                    state_sram_ce_o   = 1'b1;
                    state_sram_addr_o = addr_i;
                end
            end

            ST_CHECK_TAG: begin
                if(cache_hit) begin
                    state_sram_ce_o    = 1'b1;
                    state_sram_we_o    = 1'b1;
                    state_sram_addr_o  = req_addr_ff;
                    state_sram_wdata_o = state_cell_write;
                end else begin
                    ext_mem_req_o  = 1'b1;
                    ext_mem_addr_o = req_addr_ff;
                end
            end

            ST_MEM_WAIT: begin
                ext_mem_addr_o = ext_mem_addr_ff;
                if(ext_mem_ack_i) begin
                    cache_sram_ce_o    = 1'b1;
                    cache_sram_we_o    = 1'b1;
                    cache_sram_addr_o  = req_addr_ff;
                    cache_sram_wdata_o = cache_cell_write;

                    state_sram_ce_o    = 1'b1;
                    state_sram_we_o    = 1'b1;
                    state_sram_addr_o  = req_addr_ff;
                    state_sram_wdata_o = state_cell_write;
                end
            end

            default: begin
                // No SRAM operation.
            end
        endcase
    end

    always_comb begin : fsm_next_comb_logic
        state_next    = state_ff;
        init_set_next = init_set_ff;
        s_ready_o     = 1'b0;

        unique case(state_ff)
            ST_INIT: begin
                if(init_set_ff == SETS - 1) begin
                    state_next = ST_READY;
                end else begin
                    init_set_next = init_set_ff + 1'b1;
                end
            end

            ST_READY: begin
                s_ready_o = 1'b1;
                if(s_valid_i) begin
                    state_next = ST_CHECK_TAG;
                end
            end

            ST_CHECK_TAG: begin
                if(cache_hit) begin
                    state_next = ST_OUTPUT;
                end else begin
                    state_next = ST_MEM_WAIT;
                end
            end

            ST_MEM_WAIT: begin
                if(ext_mem_ack_i) begin
                    state_next = ST_OUTPUT;
                end
            end

            ST_OUTPUT: begin
                if(m_ready_i) begin
                    state_next = ST_READY;
                end
            end

            default: begin
                state_next = ST_INIT;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // -- Sequential logic
    // ------------------------------------------------------------------------

    always_ff @(posedge clk_i) begin : fsm_seq_logic
        if(!rstn_i) begin
            state_ff       <= ST_INIT;
            init_set_ff    <= '0;
            req_addr_ff    <= '0;
            req_tag_ff     <= '0;
            req_set_ff     <= '0;
            victim_way_ff  <= '0;
            ext_mem_addr_ff <= '0;
            data_ff        <= '0;
            hit_ff         <= 1'b0;
            m_valid_ff     <= 1'b0;
        end else begin
            state_ff    <= state_next;
            init_set_ff <= init_set_next;

            if(state_ff == ST_READY && s_valid_i && s_ready_o) begin
                req_addr_ff <= addr_i;
                req_tag_ff  <= addr_tag;
                req_set_ff  <= addr_set;
            end

            if(state_ff == ST_CHECK_TAG && !cache_hit) begin
                victim_way_ff   <= victim_way;
                ext_mem_addr_ff <= req_addr_ff;
            end

            if(state_ff == ST_CHECK_TAG && cache_hit) begin
                data_ff    <= hit_data;
                hit_ff     <= 1'b1;
                m_valid_ff <= 1'b1;
            end else if(state_ff == ST_MEM_WAIT && ext_mem_ack_i) begin
                data_ff    <= ext_mem_data_i;
                hit_ff     <= 1'b0;
                m_valid_ff <= 1'b1;
            end else if(state_ff == ST_OUTPUT && m_ready_i) begin
                m_valid_ff <= 1'b0;
            end
        end
    end

endmodule : cache_ctrl
