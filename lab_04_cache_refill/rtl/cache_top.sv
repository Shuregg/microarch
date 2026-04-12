module cache_top #(
    SETS        = 8,
    WAYS        = 1,
    DATA_WIDTH  = 32,
    ADDR_WIDTH  = 30
) (
    input  logic                      clk_i,
    input  logic                      rstn_i,

    // Slave request signals
    input  logic                      s_valid_i,
    output logic                      s_ready_o,

    // Master request signals
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

    localparam CELL_AMOUNT  = SETS;
    localparam CELL_WIDTH   = WAYS * (TAG_WIDTH + DATA_WIDTH);

    logic [ADDR_WIDTH - 1 : 0] sram_addr;
    logic                      sram_we;
    logic                      sram_ce;
    logic [CELL_WIDTH - 1 : 0] sram_wdata;
    logic [CELL_WIDTH - 1 : 0] sram_rdata;

    cache_ctrl #(
        .SETS           (SETS),
        .WAYS           (WAYS),
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH)
    ) u_cache_ctrl (
        .clk_i          (clk_i),
        .rstn_i         (rstn_i),

        .s_valid_i      (s_valid_i),
        .s_ready_o      (s_ready_o),

        .m_valid_o      (m_valid_o),
        .m_ready_i      (m_ready_i),

        .addr_i         (addr_i),
        .data_o         (data_o),
        .hit_valid_o    (hit_valid_o),
        .hit_o          (hit_o),

        .sram_addr_o    (sram_addr),
        .sram_we_o      (sram_we),
        .sram_ce_o      (sram_ce),
        .sram_wdata_o   (sram_wdata),
        .sram_rdata_i   (sram_rdata),

        .ext_mem_req_o  (ext_mem_req_o),
        .ext_mem_addr_o (ext_mem_addr_o),
        .ext_mem_data_i (ext_mem_data_i),
        .ext_mem_ack_i  (ext_mem_ack_i)
    );

    cache_sram_model #(
        .CELL_AMOUNT    (CELL_AMOUNT),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .CELL_WIDTH     (CELL_WIDTH)
    ) u_cache_sram (
        .clk_i          (clk_i),
        .ce_i           (sram_ce),
        .we_i           (sram_we),
        .addr_i         (sram_addr),
        .data_i         (sram_wdata),
        .data_o         (sram_rdata)
    );

endmodule