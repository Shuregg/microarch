package cache_param_pkg;

    parameter SETS = 8;
    parameter WAYS = 1;
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 30;

    localparam SET_WIDTH    = SETS != 1 ? $clog2(SETS) : 1;
    localparam TAG_WIDTH    = SETS != 1 ? ADDR_WIDTH - SET_WIDTH : ADDR_WIDTH;
    // localparam SET_WIDTH = (SETS == 1) ? 0 : $clog2(SETS);
    // localparam TAG_WIDTH = ADDR_WIDTH - SET_WIDTH;

    localparam VALID_WIDTH  = 1;
    localparam READ_LATENCY = 2;
    localparam CELL_AMOUNT  = SETS * WAYS;
    localparam CELL_WIDTH   = WAYS * (/*VALID_WIDTH*/ + TAG_WIDTH + DATA_WIDTH);

    // Refill parameters
    localparam WAY_CNT_WIDTH    = (WAYS != 1) ? $clog2(WAYS) : 1;
    localparam LRU_MATRIX_WIDTH = (WAYS > 1) ? ((WAYS * (WAYS - 1)) / 2) : 1;

    /*
       j: 0 1 2 3
          _ _ _ _
    i:  0|-|a|b|c|
        1|-|-|d|e|
        2|-|-|-|f|
        3|-|-|-|-|



        M[i][j] = 1: way i used later than way j
        M[i][j] = 0: way j used later than way i

        Way k is LRU if for all p != k:
            if p < k then M[p][k] == 1 (p used later than k)
            if p > k then M[p][k] == 0 (p used later than k)

    */

endpackage