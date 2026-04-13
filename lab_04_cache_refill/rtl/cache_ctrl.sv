module cache_ctrl #(
    SETS,
    WAYS,
    DATA_WIDTH,
    ADDR_WIDTH
) (
    input  logic                      clk_i,
    input  logic                      rstn_i,

    // Slave request signals
    input  logic                      s_valid_i,
    output logic                      s_ready_o,

    // Master request signals
    output logic                      m_valid_o,
    input  logic                      m_ready_i, // not supported.

    input  logic [ADDR_WIDTH - 1 : 0] addr_i,
    output logic [DATA_WIDTH - 1 : 0] data_o,
    output logic                      hit_valid_o,
    output logic                      hit_o,

    output logic                      sram_ce_o,
    output logic                      sram_we_o,
    output logic [ADDR_WIDTH - 1 : 0] sram_addr_o,
    output logic [CELL_WIDTH - 1 : 0] sram_wdata_o,
    input  logic [CELL_WIDTH - 1 : 0] sram_rdata_i,

    output logic                      ext_mem_req_o,
    output logic [ADDR_WIDTH - 1 : 0] ext_mem_addr_o,
    input  logic [DATA_WIDTH - 1 : 0] ext_mem_data_i,
    input  logic                      ext_mem_ack_i

);

    // ------------------------------------------------------------------------
    // -- Local parameters
    // ------------------------------------------------------------------------

    localparam SET_FIELD_WIDTH = SETS != 1 ? $clog2(SETS) : 1;
    localparam TAG_FIELD_WIDTH = SETS != 1 ? ADDR_WIDTH - SET_FIELD_WIDTH : ADDR_WIDTH;
    localparam READ_LATENCY = 2;

    // Single SRAM cell contains tags and data of all ways
    localparam CELL_AMOUNT = SETS;
    localparam CELL_WIDTH = WAYS * (TAG_FIELD_WIDTH + DATA_WIDTH);

    // ------------------------------------------------------------------------
    // -- Quality checks
    // ------------------------------------------------------------------------

    sets_param_range : assert property(@(posedge clk_i) SETS >= 1 && SET_FIELD_WIDTH <= ADDR_WIDTH)
    else $error("Wrong 'SETS' parameter value (%0d). It must be in range [1 : %0d]", SETS, 2 ** ADDR_WIDTH);

    ways_param_range : assert property(@(posedge clk_i) WAYS >= 1 && TAG_FIELD_WIDTH <= ADDR_WIDTH)
    else $error("Wrong 'WAYS' parameter value (%0d). It must be in range [1 : %0d]", WAYS, 2 ** ADDR_WIDTH);

    set_tag_width_sum : assert property(
        @(posedge clk_i) disable iff(SETS == 1) 
        SET_FIELD_WIDTH + TAG_FIELD_WIDTH == ADDR_WIDTH)
    else $error("The sum of 'tag' and 'set' widths (%0d) is not equal to 'ADDR_WIDTH' parameter value (%0d).",
        SET_FIELD_WIDTH + TAG_FIELD_WIDTH, ADDR_WIDTH);

    set_tag_width_sum_sets_1 : assert property(
        @(posedge clk_i) disable iff(SETS != 1) 
        TAG_FIELD_WIDTH == ADDR_WIDTH && SET_FIELD_WIDTH == 1)
    else $error("The 'tag' widths (%0d) is not equal to 'ADDR_WIDTH' parameter value (%0d).",
        TAG_FIELD_WIDTH, ADDR_WIDTH);

    single_hit : assert property(
        @(posedge clk_i) disable iff (!rstn_i)
        $onehot0(ways_hits))
    else $error("Unexpected value of 'ways_hits' ('b%b). Only single bit can be high.", ways_hits);

    addr_undefined : assert property(
        @(posedge clk_i) disable iff(!rstn_i) 
        !$isunknown(addr_i))
    else $error("The 'addr_i' bus contains undefined value(-s) ('h%x).",
        addr_i);

    // ------------------------------------------------------------------------
    // -- Type definitions
    // ------------------------------------------------------------------------

    typedef struct packed {
        logic [TAG_FIELD_WIDTH - 1 : 0] tag;
        logic [DATA_WIDTH      - 1 : 0] data;
    } sram_cell_t;

    typedef enum logic [STATE_WIDTH - 1 : 0] {
        RESET,
        IDLE,
        SRAM_REQ,
        SRAM_ACK,
        EXT_MEM_REQ,
        EXT_MEM_ACK,
        EVICT
    } cache_ctrl_state_t;

    // ------------------------------------------------------------------------
    // -- Internal registers and wires
    // ------------------------------------------------------------------------

    // SRAM cells: Valid, tag, data
    sram_cell_t [WAYS - 1 : 0] sram_cell_of_curr_set;
    logic [CELL_AMOUNT - 1 : 0][WAYS - 1 : 0] sram_valids_ff;
    logic [CELL_AMOUNT - 1 : 0][WAYS - 1 : 0] sram_valids_ff_next;

    // Cache's SRAM interface signals
    logic                      sram_ce_ff;
    logic                      sram_ce_ff_next;
    logic                      sram_we_ff;
    logic                      sram_we_ff_next;
    logic [ADDR_WIDTH - 1 : 0] sram_addr_ff;
    logic [ADDR_WIDTH - 1 : 0] sram_addr_ff_next;
    logic [CELL_WIDTH - 1 : 0] sram_wdata_ff;
    logic [CELL_WIDTH - 1 : 0] sram_wdata_ff_next;
    logic [CELL_WIDTH - 1 : 0] sram_rdata_ff;
    logic [CELL_WIDTH - 1 : 0] sram_rdata_ff_next;
    logic                      sram_rdata_ff_en;

    // Address shift register with depth = 4
    logic [SHIFT_REG_DEPTH - 1 : 0][ADDR_WIDTH      - 1 : 0] addr_shift_ff;
    logic                                                    addr_shift_ff_en;
    logic [SHIFT_REG_DEPTH - 1 : 0][TAG_FIELD_WIDTH - 1 : 0] decoded_tag;
    logic [SHIFT_REG_DEPTH - 1 : 0][SET_FIELD_WIDTH - 1 : 0] decoded_set;

    logic [0 : WAYS - 1]                     ways_hits;
    logic [0 : WAYS - 1][DATA_WIDTH - 1 : 0] ways_data;

    logic                                    hit_ff;
    logic                                    hit_ff_next;
    // logic [READ_LATENCY - 1 : 0]             hit_valid_shift_ff; // hit_valid shift reg
    logic                                    hit_valid_ff;
    logic                                    hit_valid_ff_next;
    logic [DATA_WIDTH - 1 : 0]               data_ff;
    logic [DATA_WIDTH - 1 : 0]               data_ff_next;

    cache_ctrl_state_t                       state_ff;
    cache_ctrl_state_t                       state_ff_next;
    logic                                    state_ff_en;

    logic                                    s_hs;
    logic                                    s_ready_ff;
    logic                                    s_ready_ff_next;
    logic                                    m_hs;
    logic                                    m_valid_ff;
    logic                                    m_valid_ff_next;

    logic                                    ext_mem_req_ff;
    logic                                    ext_mem_req_ff_next;
    logic                                    ext_mem_ack;
    logic [DATA_WIDTH - 1 : 0]               ext_mem_data;
    logic [ADDR_WIDTH - 1 : 0]               ext_mem_addr_ff;
    logic [ADDR_WIDTH - 1 : 0]               ext_mem_addr_ff_next;

    logic [WAY_IDX_WIDTH - 1 : 0]                      way_hit_num_of_curr_set;
    sram_cell_t [WAYS - 1: 0]                          refilled_sram_cell_ff;
    sram_cell_t [WAYS - 1: 0]                          refilled_sram_cell_ff_next;
    logic [CELL_AMOUNT - 1 : 0][MATRIX_BITS - 1 : 0]   lru_matrix_ff;
    logic [CELL_AMOUNT - 1 : 0][MATRIX_BITS - 1 : 0]   lru_matrix_next;
    logic [CELL_AMOUNT - 1 : 0]                        lru_update_en;
    logic [CELL_AMOUNT - 1 : 0]                        lru_hit;
    logic [CELL_AMOUNT - 1 : 0][WAY_IDX_WIDTH - 1 : 0] lru_hit_way;
    logic [CELL_AMOUNT - 1 : 0][WAY_IDX_WIDTH - 1 : 0] lru_way;

    logic [WAY_IDX_WIDTH - 1 : 0] replaced_way_ff;
    logic [WAY_IDX_WIDTH - 1 : 0] replaced_way_ff_next;
    logic [WAY_IDX_WIDTH - 1 : 0] replaced_way_ff_en;

    // ------------------------------------------------------------------------
    // -- Instances
    // ------------------------------------------------------------------------

    genvar set_idx;
    generate
        for (set_idx = 0; set_idx < CELL_AMOUNT; set_idx++) begin : lru_gen
            matrix_lru #(
                .WAYS (WAYS)
            ) u_matrix_lru (
                .clk_i      (clk_i),
                .rstn_i     (rstn_i),
                .en_i       (lru_update_en[set_idx]),
                .hit_i      (lru_hit[set_idx]),
                .hit_way_i  (lru_hit_way[set_idx]),
                .lru_way_o  (lru_way[set_idx])
            );
        end
    endgenerate

    assign ext_mem_ack = ext_mem_ack_i;
    assign ext_mem_req_o = ext_mem_req_ff;

    // assign s_ready_o = 

    // Slave handshake;
    assign s_ready_o = s_ready_ff;
    assign s_hs = s_valid_i & s_ready_o;

    // Master handshake
    assign m_valid_o = m_valid_ff;
    assign m_hs = m_valid_o & m_ready_i;

    // Register enable signals
    assign state_ff_en = 1'b1;
    // assign addr_shift_ff_en = 1'b1;

    // FSM next state logic
    always_comb begin
        sram_ce_ff_next         = '0;
        sram_we_ff_next         = '0;
        sram_addr_ff_next       = '0;
        sram_wdata_ff_next      = '0;
        sram_valids_ff_next     = sram_valids_ff;

        data_ff_next            = '0;

        hit_valid_ff_next       = '0;
        s_ready_ff_next         = 1'b0;
        m_valid_ff_next         = hit_valid_ff_next;

        ext_mem_req_ff_next     = '0;
        ext_mem_addr_ff_next    = '0;

        addr_shift_ff_en        = 1'b1;
        sram_rdata_ff_en        = 1'b1;

        lru_update_en           = '0;
        lru_hit                 = '0;
        lru_hit_way             = '0;
        way_hit_num_of_curr_set = '0;

        replaced_way_ff_en      = '0;

        refilled_sram_cell_ff_next = sram_cell_of_curr_set;

        case (state_ff)
            RESET,
            IDLE: begin
                s_ready_ff_next         = 1'b1;
                if (s_hs) begin
                    state_ff_next       = SRAM_REQ;
                    sram_ce_ff_next     = 1'b1;
                    sram_addr_ff_next   = addr_i;
                end else begin
                    state_ff_next       = IDLE;
                end
            end
            SRAM_REQ: begin
                state_ff_next = SRAM_ACK;
            end
            SRAM_ACK: begin
                if (hit_ff_next) begin
                    s_ready_ff_next = 1'b1;
                    for(int way = 0; way < WAYS; way++) begin
                        if (ways_hits[way]) begin
                            data_ff_next = sram_cell_of_curr_set[way].data;
                            hit_valid_ff_next = 1'b1;
                            // Determine the number (index) of way with hit
                            way_hit_num_of_curr_set = way[WAY_IDX_WIDTH - 1 : 0];
                            break;
                        end
                    end

                    // Update LRU matrix
                    lru_update_en [decoded_set[1]] = 1'b1;
                    lru_hit       [decoded_set[1]] = 1'b1;
                    lru_hit_way   [decoded_set[1]] = way_hit_num_of_curr_set;

                    // If new request received -> go to SRAM_REQ state
                    if(s_hs) begin
                        state_ff_next     = SRAM_REQ;
                        sram_ce_ff_next   = 1'b1;
                        sram_addr_ff_next = addr_i;
                    end else begin
                        state_ff_next = IDLE;
                    end
                end else begin
                    state_ff_next        = EXT_MEM_REQ;
                    sram_rdata_ff_en     = 1'b0; // Do not update rdata.
                                                 // It will be used for evicting.

                    s_ready_ff_next      = 1'b0; // Do not receive new requests
                                                 // while accessing to the
                                                 // external memory

                    addr_shift_ff_en     = 1'b0; // Do not shift

                    lru_update_en [decoded_set[1]] = 1'b1;
                    lru_hit       [decoded_set[1]] = 1'b0; // Miss
                    // lru_hit_way is no matter when miss

                    ext_mem_req_ff_next  = 1;
                    ext_mem_addr_ff_next = addr_shift_ff[1];
                end
            end
            EXT_MEM_REQ: begin
                // Immediate reaction from external memory is unrealistic.
                // No aknowledge check in this state.
                // if(ext_mem_ack)

                state_ff_next        = EXT_MEM_ACK;
                // Stay req high 2-nd cycle (Wishbone style)
                ext_mem_req_ff_next  = 1;
                ext_mem_addr_ff_next = addr_shift_ff[1];
                sram_rdata_ff_en     = 1'b0; // Do not update rdata.
                addr_shift_ff_en     = 1'b0; // Do not shift
                s_ready_ff_next      = 1'b0;

                replaced_way_ff_en   = 1;
                replaced_way_ff_next = lru_way[decoded_set[1]];
            end
            EXT_MEM_ACK: begin
                if(ext_mem_ack) begin
                    state_ff_next                                        = EVICT;

                    s_ready_ff_next                                      = 1'b0;

                    sram_ce_ff_next                                      = 1'b1;
                    sram_we_ff_next                                      = 1'b1;
                    sram_addr_ff_next                                    = addr_shift_ff[1];
                    refilled_sram_cell_ff_next[replaced_way_ff].tag      = decoded_tag[1];
                    refilled_sram_cell_ff_next[replaced_way_ff].data     = ext_mem_data;
                    sram_wdata_ff_next                                   = refilled_sram_cell_ff_next;
                    sram_valids_ff_next[decoded_set[1]][replaced_way_ff] = 1'b1;

                    data_ff_next                                         = ext_mem_data;
                    addr_shift_ff_en                                     = 1'b1; // ???

                    // lru_update_en [decoded_set[1]] = 1'b1;
                    // lru_hit       [decoded_set[1]] = 1'b0;
                end else begin
                    state_ff_next        = EXT_MEM_ACK;
                    sram_rdata_ff_en     = 1'b0; // Do not update rdata.
                    addr_shift_ff_en     = 1'b0;
                    ext_mem_addr_ff_next = addr_shift_ff[1];
                end
            end
            EVICT: begin
                s_ready_ff_next = 1'b1;
                if(s_valid_i) begin
                    state_ff_next     = SRAM_REQ;
                    sram_ce_ff_next   = 1'b1;
                    sram_addr_ff_next = addr_i;
                end else begin
                    state_ff_next     = IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            state_ff <= RESET;
        end else if (state_ff_en) begin
            state_ff <= state_ff_next;
        end
    end

    assign sram_ce_o    = sram_ce_ff;
    assign sram_we_o    = sram_we_ff;
    assign sram_addr_o  = sram_addr_ff;
    assign sram_wdata_o = sram_wdata_ff;

    // Cache's SRAM signals logic
    assign sram_cell_of_curr_set = sram_rdata_i;

    // Read logic
    assign hit_o       = hit_ff;
    assign data_o      = data_ff;
    // assign hit_valid_o = hit_valid_shift_ff[READ_LATENCY - 1];
    assign hit_valid_o = hit_valid_ff;

    always_comb begin
        if(SETS == 1) begin
            for(int i = 0; i < SHIFT_REG_DEPTH; i++) begin
                decoded_tag[i] = addr_shift_ff[i];
                decoded_set[i] = '0;
            end
        end else begin
            for(int i = 0; i < SHIFT_REG_DEPTH; i++) begin
                {decoded_tag[i], decoded_set[i]} = addr_shift_ff[i];
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            addr_shift_ff <= '0;
        end else if (addr_shift_ff_en) begin
            addr_shift_ff <= {addr_shift_ff[SHIFT_REG_DEPTH - 2 : 0], addr_i};
        end
    end

    always_comb begin : ways_hits_comb_logic
        for(int way = 0; way < WAYS; way++) begin
            ways_hits[way] = (sram_cell_of_curr_set[way].tag == decoded_tag[0]) & (sram_valids_ff[decoded_set[0]][way]);
        end
    end

    always_ff @(posedge clk_i) begin : data_ff_seq_logic
        if (!rstn_i) begin
            data_ff <= 0;
        end else begin
            data_ff <= data_ff_next;
        end
    end

    // always_ff @(posedge clk_i) begin : hit_valid_shift_ff_seq_logic
    //     if (!rstn_i) begin
    //         hit_valid_shift_ff <= 0;
    //     end else begin
    //         hit_valid_shift_ff <= {hit_valid_shift_ff[READ_LATENCY - 2 : 0], 1'b1};
    //     end
    // end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            hit_valid_ff <= '0;
        end else begin
            hit_valid_ff <= hit_valid_ff_next;
        end
    end

    assign hit_ff_next = |(ways_hits);
    always_ff @(posedge clk_i) begin : hit_ff_seq_logic
        if (!rstn_i) begin
            hit_ff <= 1'b0;
        end else begin
            hit_ff <= hit_ff_next;
        end
    end

    // Handshake logic
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            s_ready_ff <= 1'b1;
        end else begin
            s_ready_ff <= s_ready_ff_next;
        end
    end
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            m_valid_ff <= 1'b0;
        end else begin
            m_valid_ff <= m_valid_ff_next;
        end
    end

    // Cache's SRAM memory logic

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            sram_ce_ff <= 1'b0;
        end else begin
            sram_ce_ff <= sram_ce_ff_next;
        end
    end
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            sram_we_ff <= '0;
        end else begin
            sram_we_ff <= sram_we_ff_next;
        end
    end
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            sram_addr_ff <= '0;
        end else begin
            sram_addr_ff <= sram_addr_ff_next;
        end
    end
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            sram_wdata_ff <= '0;
        end else begin
            sram_wdata_ff <= sram_wdata_ff_next;
        end
    end

    // always_ff @(posedge clk_i) begin
    //     if (!rstn_i) begin
    //         sram_rdata_ff <= '0;
    //     end else if (sram_rdata_ff_en) begin
    //         sram_rdata_ff <= sram_rdata_ff_next;
    //     end
    // end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            sram_valids_ff <= '0;
        end else begin
            sram_valids_ff <= sram_valids_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            replaced_way_ff <= '0;
        end else if(replaced_way_ff_en) begin
            replaced_way_ff <= replaced_way_ff_next;
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            refilled_sram_cell_ff <= '0;
        end else begin
            refilled_sram_cell_ff <= refilled_sram_cell_ff_next;
        end
    end

    // External memory logic
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            ext_mem_req_ff <= '0;
        end else begin
            ext_mem_req_ff <= ext_mem_req_ff_next;
        end
    end



endmodule : cache_ctrl
