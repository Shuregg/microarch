module cache_sram_model #(
    CELL_AMOUNT,
    ADDR_WIDTH,
    CELL_WIDTH
) (
    input  logic                      clk_i,
    input  logic                      ce_i,
    input  logic                      we_i,
    input  logic [ADDR_WIDTH - 1 : 0] addr_i,
    input  logic [CELL_WIDTH - 1 : 0] data_i,
    output logic [CELL_WIDTH - 1 : 0] data_o
);
    // Internal address width (or set width)
    localparam INT_ADDR_WIDTH = CELL_AMOUNT != 1 ? $clog2(CELL_AMOUNT) : 1;

    set_tag_width_sum : assert property(
        @(posedge clk_i) 
        INT_ADDR_WIDTH >= 1)
    else $error("Wrong INT_ADDR_WIDTH parameter value (%0d).", INT_ADDR_WIDTH);

    // Local wires & registers
    logic [CELL_WIDTH     - 1 : 0] sram       [0: CELL_AMOUNT - 1];
    logic [CELL_WIDTH     - 1 : 0] data_o_ff;
    logic [INT_ADDR_WIDTH - 1 : 0] int_addr;
    logic                          rd_op;
    logic                          wr_op;

    assign data_o   = data_o_ff;
    assign int_addr = (CELL_AMOUNT != 1) ? (addr_i[INT_ADDR_WIDTH - 1 : 0]) : ('0);

    assign rd_op = ce_i & (~we_i);
    assign wr_op = ce_i & we_i;

    always_ff @(posedge clk_i) begin : data_rd_seq_logic
        if(rd_op) begin
            data_o_ff <= sram[int_addr];
        end else begin
            data_o_ff <= data_o_ff;
        end
    end

    always_ff @(posedge clk_i) begin : data_wr_seq_logic
        if(wr_op) begin
            sram[int_addr] <= data_i;
        end
    end

endmodule
