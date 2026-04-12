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

    // Slave request signals
    logic                      s_valid;
    logic                      s_ready;

    // Master request signals
    logic                      m_valid;
    logic                      m_ready;

    logic [ADDR_WIDTH - 1 : 0] addr;
    logic [DATA_WIDTH - 1 : 0] data;
    logic                      hit_valid;
    logic                      hit;

    logic                      sram_ce;
    logic                      sram_we;
    logic [ADDR_WIDTH - 1 : 0] sram_addr;
    logic [CELL_WIDTH - 1 : 0] sram_wdata;
    logic [CELL_WIDTH - 1 : 0] sram_rdata;

    logic                      ext_mem_req;
    logic [ADDR_WIDTH - 1 : 0] ext_mem_addr;
    logic [DATA_WIDTH - 1 : 0] ext_mem_data;
    logic                      ext_mem_ack;

endinterface : cache_if
