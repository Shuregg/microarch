package cache_param_pkg;

    parameter SETS = 8;
    parameter WAYS = 1;
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 30;

    localparam SET_WIDTH    = SETS != 1 ? $clog2(SETS) : 1;
    localparam TAG_WIDTH    = SETS != 1 ? ADDR_WIDTH - SET_WIDTH : ADDR_WIDTH;

    localparam VALID_WIDTH  = 1;
    localparam READ_LATENCY = 2;
    localparam CELL_AMOUNT  = SETS;
    localparam CELL_WIDTH   = WAYS * (TAG_WIDTH + DATA_WIDTH);

    // Refill parameters
    localparam WAY_CNT_WIDTH = (WAYS != 1) ? $clog2(WAYS) : 1;

endpackage