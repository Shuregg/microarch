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

    logic is_full_ch0;
    logic is_full_ch1;

    // Onehot read priority
    logic [1:0] read_priority_ff;
    logic [1:0] read_priority_next;

    logic fifo_we;
    logic fifo_r_op_ch0;
    logic fifo_r_op_ch1;

    logic [WORD_WIDTH-1 : 0] data_ch0_ff;
    logic [WORD_WIDTH-1 : 0] data_ch1_ff;

    // logic valid_ch0_ff;
    // logic valid_ch1_ff;
    logic valid_ch0_next;
    logic valid_ch1_next;

    // A signal for parallel writing and reading
    logic fifo_is_freeing_up;

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

    /*
    uneven_fifo_filling : assert property(
        @(posedge aclk_i) disable iff (!aresetn_i)
        !(!is_empty_ch0 && is_empty_ch1)
    ) else $error("Channel 0 is not empty but channel 1 is. You must follow \
        the rules for reading fifo based on the 'tuser_o' signal");
    */

    // ------------------------------
    // -- Write logic
    // ------------------------------

    assign is_full_ch0 = (data_cnt_ch0_ff == FIFO_DEPTH);
    assign is_full_ch1 = (data_cnt_ch1_ff == FIFO_DEPTH);

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

    // assign tvalid_ch0_o = valid_ch0_ff;
    // assign tvalid_ch1_o = valid_ch1_ff;

    // assign tdata_ch0_o = data_ch0_ff;
    // assign tdata_ch1_o = data_ch1_ff;

    assign tuser_o = read_priority_ff;

    // assign fifo_re_ch0 = !is_empty_ch0 && tready_ch0_i && (read_priority_ff[0]);
    // assign fifo_re_ch1 = !is_empty_ch1 && tready_ch1_i && (read_priority_ff[1] || fifo_re_ch0);
    // Additional condition for parallel                                       ^            ^
    // reading from both channels                                              |____________|

    assign fifo_re_ch0 = tvalid_ch0_o && tready_ch0_i && (tuser_o[0] || (!is_empty_ch1 && tready_ch1_i && tuser_o[1]));
    assign fifo_re_ch1 = tvalid_ch1_o && tready_ch1_i && (tuser_o[1] || (!is_empty_ch0 && tready_ch0_i && tuser_o[0]));

    assign fifo_r_op_ch0 = !is_empty_ch0 && tready_ch0_i && tvalid_ch0_o;
    assign fifo_r_op_ch1 = !is_empty_ch1 && tready_ch1_i && tvalid_ch1_o;

    // Channel 1 always contains newer data than channel 0 (due to specification);
    // FIFO can be written when it is not full and both channels contain same number of unreaded values.
    // assign fifo_is_freeing_up = fifo_re_ch1;
    assign fifo_is_freeing_up = fifo_re_ch1;

    assign tdata_ch0_o = buff_ch0[r_ptr_ch0_ff];
    assign tdata_ch1_o = buff_ch1[r_ptr_ch1_ff];
    always_comb begin
        if(tvalid_ch0_o && tready_ch0_i) begin
            if(tvalid_ch1_o && tready_ch1_i) begin
                read_priority_next = read_priority_ff;
            end else begin
                read_priority_next = ~read_priority_ff;
            end
        end else begin
            if(tvalid_ch1_o && tready_ch1_i)
                read_priority_next = ~read_priority_ff;
            else
                read_priority_next = read_priority_ff;
        end
    end
    always_ff @(posedge aclk_i) begin : read_priority_ff_logic
        if(!aresetn_i) begin
            // data_ch0_ff      <= '0;
            // data_ch1_ff      <= '0;
            read_priority_ff <= 2'b01;
        end else begin
            // data_ch0_ff      <= buff_ch0[r_ptr_ch0_ff];
            // data_ch1_ff      <= buff_ch1[r_ptr_ch1_ff];
            read_priority_ff <= read_priority_next;
        end
    end

    // ------------------------------
    // -- Channel 0
    // ------------------------------

    // assign valid_ch0_next = !is_empty_ch0;
    // always_ff @(posedge aclk_i) begin : ch0_valid_logic
    //     if(!aresetn_i)
    //         valid_ch0_ff <= 1'b0;
    //     else
    //         valid_ch0_ff <= valid_ch0_next;
    // end

    assign tvalid_ch0_o = !is_empty_ch0;
    always_comb begin
        if(tvalid_ch0_o && tready_ch0_i) begin
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
        if(tvalid_ch0_o && tready_ch0_i) begin
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

    // assign valid_ch1_next = !is_empty_ch1;
    assign tvalid_ch1_o = !is_empty_ch1;
    // always_ff @(posedge aclk_i) begin : ch1_valid_logic
    //     if(!aresetn_i)
    //         valid_ch1_ff <= 1'b0;
    //     else
    //         valid_ch1_ff <= valid_ch1_next;
    // end

    always_comb begin
        if(tvalid_ch1_o && tready_ch1_i) begin
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
        if(tvalid_ch1_o && tready_ch1_i) begin
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
