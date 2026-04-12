module cache #(
    SETS = 8,
    WAYS = 1,
    DATA_WIDTH = 32,
    ADDR_WIDTH = 30
) (
    input  logic                      clk_i,
    input  logic                      rstn_i,
    input  logic [ADDR_WIDTH - 1 : 0] addr_i,
    output logic [DATA_WIDTH - 1 : 0] data_o,
    output logic                      hit_valid_o,
    output logic                      hit_o
);

    // ------------------------------------------------------------------------
    // -- Local parameters
    // ------------------------------------------------------------------------

    localparam SET_FIELD_WIDTH = SETS != 1 ? $clog2(SETS) : 1;
    localparam TAG_FIELD_WIDTH = SETS != 1 ? ADDR_WIDTH - SET_FIELD_WIDTH : ADDR_WIDTH;
    localparam READ_LATENCY = 2;

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
        @(posedge clk_i) disable iff(rstn_i) 
        !$isunknown(addr_i))
    else $error("The 'addr_i' bus contains undefined value(-s) ('h%x).",
        addr_i);

    // ------------------------------------------------------------------------
    // -- Type definitions
    // ------------------------------------------------------------------------

    typedef struct packed {
        logic                           valid;
        logic [TAG_FIELD_WIDTH - 1 : 0] tag;
        logic [DATA_WIDTH      - 1 : 0] data;
    } set_t;

    // ------------------------------------------------------------------------
    // -- Internal registers and wires
    // ------------------------------------------------------------------------

    set_t sram[0 : SETS - 1][0 : WAYS - 1];

    logic [WAYS - 1 : 0][TAG_FIELD_WIDTH - 1 : 0] sram_tags_ff;
    logic [WAYS - 1 : 0]                          sram_valids_ff;

    logic [TAG_FIELD_WIDTH - 1 : 0]          tag;
    logic [TAG_FIELD_WIDTH - 1 : 0]          tag_ff;
    logic [SET_FIELD_WIDTH - 1 : 0]          set;
    logic [SET_FIELD_WIDTH - 1 : 0]          set_ff;

    logic [0 : WAYS - 1]                     ways_hits;
    logic [0 : WAYS - 1][DATA_WIDTH - 1 : 0] ways_data;

    logic                                    hit_ff;
    logic [READ_LATENCY - 1 : 0]             hit_valid_shift_ff; // hit_valid shift reg
    logic [DATA_WIDTH - 1 : 0]               data_ff;
    logic [DATA_WIDTH - 1 : 0]               data_ff_next;

    // ------------------------------------------------------------------------
    // -- Read logic
    // ------------------------------------------------------------------------

    assign hit_o       = hit_ff;
    assign data_o      = data_ff;
    assign hit_valid_o = hit_valid_shift_ff[READ_LATENCY - 1];

    always_comb begin : tag_set_comb_logic
        {tag, set} = (SETS == 1) ? {addr_i, 1'b0} : addr_i;
    end

    always_ff @(posedge clk_i) begin : tag_ff_seq_logic
        if(!rstn_i) begin
            tag_ff <= 0;
        end else begin
            tag_ff <= tag;
        end
    end

    always_ff @(posedge clk_i) begin : set_ff_seq_logic
        if(!rstn_i) begin
            set_ff <= 0;
        end else begin
            set_ff <= set;
        end
    end

    always_ff @(posedge clk_i) begin : sram_valids_ff_seq_logic
        for(int way = 0; way < WAYS; way++) begin
            if(!rstn_i) begin
                // No reset for sram_valids_ff[way] registers
            end else begin
                sram_valids_ff[way] <= sram[set][way].valid;
            end
        end
    end

    always_ff @(posedge clk_i) begin : sram_tags_ff_seq_logic
        for(int way = 0; way < WAYS; way++) begin
            if(!rstn_i) begin
                // No reset for sram_tags_ff[way] registers
            end else begin
                sram_tags_ff[way] <= sram[set][way].tag;
            end
        end
    end

    always_ff @(posedge clk_i) begin : ways_data_seq_logic
        for(int way = 0; way < WAYS; way++) begin
            if(!rstn_i) begin
                // No reset for ways_data[way] registers
            end else begin
                ways_data[way] <= (sram[set][way].data);
            end
        end
    end

    always_comb begin : ways_hits_comb_logic
        for(int way = 0; way < WAYS; way++) begin
            ways_hits[way] = (sram_tags_ff[way] == tag_ff) & (sram_valids_ff[way]);
        end
    end

    always_comb begin : data_ff_next_comb_logic
        for(int way = 0; way < WAYS; way++) begin
            if(ways_hits[way]) begin
                data_ff_next = ways_data[way];
                break;
            end else begin
                data_ff_next = data_ff;
            end
        end
    end

    always_ff @(posedge clk_i) begin : data_ff_seq_logic
        if(!rstn_i) begin
            data_ff <= 0;
        end else begin
            data_ff <= data_ff_next;
        end
    end

    // always_ff @(posedge clk_i) begin : data_ff_seq_logic
    //     for(int way = 0; way < WAYS; way++) begin
    //         if(!rstn_i) begin
    //             data_ff <= 0;
    //         end else if(ways_hits[way]) begin
    //             data_ff <= ways_data[way];
    //         end else begin
    //             data_ff <= data_ff;
    //         end
    //     end
    // end

    always_ff @(posedge clk_i) begin : hit_valid_shift_ff_seq_logic
        if(!rstn_i) begin
            hit_valid_shift_ff <= 0;
        end else begin
            hit_valid_shift_ff <= {hit_valid_shift_ff[0], 1'b1};
        end
    end

    always_ff @(posedge clk_i) begin : hit_ff_seq_logic
        if(!rstn_i) begin
            hit_ff <= 1'b0;
        end else begin
            hit_ff <= ^(ways_hits);
        end
    end

endmodule : cache
