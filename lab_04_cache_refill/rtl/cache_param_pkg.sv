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

    parameter STATE_WIDTH = 4;
    parameter SHIFT_REG_DEPTH = 4;

    localparam SET_WIDTH    = SETS != 1 ? $clog2(SETS) : 1;
    localparam TAG_WIDTH    = SETS != 1 ? ADDR_WIDTH - SET_WIDTH : ADDR_WIDTH;

    localparam VALID_WIDTH  = 1;
    localparam READ_LATENCY = 2;
    localparam CELL_AMOUNT  = SETS;
    localparam CELL_WIDTH   = WAYS * (TAG_WIDTH + DATA_WIDTH);

    // Refill parameters
    localparam WAY_CNT_WIDTH = (WAYS != 1) ? $clog2(WAYS) : 1;

endpackage
