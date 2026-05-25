module cache_top #(
    parameter int SETS       = 1,
    parameter int WAYS       = 1,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 30
) (
    input  logic                      clk_i,
    input  logic                      rstn_i,

    // Slave request signals
    input  logic                      s_valid_i,
    output logic                      s_ready_o,

    // Master response signals
    output logic                      m_valid_o,
    input  logic                      m_ready_i,

    input  logic [ADDR_WIDTH - 1 : 0] addr_i,
    output logic [DATA_WIDTH - 1 : 0] data_o,
    output logic                      hit_valid_o,
    output logic                      hit_o,

    output logic                      ext_mem_req_o,
    output logic [ADDR_WIDTH - 1 : 0] ext_mem_addr_o,
    input  logic [DATA_WIDTH - 1 : 0] ext_mem_data_i,
    input  logic                      ext_mem_ack_i
);

    localparam int SET_WIDTH        = (SETS != 1) ? $clog2(SETS) : 1;
    localparam int TAG_WIDTH        = (SETS != 1) ? ADDR_WIDTH - SET_WIDTH : ADDR_WIDTH;
    localparam int LRU_CNT_WIDTH    = (WAYS != 1) ? $clog2(WAYS) : 1;
    localparam int CACHE_CELL_WIDTH = WAYS * (TAG_WIDTH + DATA_WIDTH);
    localparam int STATE_WAY_WIDTH  = 1 + LRU_CNT_WIDTH;
    localparam int STATE_CELL_WIDTH = WAYS * STATE_WAY_WIDTH;

    logic [ADDR_WIDTH - 1 : 0]       cache_sram_addr;
    logic                            cache_sram_we;
    logic                            cache_sram_ce;
    logic [CACHE_CELL_WIDTH - 1 : 0] cache_sram_wdata;
    logic [CACHE_CELL_WIDTH - 1 : 0] cache_sram_rdata;

    logic [ADDR_WIDTH - 1 : 0]       state_sram_addr;
    logic                            state_sram_we;
    logic                            state_sram_ce;
    logic [STATE_CELL_WIDTH - 1 : 0] state_sram_wdata;
    logic [STATE_CELL_WIDTH - 1 : 0] state_sram_rdata;

    cache_ctrl #(
        .SETS           (SETS),
        .WAYS           (WAYS),
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH)
    ) u_cache_ctrl (
        .clk_i              (clk_i),
        .rstn_i             (rstn_i),

        .s_valid_i          (s_valid_i),
        .s_ready_o          (s_ready_o),

        .m_valid_o          (m_valid_o),
        .m_ready_i          (m_ready_i),

        .addr_i             (addr_i),
        .data_o             (data_o),
        .hit_valid_o        (hit_valid_o),
        .hit_o              (hit_o),

        .cache_sram_addr_o  (cache_sram_addr),
        .cache_sram_we_o    (cache_sram_we),
        .cache_sram_ce_o    (cache_sram_ce),
        .cache_sram_wdata_o (cache_sram_wdata),
        .cache_sram_rdata_i (cache_sram_rdata),

        .state_sram_addr_o  (state_sram_addr),
        .state_sram_we_o    (state_sram_we),
        .state_sram_ce_o    (state_sram_ce),
        .state_sram_wdata_o (state_sram_wdata),
        .state_sram_rdata_i (state_sram_rdata),

        .ext_mem_req_o      (ext_mem_req_o),
        .ext_mem_addr_o     (ext_mem_addr_o),
        .ext_mem_data_i     (ext_mem_data_i),
        .ext_mem_ack_i      (ext_mem_ack_i)
    );

    cache_sram_model #(
        .CELL_AMOUNT    (SETS),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .CELL_WIDTH     (CACHE_CELL_WIDTH)
    ) u_cache_sram (
        .clk_i          (clk_i),
        .ce_i           (cache_sram_ce),
        .we_i           (cache_sram_we),
        .addr_i         (cache_sram_addr),
        .data_i         (cache_sram_wdata),
        .data_o         (cache_sram_rdata)
    );

    cache_sram_model #(
        .CELL_AMOUNT    (SETS),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .CELL_WIDTH     (STATE_CELL_WIDTH)
    ) u_state_sram (
        .clk_i          (clk_i),
        .ce_i           (state_sram_ce),
        .we_i           (state_sram_we),
        .addr_i         (state_sram_addr),
        .data_i         (state_sram_wdata),
        .data_o         (state_sram_rdata)
    );

endmodule : cache_top
