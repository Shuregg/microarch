module tb_direct_mapped_cache();

    `define INI_FILE_PATH ""

    parameter  ADDR_WIDTH        = 32;
    parameter  DATA_WIDTH        = 32;
    parameter  BYTE_OFFSET_WIDTH = 2
    localparam WORD_AMOUNT       = ADDR_WIDTH - BYTE_OFFSET_WIDTH;

    logic [DATA_WIDTH - 1 : 0] expeced_words[WORD_AMOUNT];

    cache #(
        .SETS        (8),
        .WAYS        (1),
        .DATA_WIDTH  (32),
        .ADDR_WIDTH  (WORD_AMOUNT)
    ) u_direct_mapped_cache (
        .clk_i       (clk),
        .rstn_i      (rstn),
        .addr_i      (addr),
        .data_o      (data),
        .hit_valid_o (hit_valid),
        .hit_o       (hit)
    );

    initial begin
        $readmemh("./mem_lists/")
    end

endmodule : tb_direct_mapped_cache