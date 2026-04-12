import cache_param_pkg::*;

module cache_ctrl #(
    SETS       = SETS,
    WAYS       = WAYS,
    DATA_WIDTH = DATA_WIDTH,
    ADDR_WIDTH = ADDR_WIDTH
) (
    // Clock & Reset
    input  logic                      clk_i,
    input  logic                      rstn_i,
    input  logic                      en_i,

    // Cache controller interface
    input  logic [ADDR_WIDTH - 1 : 0] addr_i,
    output logic [DATA_WIDTH - 1 : 0] data_o,
    output logic                      hit_valid_o,
    output logic                      hit_o,

    // Cache's SRAM interface
    output logic [ADDR_WIDTH - 1 : 0] sram_addr_o,
    output logic                      sram_we_o,
    output logic                      sram_ce_o,
    output logic [CELL_WIDTH - 1 : 0] sram_wdata_o,
    input  logic [CELL_WIDTH - 1 : 0] sram_rdata_i,

    // External memory access interface
    output logic                      ext_mem_req_o,
    output logic [ADDR_WIDTH - 1 : 0] ext_mem_addr_o,
    input  logic [DATA_WIDTH - 1 : 0] ext_mem_data_i,
    input  logic                      ext_mem_ack_i
);

    // ------------------------------------------------------------------------
    // -- Type definitions
    // ------------------------------------------------------------------------

    typedef struct packed {
        // logic [VALID_WIDTH - 1 : 0] valid;
        logic [TAG_WIDTH   - 1 : 0] tag;
        logic [DATA_WIDTH  - 1 : 0] data;
    } cache_sram_cell_t;

    typedef enum logic[3:0] {
        RESET,
        IDLE,
        SRAM_FIRST_READ,
        SRAM_READ,
        EXT_MEM_REQ,
        EXT_MEM_ACK,
        SRAM_REFILL
    } cache_state_e;

    // ------------------------------------------------------------------------
    // -- Internal registers and wires
    // ------------------------------------------------------------------------

    logic en_dly_ff;

    // Input address convertation signals & registers
    logic [TAG_WIDTH  - 1 : 0]                tag;
    logic [TAG_WIDTH  - 1 : 0]                tag_ff;
    logic [SET_WIDTH  - 1 : 0]                set;
    logic [SET_WIDTH  - 1 : 0]                set_ff;
    logic [ADDR_WIDTH - 1 : 0]                addr_dly;

    logic [WAYS - 1 : 0]                      ways_hits;

    // Cache's SRAM busses
    logic [WAYS - 1 : 0][VALID_WIDTH - 1 : 0] sram_ways_valids;
    logic [WAYS - 1 : 0][TAG_WIDTH   - 1 : 0] sram_ways_tags;
    logic [WAYS - 1 : 0][DATA_WIDTH  - 1 : 0] sram_ways_data;

    // Hit signals & registers
    logic                                     hit_ff;
    logic                                     hit_ff_next;
    logic                                     hit_valid_ff;
    logic                                     hit_valid_ff_next;

    // output cache's data register
    logic [DATA_WIDTH - 1 : 0]                data_ff;
    logic [DATA_WIDTH - 1 : 0]                data_ff_next;

    // Cache controller state register
    cache_state_e                             state_ff;
    cache_state_e                             state_ff_next;

    // Cache's SRAM signals & registers
    logic             [ADDR_WIDTH - 1 : 0]    sram_addr_ff;
    logic                                     sram_we_ff;
    logic                                     sram_ce_ff;
    logic             [CELL_WIDTH - 1 : 0]    sram_wdata_ff;
    cache_sram_cell_t [WAYS       - 1 : 0]    sram_rdata; // SRAM cell contains {tag, data}

    logic             [ADDR_WIDTH - 1 : 0]    sram_addr_ff_next;
    logic                                     sram_we_ff_next;
    logic                                     sram_ce_ff_next;
    logic             [CELL_WIDTH - 1 : 0]    sram_wdata_ff_next;

    // External memory signals & registers
    logic                                     ext_mem_req_ff;
    logic             [ADDR_WIDTH - 1 : 0]    ext_mem_addr_ff;
    logic                                     ext_mem_req_ff_next;
    logic             [ADDR_WIDTH - 1 : 0]    ext_mem_addr_ff_next;
    logic             [DATA_WIDTH - 1 : 0]    ext_mem_data;
    logic                                     ext_mem_ack;

    // Valid Status register for each cell
    logic [CELL_AMOUNT - 1 : 0][VALID_WIDTH - 1 : 0] ways_valids_ff;
    logic [CELL_AMOUNT - 1 : 0][VALID_WIDTH - 1 : 0] ways_valids_ff_next;

    // Refill registers
    logic [ADDR_WIDTH       - 1 : 0]                 refill_addr;
    logic [CELL_WIDTH       - 1 : 0]                 refill_data;
    logic [$clog2(WAYS)     - 1 : 0]                 updated_way_ff;
    logic [$clog2(WAYS)     - 1 : 0]                 updated_way_ff_next;

    logic [SETS - 1 : 0][LRU_MATRIX_WIDTH - 1 : 0]   lru_matrix_ff;
    logic [SETS - 1 : 0][LRU_MATRIX_WIDTH - 1 : 0]   lru_matrix_ff_next;
    logic [LRU_MATRIX_WIDTH - 1 : 0]                 lru_matrix_curr;


    // ------------------------------------------------------------------------
    // -- Quality checks
    // ------------------------------------------------------------------------

    sets_param_range : assert property(@(posedge clk_i) SETS >= 1 && SET_WIDTH <= ADDR_WIDTH)
    else $error("Wrong 'SETS' parameter value (%0d). It must be in range [1 : %0d]", SETS, 2 ** ADDR_WIDTH);

    ways_param_range : assert property(@(posedge clk_i) WAYS >= 1 && TAG_WIDTH <= ADDR_WIDTH)
    else $error("Wrong 'WAYS' parameter value (%0d). It must be in range [1 : %0d]", WAYS, 2 ** ADDR_WIDTH);

    set_tag_width_sum : assert property(
        @(posedge clk_i) disable iff(SETS == 1)
        SET_WIDTH + TAG_WIDTH == ADDR_WIDTH)
    else $error("The sum of 'tag' and 'set' widths (%0d) is not equal to 'ADDR_WIDTH' parameter value (%0d).",
        SET_WIDTH + TAG_WIDTH, ADDR_WIDTH);

    set_tag_width_sum_sets_1 : assert property(
        @(posedge clk_i) disable iff(SETS != 1)
        TAG_WIDTH == ADDR_WIDTH && SET_WIDTH == 1)
    else $error("The 'tag' widths (%0d) is not equal to 'ADDR_WIDTH' parameter value (%0d).",
        TAG_WIDTH, ADDR_WIDTH);

    single_hit : assert property(
        @(posedge clk_i) disable iff (!rstn_i)
        $onehot0(ways_hits))
    else $error("Unexpected value of 'ways_hits' ('b%b). Only single bit can be high.", ways_hits);

    addr_undefined : assert property(
        @(posedge clk_i) disable iff(rstn_i)
        !$isunknown(addr_i))
    else $error("The 'addr_i' bus contains undefined value(-s) ('h%x).", addr_i);

    // ------------------------------------------------------------------------
    // -- Synthesizable functions
    // ------------------------------------------------------------------------


    function automatic int get_lru_matrix_idx(input int i, input int j);
        i_less_than_j : assert(i < j);
        int index = (i * (2 * WAYS - i - 1)) / 2 + (j - i - 1);
        return index;
    endfunction

    // Input: lru_matrix_curr[i], updated_way (way with hit or refill way)
    // output: lru_matrix_ff_next[i], where 'i' is inside [0 : SETS-1]
    function automatic logic [LRU_MATRIX_WIDTH - 1 : 0] update_lru_matrix(
        input logic [LRU_MATRIX_WIDTH - 1 : 0] curr_matrix,
        input logic [WAY_CNT_WIDTH    - 1 : 0] updated_way
    );
        int index = 0;
        logic [LRU_MATRIX_WIDTH - 1 : 0] next_matrix = curr_matrix;
        for (int i = 0; i < WAYS - 1; i++) begin
            for (int j = i + 1; j < WAYS; j++) begin
                if (i == updated_way) begin
                    // updated_way is i, and we are at M[i][j]
                    next_matrix[index] = 1'b1;   // i-th way (updated_way) used later than j
                end else if (j == updated_way) begin
                    // updated_way is j, and we are at M[i][j]
                    next_matrix[index] = 1'b0;   // j-th way (updated_way) used later than i
                end
                index++;
            end
        end
        return next_matrix;
    endfunction

    function automatic logic [WAY_CNT_WIDTH - 1 : 0] get_lru_way(
        input logic [LRU_MATRIX_WIDTH - 1 : 0] matrix
    );

        logic [WAYS          - 1 : 0] is_lru;
        logic [WAY_CNT_WIDTH - 1 : 0] lru_way_num = 0;

        if(WAYS > 1) begin
            for (int k = 0; k < WAYS - 1; k++) begin
                is_lru[k] = 1'b1;
                for (int p = k + 1; p < WAYS; p++) begin
                    if (p != k) begin
                        if (p < k) begin
                            if (matrix[get_lru_matrix_idx(p, k)] == 1'b0)
                                is_lru[k] = 1'b0;
                        end else begin
                            if (matrix[get_lru_matrix_idx(k, p)] == 1'b1)
                                is_lru[k] = 1'b0;
                        end
                    end
                end
            end
            onehot_is_lru : assert($onehot(is_lru));

            for (int i = 0; i < WAY_CNT_WIDTH; i++) begin : gen_idx_bit
                logic [WAYS - 1 : 0] mask;
                for (int j = 0; j < WAYS; j++) begin : gen_mask_bit
                    mask[j] = ((j >> i) & 1);
                end
                lru_way_num[i] = |(is_lru & mask);
            end
        end else begin
            lru_way_num = 0;
        end

        return lru_way_num;
    endfunction

    // ------------------------------------------------------------------------
    // -- Cache controller next state logic
    // ------------------------------------------------------------------------

    assign sram_wdata_o   = sram_wdata_ff;
    assign sram_rdata     = sram_rdata_i;
    assign sram_we_o      = sram_we_ff;
    assign sram_ce_o      = sram_ce_ff;
    assign sram_addr_o    = sram_addr_ff;

    assign ext_mem_ack    = ext_mem_ack_i;
    assign ext_mem_addr_o = ext_mem_addr_ff;
    assign ext_mem_req_o  = ext_mem_req_ff;
    assign ext_mem_data   = ext_mem_data_i;

    // LRU
    // TODO implement refill algorithm
    assign refill_addr        = addr_dly;
    assign lru_matrix_curr    = lru_matrix_ff[set_ff];

    always_comb begin
        int curr_set = set_ff;
        for(int s = 0; s < SETS; s++) begin
            if(s == curr_set) begin
                lru_matrix_ff_next[s] = update_lru_matrix(lru_matrix_ff[s], updated_way_ff);
            end else begin
                lru_matrix_ff_next[s] = lru_matrix_ff[s];
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            lru_matrix_ff <= '0;
        end else if (en_i && (state_ff == SRAM_READ && hit_ff_next) || state_ff == SRAM_REFILL) begin
            lru_matrix_ff <= lru_matrix_ff_next;
        end
    end

    always_comb begin : next_state_comb_logic
        // Default values
        sram_we_ff_next         = 1'b0;
        sram_ce_ff_next         = 1'b0;
        hit_valid_ff_next       = 1'b0;
        ext_mem_req_ff_next     = 1'b0;
        sram_addr_ff_next       = '0;
        sram_wdata_ff_next      = sram_wdata_ff;
        data_ff_next            = data_ff;
        ways_valids_ff_next     = ways_valids_ff;
        updated_way_ff_next     = updated_way_ff;
        ext_mem_addr_ff_next    = ext_mem_addr_ff;
        refill_data             = sram_rdata;

        case(state_ff)
        RESET,
        IDLE        : begin
            if(en_i) begin
                state_ff_next     = SRAM_FIRST_READ;
                sram_we_ff_next   = 1'b0;
                sram_ce_ff_next   = 1'b1;
                sram_addr_ff_next = addr_i;
            end else begin
                state_ff_next     = IDLE;
            end
        end
        SRAM_FIRST_READ   : begin
            if(en_i) begin
                state_ff_next     = SRAM_READ;
                sram_we_ff_next   = 1'b0;
                sram_ce_ff_next   = 1'b1;
                sram_addr_ff_next = addr_i;
            end else begin
                state_ff_next     = IDLE;
                sram_we_ff_next   = 1'b0;
                sram_ce_ff_next   = 1'b0;
            end
        end
        SRAM_READ   : begin
            if(en_i) begin
                sram_addr_ff_next = addr_i;
                if(hit_ff_next) begin
                    state_ff_next           = SRAM_READ;
                    sram_we_ff_next         = 1'b0;
                    sram_ce_ff_next         = 1'b1;
                    hit_valid_ff_next       = 1'b1;
                    ext_mem_req_ff_next     = 1'b0;
                    for(int way = 0; way < WAYS; way++) begin
                        if(ways_hits[way]) begin
                            data_ff_next        = sram_ways_data[way];
                            updated_way_ff_next = way;
                            break;
                        end
                    end
                end else begin
                    state_ff_next           = EXT_MEM_REQ;
                    sram_we_ff_next         = 1'b0;
                    sram_ce_ff_next         = 1'b0; // Stall cache state until get acknowledge from external memory
                    hit_valid_ff_next       = 1'b0;
                    ext_mem_req_ff_next     = 1'b1; // Generate request to external memory due to miss
                    ext_mem_addr_ff_next    = addr_dly;
                end
            end else begin
                sram_we_ff_next             = 1'b0;
                sram_ce_ff_next             = 1'b0;
                hit_valid_ff_next           = 1'b0;
                ext_mem_req_ff_next         = 1'b0;
                state_ff_next               = IDLE;
            end
        end
        EXT_MEM_REQ : begin
            ext_mem_req_ff_next     = 1'b1; // Request stay high 2 cycles for synchronous slave (like in Wishbone)
            if(ext_mem_ack) begin
                state_ff_next       = SRAM_REFILL;
                sram_we_ff_next     = 1'b1;
                sram_ce_ff_next     = 1'b1;
                hit_valid_ff_next   = 1'b1;
                data_ff_next        = ext_mem_data;
                sram_addr_ff_next   = refill_addr;

                refill_data[]
                sram_wdata_ff_next  = refill_data;

                // TODO check this implementation
                ways_valids_ff_next[set_ff * WAYS + updated_way_ff] = '1;

                updated_way_ff_next = get_lru_way(lru_matrix_curr);
            end else begin
                state_ff_next       = EXT_MEM_ACK;
                sram_we_ff_next     = 1'b0;
                sram_ce_ff_next     = 1'b0;
                hit_valid_ff_next   = 1'b0;
            end
        end
        EXT_MEM_ACK : begin
            ext_mem_req_ff_next = 1'b0;
            if(ext_mem_ack) begin
                state_ff_next       = SRAM_REFILL;
                sram_we_ff_next     = 1'b1;
                sram_ce_ff_next     = 1'b1;
                hit_valid_ff_next   = 1'b1;
                data_ff_next        = ext_mem_data;
                sram_addr_ff_next   = refill_addr;

                sram_wdata_ff_next  = refill_data;

                // TODO check this implementation
                ways_valids_ff_next[set_ff * WAYS + updated_way_ff] = '1;

                updated_way_ff_next = get_lru_way(lru_matrix_curr);
            end else begin
                state_ff_next       = EXT_MEM_ACK;
                sram_we_ff_next     = 1'b0;
                sram_ce_ff_next     = 1'b0;
                hit_valid_ff_next   = 1'b0;
            end
        end
        SRAM_REFILL : begin
            sram_we_ff_next         = 1'b0;
            hit_valid_ff_next       = 1'b0;
            if(en_i) begin
                state_ff_next       = SRAM_READ;
                sram_ce_ff_next     = 1'b1;
            end else begin
                state_ff_next = IDLE;
                sram_ce_ff_next     = 1'b0;
            end
        end
        endcase // state_ff
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            en_dly_ff <= '0;
        end else begin
            en_dly_ff <= en_i;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            ways_valids_ff <= '0;
        end else begin
            ways_valids_ff <= ways_valids_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            sram_wdata_ff <= 0;
        end else begin
            sram_wdata_ff <= sram_wdata_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            sram_ce_ff <= 0;
        end else begin
            sram_ce_ff <= sram_ce_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            sram_we_ff <= 0;
        end else begin
            sram_we_ff <= sram_we_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            sram_addr_ff <= 0;
        end else begin
            sram_addr_ff <= sram_addr_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            state_ff <= RESET;
        end else begin
            state_ff <= state_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            updated_way_ff <= '0;
        end else begin
            updated_way_ff <= updated_way_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            ext_mem_addr_ff <= '0;
        end else begin
            ext_mem_addr_ff <= ext_mem_addr_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            ext_mem_req_ff <= '0;
        end else begin
            ext_mem_req_ff <= ext_mem_req_ff_next;`
        end
    end

    // ------------------------------------------------------------------------
    // -- Read logic
    // ------------------------------------------------------------------------

    assign hit_o       = hit_ff;
    assign data_o      = data_ff;
    assign hit_valid_o = hit_valid_ff;

    always_comb begin : tag_set_comb_logic
        {tag, set} = (SETS == 1) ? {addr_i, 1'b0} : addr_i;
    end

    always_ff @(posedge clk_i) begin : tag_ff_seq_logic
        if(!rstn_i) begin
            tag_ff <= 0;
        end else if(en_i) begin
            tag_ff <= tag;
        end
    end

    always_ff @(posedge clk_i) begin : set_ff_seq_logic
        if(!rstn_i) begin
            set_ff <= 0;
        end else if(en_i) begin
            set_ff <= set;
        end
    end

    assign addr_dly = {tag_ff, set_ff};

    always_comb begin : ways_fields_comb_logic
        for(int way = 0; way < WAYS; way++) begin
            // sram_ways_valids [way] = sram_rdata[way].valid;
            sram_ways_valids [way] = ways_valids_ff[(set_ff * WAYS) + way];
            sram_ways_tags   [way] = sram_rdata[way].tag;
            sram_ways_data   [way] = sram_rdata[way].data;
        end
    end

    always_comb begin : ways_hits_comb_logic
        for(int way = 0; way < WAYS; way++) begin
            ways_hits[way] = (sram_ways_tags[way] == tag_ff) & (sram_ways_valids[way]);
        end
    end

    always_ff @(posedge clk_i) begin : data_ff_seq_logic
        if(!rstn_i) begin
            data_ff <= 0;
        end else if(en_i) begin
            data_ff <= data_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin : hit_valid_shift_ff_seq_logic
        if(!rstn_i) begin
            hit_valid_ff <= 0;
        end else if(en_i) begin
            hit_valid_ff <= hit_valid_ff_next;
        end
    end

    assign hit_ff_next = |(ways_hits) | ext_mem_ack;
    always_ff @(posedge clk_i) begin : hit_ff_seq_logic
        if(!rstn_i) begin
            hit_ff <= 1'b0;
        end else if(en_i) begin
            hit_ff <= hit_ff_next;
        end
    end

endmodule : cache
