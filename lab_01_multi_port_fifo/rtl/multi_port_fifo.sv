module multi_port_fifo#(
    parameter WORD_WIDTH = 32,
    parameter FIFO_DEPTH = 8
) (

    input  logic aclk_i,
    input  logic aresetn_i,

    // AXI-Stream Master
    input  logic [WORD_WIDTH * 2 - 1 : 0] tdata_i,
    input  logic                          tvalid_i,
    output logic                          tready_o,

    // AXI-Stream Slave channel 0
    output logic [WORD_WIDTH - 1 : 0]     tdata_ch0_o,
    output logic                          tvalid_ch0_o,
    input  logic                          tready_ch0_i,

    // AXI-Stream Slave channel 1
    output logic [WORD_WIDTH - 1 : 0]     tdata_ch1_o,
    output logic                          tvalid_ch1_o,
    input  logic                          tready_ch1_i,

    // Read channel priority
    output logic [1:0]                    tuser_o
);

    // ------------------------------
    // -- Local Signals Declaration
    // ------------------------------

    logic [FIFO_DEPTH-1 : 0][WORD_WIDTH-1 : 0] buff_ch0;
    logic [FIFO_DEPTH-1 : 0][WORD_WIDTH-1 : 0] buff_ch1;

    logic [$clog2(FIFO_DEPTH)-1 : 0] w_ptr_ff;
    logic [$clog2(FIFO_DEPTH)-1 : 0] r_ptr_ch0_ff;
    logic [$clog2(FIFO_DEPTH)-1 : 0] r_ptr_ch1_ff;

    logic [$clog2(FIFO_DEPTH)-1 : 0] w_ptr_next;
    logic [$clog2(FIFO_DEPTH)-1 : 0] r_ptr_ch0_next;
    logic [$clog2(FIFO_DEPTH)-1 : 0] r_ptr_ch1_next;

    logic [$clog2(FIFO_DEPTH + 1)-1 : 0] data_cnt_ch0_ff;
    logic [$clog2(FIFO_DEPTH + 1)-1 : 0] data_cnt_ch1_ff;
    logic [$clog2(FIFO_DEPTH + 1)-1 : 0] data_cnt_ch0_next;
    logic [$clog2(FIFO_DEPTH + 1)-1 : 0] data_cnt_ch1_next;

    logic is_empty_ch0;
    logic is_empty_ch1;
    logic is_almost_empty_ch0;
    logic is_almost_empty_ch1;

    logic is_full_ch0;
    logic is_full_ch1;
    logic is_almost_full_ch0;
    logic is_almost_full_ch1;
    logic is_both_full;

    // Onehot read priority
    logic [1:0] read_priority_ff;
    logic [1:0] read_priority_next;

    logic fifo_we;

    logic valid_ch0_next;
    logic valid_ch1_next;

    // A signal for parallel writing and reading
    logic fifo_is_freeing_up;
    logic fifo_single_read;
    logic fifo_double_read;

    // ------------------------------
    // -- Assertion properties
    // ------------------------------

    w_ptr_ff_val : assert property(
        @(posedge aclk_i) disable iff (!aresetn_i)
        w_ptr_ff < FIFO_DEPTH
    ) else $error("w_ptr_ff BEQ FIFO_DEPTH: %0d >= %0d", w_ptr_ff, FIFO_DEPTH);

    data_cnt_ch0_ff_val : assert property(
        @(posedge aclk_i) disable iff (!aresetn_i)
        data_cnt_ch0_ff <= FIFO_DEPTH
    ) else $error("data_cnt_ch0_ff Bigger than FIFO_DEPTH: %0d > %0d", data_cnt_ch0_ff, FIFO_DEPTH);

    data_cnt_ch1_ff_val : assert property(
        @(posedge aclk_i) disable iff (!aresetn_i)
        data_cnt_ch1_ff <= FIFO_DEPTH
    ) else $error("data_cnt_ch1_ff Bigger than FIFO_DEPTH: %0d > %0d", data_cnt_ch1_ff, FIFO_DEPTH);

    r_ptr_ch0_ff_val : assert property(
        @(posedge aclk_i) disable iff (!aresetn_i)
        r_ptr_ch0_ff < FIFO_DEPTH
    ) else $error("r_ptr_ch0_ff BEQ FIFO_DEPTH: %0d >= %0d", r_ptr_ch0_ff, FIFO_DEPTH);

    r_ptr_ch1_ff_val : assert property(
        @(posedge aclk_i) disable iff (!aresetn_i)
        r_ptr_ch1_ff < FIFO_DEPTH
    ) else $error("r_ptr_ch1_ff BEQ FIFO_DEPTH: %0d >= %0d", r_ptr_ch1_ff, FIFO_DEPTH);

    read_priority_ff_val : assert property(
        @(posedge aclk_i) disable iff (!aresetn_i)
        $onehot(read_priority_ff)
    ) else $error("read_priority_ff (tuser_o) == 2'b11!");

    // ------------------------------
    // -- Write logic
    // ------------------------------

    assign is_full_ch0 = (data_cnt_ch0_ff == FIFO_DEPTH);
    assign is_full_ch1 = (data_cnt_ch1_ff == FIFO_DEPTH);

    assign is_both_full = is_full_ch0 && is_full_ch1;

    assign is_almost_full_ch0 = (data_cnt_ch0_ff == FIFO_DEPTH - 1);
    assign is_almost_full_ch1 = (data_cnt_ch1_ff == FIFO_DEPTH - 1);

    assign tready_o = (!is_full_ch0 && !is_full_ch1) || fifo_is_freeing_up;
    assign fifo_we = tvalid_i && tready_o;

    always_ff @(posedge aclk_i) begin : write_logic
        if(!aresetn_i) begin
            buff_ch0 <= '0;
            buff_ch1 <= '0;
            w_ptr_ff <= '0;
        end else if(fifo_we) begin
            {buff_ch1[w_ptr_ff], buff_ch0[w_ptr_ff]} <= tdata_i;
            w_ptr_ff <= w_ptr_next;
        end
    end

    always_comb begin : next_w_ptr_logic
        if(w_ptr_ff == FIFO_DEPTH - 1)
            w_ptr_next = 0;
        else
            w_ptr_next = w_ptr_ff + 1;
    end

    // ------------------------------
    // -- Read logic
    // ------------------------------

    assign is_empty_ch0 = (data_cnt_ch0_ff == 0);
    assign is_empty_ch1 = (data_cnt_ch1_ff == 0);

    assign is_almost_empty_ch0 = (data_cnt_ch0_ff == 1);
    assign is_almost_empty_ch1 = (data_cnt_ch1_ff == 1);

    assign tuser_o = read_priority_ff;

    assign fifo_re_ch0 = tvalid_ch0_o && tready_ch0_i;
    assign fifo_re_ch1 = tvalid_ch1_o && tready_ch1_i;

    assign fifo_single_read = fifo_re_ch0 ^ fifo_re_ch1;
    assign fifo_double_read = fifo_re_ch0 & fifo_re_ch1;

    assign fifo_is_freeing_up = fifo_double_read || (fifo_single_read && !is_both_full);

    assign tdata_ch0_o = buff_ch0[r_ptr_ch0_ff];
    assign tdata_ch1_o = buff_ch1[r_ptr_ch1_ff];
    always_comb begin
        if(fifo_re_ch0) begin
            if(fifo_re_ch1) begin
                read_priority_next = read_priority_ff;
            end else begin
                read_priority_next = ~read_priority_ff;
            end
        end else begin
            if(fifo_re_ch1)
                read_priority_next = ~read_priority_ff;
            else
                read_priority_next = read_priority_ff;
        end
    end
    always_ff @(posedge aclk_i) begin : read_priority_ff_logic
        if(!aresetn_i) begin
            read_priority_ff <= 2'b01;
        end else begin
            read_priority_ff <= read_priority_next;
        end
    end

    // ------------------------------
    // -- Channel 0
    // ------------------------------

    assign tvalid_ch0_o = !is_empty_ch0;

    always_comb begin
        if(fifo_re_ch0) begin
            if(r_ptr_ch0_ff == FIFO_DEPTH - 1)
                r_ptr_ch0_next = '0;
            else
                r_ptr_ch0_next = r_ptr_ch0_ff + 1;
        end else begin
            r_ptr_ch0_next = r_ptr_ch0_ff;
        end
    end
    always_ff @(posedge aclk_i) begin
        if(!aresetn_i)
            r_ptr_ch0_ff <= '0;
        else
            r_ptr_ch0_ff <= r_ptr_ch0_next;
    end

    always_comb begin
        if(fifo_re_ch0) begin
            if(!fifo_we)
                data_cnt_ch0_next = is_empty_ch0 ? data_cnt_ch0_ff : data_cnt_ch0_ff - 1;
            else
                data_cnt_ch0_next = data_cnt_ch0_ff;
        end else begin
            if(fifo_we)
                data_cnt_ch0_next = is_full_ch0 ? data_cnt_ch0_ff : data_cnt_ch0_ff + 1;
            else
                data_cnt_ch0_next = data_cnt_ch0_ff;
        end
    end
    always_ff @(posedge aclk_i) begin
        if(!aresetn_i)
            data_cnt_ch0_ff <= '0;
        else
            data_cnt_ch0_ff <= data_cnt_ch0_next;
    end

    // ------------------------------
    // -- Channel 1
    // ------------------------------

    assign tvalid_ch1_o = !is_empty_ch1;

    always_comb begin
        if(fifo_re_ch1) begin
            if(r_ptr_ch1_ff == FIFO_DEPTH - 1)
                r_ptr_ch1_next = '0;
            else
                r_ptr_ch1_next = r_ptr_ch1_ff + 1;
        end else begin
            r_ptr_ch1_next = r_ptr_ch1_ff;
        end
    end
    always_ff @(posedge aclk_i) begin
        if(!aresetn_i)
            r_ptr_ch1_ff <= '0;
        else
            r_ptr_ch1_ff <= r_ptr_ch1_next;
    end

    always_comb begin
        if(fifo_re_ch1) begin
            if(!fifo_we)
                data_cnt_ch1_next = is_empty_ch1 ? data_cnt_ch1_ff : data_cnt_ch1_ff - 1;
            else
                data_cnt_ch1_next = data_cnt_ch1_ff;
        end else begin
            if(fifo_we)
                data_cnt_ch1_next = is_full_ch1 ? data_cnt_ch1_ff : data_cnt_ch1_ff + 1;
            else
                data_cnt_ch1_next = data_cnt_ch1_ff;
        end
    end
    always_ff @(posedge aclk_i) begin
        if(!aresetn_i)
            data_cnt_ch1_ff <= '0;
        else
            data_cnt_ch1_ff <= data_cnt_ch1_next;
    end
endmodule : multi_port_fifo

