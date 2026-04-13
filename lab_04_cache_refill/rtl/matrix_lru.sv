module matrix_lru #(
    parameter int WAYS
) (
    input  logic                     clk_i,
    input  logic                     rstn_i,
    input  logic                     en_i,
    input  logic                     hit_i,
    input  logic [WAY_IDX_WIDTH - 1 : 0] hit_way_i,
    output logic [WAY_IDX_WIDTH - 1 : 0] lru_way_o
);

    localparam int WAY_IDX_WIDTH = (WAYS > 1) ? $clog2(WAYS) : 1;
    localparam int MATRIX_BITS = (WAYS > 1) ? WAYS * (WAYS - 1) / 2 : 1;

    logic [MATRIX_BITS-1:0] matrix_ff;

    function automatic int get_index(int i, int j);
        return i * WAYS - (i * (i + 1)) / 2 + (j - i - 1);
    endfunction

    logic [MATRIX_BITS - 1 : 0] matrix_next;
    logic [WAY_IDX_WIDTH - 1 : 0] lru_way_comb;

    always_comb begin
        if (WAYS == 1) begin
            lru_way_comb = '0;
            matrix_next  = '0;
        end else begin
            logic [WAYS - 1:0] is_lru;
            logic [WAY_IDX_WIDTH-1:0] update_way;

            // Determine the way to be updated
            if (en_i) begin
                if (hit_i)
                    update_way = hit_way_i;
                else
                    update_way = lru_way_comb; // if miss - use current LRU way for update
            end else begin
                update_way = '0;
            end

            // Matrix next state calculation
            matrix_next = matrix_ff;
            if (en_i) begin
                for (int i = 0; i < WAYS - 1; i++) begin
                    for (int j = i + 1; j < WAYS; j++) begin
                        int idx;
                        idx = get_index(i, j);
                        if (i == update_way)
                            matrix_next[idx] = 1'b1;   // update_way is newer than j
                        else if (j == update_way)
                            matrix_next[idx] = 1'b0;   // i is older than update_way
                    end
                end
            end

            // Make desicion (find LRU way)
            for (int w = 0; w < WAYS; w++) begin
                logic less_than_all = 1'b1;
                for (int j = 0; j < WAYS; j++) begin
                    if (j != w) begin
                        logic bit_val;

                        if (w < j) begin
                            bit_val = matrix_ff[get_index(w, j)];
                        end else begin
                            bit_val = ~matrix_ff[get_index(j, w)]; // Assym access
                        end

                        if (bit_val == 1'b1) begin
                            less_than_all = 1'b0;   // w is newer than j -> w is not an LRU way
                        end
                    end
                end
                is_lru[w] = less_than_all;
            end

            // Priority encoder that chooses the first LRU way found
            lru_way_comb = '0;
            for (int w = 0; w < WAYS; w++) begin
                if (is_lru[w]) begin
                    lru_way_comb = w[WAY_IDX_WIDTH - 1 : 0];
                    break;
                end
            end
        end
    end

    assign lru_way_o = lru_way_comb;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            matrix_ff <= '0;
        end else begin
            matrix_ff <= matrix_next;
        end
    end

endmodule
