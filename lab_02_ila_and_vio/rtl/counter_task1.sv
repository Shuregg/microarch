module counter_task1 (
    input  logic       clk_i,
    input  logic       rstn_i,
    output logic [7:0] counter_o
);

    (* MARK_DEBUG = "TRUE" *) logic [7:0] counter_ff;
    
    assign counter_o = counter_ff;
    
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            counter_ff <= '0;
        end else begin
            counter_ff <= counter_ff + 1;
        end
    end

endmodule