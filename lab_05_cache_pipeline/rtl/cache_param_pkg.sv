package cache_param_pkg;

    `ifdef DIRECT_MAPPED_CACHE
        parameter  SETS = 8;
        parameter  WAYS = 1;
    `elsif FOUR_WAY_SET_ASSOCIATIVE_CACHE
        parameter  SETS = 2;
        parameter  WAYS = 4;
    `elsif FULLY_ASSOCIATIVE_CACHE
        parameter  SETS = 1;
        parameter  WAYS = 8;
    `endif
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 30;

    localparam SET_WIDTH    = SETS != 1 ? $clog2(SETS) : 1;
    localparam TAG_WIDTH    = SETS != 1 ? ADDR_WIDTH - SET_WIDTH : ADDR_WIDTH;

    localparam VALID_WIDTH      = 1;
    localparam CELL_AMOUNT      = SETS;

    // Cache SRAM parameters
    localparam CACHE_CELL_WIDTH = WAYS * (TAG_WIDTH + DATA_WIDTH);
    localparam CELL_WIDTH       = CACHE_CELL_WIDTH;

    // Refill/state SRAM parameters
    localparam WAY_CNT_WIDTH    = (WAYS != 1) ? $clog2(WAYS) : 1;
    localparam LRU_CNT_WIDTH    = WAY_CNT_WIDTH;
    localparam STATE_WAY_WIDTH  = VALID_WIDTH + LRU_CNT_WIDTH;
    localparam STATE_CELL_WIDTH = WAYS * STATE_WAY_WIDTH;

endpackage
