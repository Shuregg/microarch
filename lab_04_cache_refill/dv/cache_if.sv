interface cache_if # (
    parameter ADDR_WIDTH = 30,
    parameter DATA_WIDTH = 32
) (
    input logic                clk,
    input logic                rstn
);
    logic [ADDR_WIDTH - 1 : 0] addr;
    logic [DATA_WIDTH - 1 : 0] data;
    logic                      hit_valid;
    logic                      hit;
endinterface : cache_if
