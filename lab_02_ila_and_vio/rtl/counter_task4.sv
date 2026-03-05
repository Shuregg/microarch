module counter_task4 (
  input  logic clk_i,
  input  logic rstn_i,

  (* MARK_DEBUG = "TRUE" *) input  logic [7:0] counter1_max_i,
  (* MARK_DEBUG = "TRUE" *) input  logic [7:0] counter2_max_i,

  (* MARK_DEBUG = "TRUE" *) output logic [7:0] counter1_o,
  (* MARK_DEBUG = "TRUE" *) output logic [7:0] counter2_o
);

  logic [7:0] counter1_ff;
  logic [7:0] counter2_ff;

  always_ff @( posedge clk_i or negedge rstn_i  ) begin
    if (~rstn_i)
      counter1_ff <= '0;
    else if (counter1_ff >= counter1_max_i)
      counter1_ff <= '0;
    else
      counter1_ff <= counter1_ff + 1;
  end

  always_ff @( posedge clk_i or negedge rstn_i  ) begin
    if (~rstn_i)
      counter2_ff <= '0;
    else if ( (counter2_ff >= counter2_max_i) && (counter1_ff >= counter1_max_i) )
      counter2_ff <= '0;
    else if (counter1_ff >= counter1_max_i)
      counter2_ff <= counter2_ff + 1;
  end

  assign counter1_o = counter1_ff;
  assign counter2_o = counter2_ff;

endmodule
