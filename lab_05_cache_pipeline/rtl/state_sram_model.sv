module state_sram_model #(
    parameter int CELL_AMOUNT,
    parameter int ADDR_WIDTH,
    parameter int CELL_WIDTH
) (
    input  logic clk_i,

    // Port A: read-only (CACHE_REQ stage drives, CHECK_TAG stage reads)
    input  logic                      a_ce_i,
    input  logic [ADDR_WIDTH - 1 : 0] a_addr_i,
    output logic [CELL_WIDTH - 1 : 0] a_data_o,

    // Port B: write-only (init / CHECK_TAG hit LRU / REFILL miss LRU)
    input  logic                      b_ce_i,
    input  logic                      b_we_i,
    input  logic [ADDR_WIDTH - 1 : 0] b_addr_i,
    input  logic [CELL_WIDTH - 1 : 0] b_data_i
);

    localparam INT_ADDR_WIDTH = (CELL_AMOUNT != 1) ? $clog2(CELL_AMOUNT) : 1;

    logic [CELL_WIDTH     - 1 : 0] sram [0 : CELL_AMOUNT - 1];
    logic [CELL_WIDTH     - 1 : 0] a_data_ff;

    assign a_data_o = a_data_ff;

    // Port A: synchronous read, read-first (sees value before same-cycle Port B write)
    always_ff @(posedge clk_i) begin : port_a_read
        if (a_ce_i) begin
            a_data_ff <= sram[(CELL_AMOUNT != 1) ? a_addr_i[INT_ADDR_WIDTH - 1 : 0] : '0];
        end
    end

    // Port B: synchronous write
    always_ff @(posedge clk_i) begin : port_b_write
        if (b_ce_i && b_we_i) begin
            sram[(CELL_AMOUNT != 1) ? b_addr_i[INT_ADDR_WIDTH - 1 : 0] : '0] <= b_data_i;
        end
    end

endmodule : state_sram_model
