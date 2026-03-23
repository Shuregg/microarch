module testbench();

    // ----------------------------------------
    // -- Parameters
    // ----------------------------------------

    parameter CLK_PERIOD = 10;
    parameter DUT_WORD_WIDTH = 32;
    parameter DUT_FIFO_DEPTH = 8;

    // ----------------------------------------
    // -- Type defines
    // ----------------------------------------

    typedef struct {
        rand logic [2 * DUT_WORD_WIDTH - 1 : 0] tdata;
    } axis_in_pkt_t;

    typedef struct {
        rand logic [DUT_WORD_WIDTH - 1 : 0] tdata;
        rand logic [1:0]                    tuser;
        realtime                            timestamp;
    } axis_out_pkt_t;

    typedef enum int { NONE, CH0, CH1, BOTH_WITH_CH0_OLDEST, BOTH_WITH_CH1_OLDEST } read_type_e;

    // ----------------------------------------
    // -- TB Variables
    // ----------------------------------------

    logic                            clk;
    logic                            rst_n;

    logic [2 * DUT_WORD_WIDTH-1 : 0] m_data;
    logic                            m_valid;
    logic                            m_ready;

    logic [DUT_WORD_WIDTH-1 : 0]     s_data_ch0;
    logic                            s_valid_ch0;
    logic                            s_ready_ch0;

    logic [DUT_WORD_WIDTH-1 : 0]     s_data_ch1;
    logic                            s_valid_ch1;
    logic                            s_ready_ch1;

    logic [1:0]                      s_user;

    mailbox#(axis_out_pkt_t) axis_in_ch0_mbx  = new();
    mailbox#(axis_out_pkt_t) axis_in_ch1_mbx  = new();
    mailbox#(axis_out_pkt_t) axis_out_ch0_mbx = new();
    mailbox#(axis_out_pkt_t) axis_out_ch1_mbx = new();

    event axis_write_ev;
    event axis_read_ch0_ev;
    event axis_read_ch1_ev;

    int unsigned fast_mode_tr_amount = 50;
    int unsigned slow_mode_tr_amount = 50;
    int unsigned checks_amount = fast_mode_tr_amount + slow_mode_tr_amount;
    int unsigned checks_proceed = 0;

    bit is_test_timeouted       = 0;
    bit axis_out_ch0_monitor_en = 0;
    bit axis_out_ch1_monitor_en = 0;

    read_type_e curr_read_op = NONE;
    read_type_e prev_read_op = NONE;

    logic [1:0]   tuser_expected = 2'b01;
    axis_in_pkt_t axis_in_pkt_prev;

    bit first_check = 1;

    // ----------------------------------------
    // -- DUT instance
    // ----------------------------------------

    multi_port_fifo#(
        .WORD_WIDTH(DUT_WORD_WIDTH),
        .FIFO_DEPTH(DUT_FIFO_DEPTH)
    ) DUT (
        .aclk_i       (clk),
        .aresetn_i    (rst_n),
        .tdata_i      (m_data),
        .tvalid_i     (m_valid),
        .tready_o     (m_ready),
        .tdata_ch0_o  (s_data_ch0),
        .tvalid_ch0_o (s_valid_ch0),
        .tready_ch0_i (s_ready_ch0),
        .tdata_ch1_o  (s_data_ch1),
        .tvalid_ch1_o (s_valid_ch1),
        .tready_ch1_i (s_ready_ch1),
        .tuser_o      (s_user)
    );

    // ----------------------------------------
    // -- Functions & Tasks
    // ----------------------------------------

    task automatic reset_gen();
        rst_n <= 1'b0;
        #(5*CLK_PERIOD);
        rst_n <= 1'b1;
    endtask : reset_gen

    task automatic reset_wait();
        wait(!rst_n);
        m_valid <= 1'b0;
        wait(rst_n);
    endtask : reset_wait

    task automatic axis_write(axis_in_pkt_t p);
        axis_out_pkt_t axis_in_pkt_ch_0;
        axis_out_pkt_t axis_in_pkt_ch_1;
        realtime ts;
        // $display("[%0f] Begin AXIS Write transaction 0x%x",
            // $realtime(), p.tdata);
        @(posedge clk);
        m_valid <= 1'b1;
        m_data  <= p.tdata;
        do begin
            @(posedge clk);
        end
        while(!m_ready);
        ->axis_write_ev;



        // Drop.
        m_valid <= 1'b0;
        ts = $realtime();
        axis_in_pkt_ch_0.tdata     = p.tdata[DUT_WORD_WIDTH - 1 : 0];
        axis_in_pkt_ch_0.timestamp = ts;
        axis_in_pkt_ch_1.tdata     = p.tdata[2 * DUT_WORD_WIDTH - 1 : DUT_WORD_WIDTH];
        axis_in_pkt_ch_1.timestamp = ts;
        axis_in_ch0_mbx.put(axis_in_pkt_ch_0);
        axis_in_ch1_mbx.put(axis_in_pkt_ch_1);
        $display("[%0f] Proceed AXIS Write transaction 0x%x", ts, p.tdata);
    endtask : axis_write

    task automatic axis_out_monitor(
        output axis_out_pkt_t                 p,
        ref    logic                          tvalid,
        ref    logic                          tready,
        ref    logic [DUT_WORD_WIDTH - 1 : 0] tdata,
        ref    logic [1:0]                    tuser,
        input  bit                            ch_num
    );
        wait(rst_n);
        do begin
            @(posedge clk);
        end while((tvalid & tready) === 0);

        p.timestamp = $realtime();
        p.tdata     = tdata;
        p.tuser     = tuser;
        $display("[%0f] Got handshake for channel %0d: tdata = 0x%x, tuser = 2'b%2b",
            p.timestamp, ch_num, p.tdata, p.tuser);
    endtask : axis_out_monitor

    function automatic int compare(axis_out_pkt_t rec, axis_out_pkt_t exp, bit compare_timestamp=0);
        bit result = 1;
        result &= (rec.tdata === exp.tdata);
        result &= (rec.tuser === exp.tuser);
        if(compare_timestamp)
            result &= (rec.timestamp == exp.timestamp);
        return result;
    endfunction : compare

    function automatic string convert_axis_out2string(axis_out_pkt_t p);
        convert_axis_out2string = $sformatf("\tTs:    %0f\n\ttdata: 0x%x\n\ttuser: %b",
            p.timestamp, p.tdata, p.tuser);
    endfunction : convert_axis_out2string

    task axis_read_ch0(output axis_out_pkt_t p);
        wait(rst_n);
        do begin
            @(posedge clk);
        end while((s_valid_ch0 && s_ready_ch0 && (s_user[0] || (s_valid_ch1 && s_ready_ch1 && s_user[1]))) === 0);
        ->axis_read_ch0_ev;

        p.timestamp = $realtime();
        p.tdata     = s_data_ch0;
        p.tuser     = s_user;
    endtask : axis_read_ch0

    task axis_read_ch1(output axis_out_pkt_t p);
        wait(rst_n);
        do begin
            @(posedge clk);
        end while((s_valid_ch1 && s_ready_ch1 && (s_user[1] || (s_valid_ch0 && s_ready_ch0 && s_user[0]))) === 0);
        ->axis_read_ch1_ev;

        p.timestamp = $realtime();
        p.tdata     = s_data_ch1;
        p.tuser     = s_user;
    endtask : axis_read_ch1

    task automatic predict_fifo(input bit parallel_reading);
        case(prev_read_op)
            CH0: begin
                curr_read_op = parallel_reading ? BOTH_WITH_CH1_OLDEST : CH1;
                tuser_expected = 2'b10;
            end
            CH1: begin
                curr_read_op = parallel_reading ? BOTH_WITH_CH0_OLDEST : CH0;
                tuser_expected = 2'b01;
            end
            NONE,
            BOTH_WITH_CH0_OLDEST: begin
                curr_read_op = parallel_reading ? BOTH_WITH_CH0_OLDEST : CH0;
                tuser_expected = 2'b01;
            end
            BOTH_WITH_CH1_OLDEST: begin
                curr_read_op = parallel_reading ? BOTH_WITH_CH1_OLDEST : CH1;
                tuser_expected = 2'b10;
            end
        endcase

        case(curr_read_op)
            CH0: begin
                axis_out_pkt_t p;
                axis_out_pkt_t p0;
                axis_out_pkt_t p0_exp;

                $display("[%0f] Begin reading data from channel 0...", $realtime());
                s_ready_ch0 <= 1'b1;
                s_ready_ch1 <= 1'b0;
                axis_read_ch0(p0);
                $display("[%0f] Read  data from channel 0: tdata = 0x%x, tuser = 2'b%2b.",
                    p0.timestamp, p0.tdata, p0.tuser);

                // Catch
                $display("[%0f] Waiting for a packet from 'axis_in_ch0_mbx'...", $realtime());
                axis_in_ch0_mbx.get(p);

                // Predict
                p0_exp.tdata = p.tdata;
                p0_exp.tuser = tuser_expected;

                // Check
                if(compare(p0, p0_exp)) begin
                    $display("[%0f] CH0 Match:\n%s",
                        $realtime(), convert_axis_out2string(p0));
                end else begin
                    $error("[%0f] CH0 Mismatch:\nrec:\n%s\nexp:\n%s",
                        $realtime(), convert_axis_out2string(p0), convert_axis_out2string(p0_exp));
                end
            end
            CH1: begin
                axis_out_pkt_t p;
                axis_out_pkt_t p1;
                axis_out_pkt_t p1_exp;

                $display("[%0f] Begin reading data from channel 1...", $realtime());
                s_ready_ch0 <= 1'b0;
                s_ready_ch1 <= 1'b1;
                axis_read_ch1(p1);
                $display("[%0f] Read  data from channel 1: tdata = 0x%x, tuser = 2'b%2b.",
                    p1.timestamp, p1.tdata, p1.tuser);

                $display("[%0f] Waiting for a packet from 'axis_in_ch1_mbx'...", $realtime());
                axis_in_ch1_mbx.get(p);

                // Predict
                p1_exp.tdata = p.tdata;
                p1_exp.tuser = tuser_expected;

                // Check
                if(compare(p1, p1_exp)) begin
                    $display("[%0f] CH1 Match:\n%s",
                        $realtime(), convert_axis_out2string(p1));
                end else begin
                    $error("[%0f] CH1 Mismatch:\nrec:\n%s\nexp:\n%s",
                        $realtime(), convert_axis_out2string(p1), convert_axis_out2string(p1_exp));
                end
            end
            BOTH_WITH_CH0_OLDEST,
            BOTH_WITH_CH1_OLDEST: begin
                axis_out_pkt_t p0_in;
                axis_out_pkt_t p1_in;
                axis_out_pkt_t p0;
                axis_out_pkt_t p1;
                axis_out_pkt_t p0_exp;
                axis_out_pkt_t p1_exp;

                fork
                    begin
                        $display("[%0f] Waiting for a packet from 'axis_in_ch0_mbx'...", $realtime());
                        axis_in_ch0_mbx.get(p0_in);
                        // $display("[%0f] Packet of 'axis_in_ch0_mbx' has been received.", $realtime());
                    end
                    begin
                        $display("[%0f] Waiting for a packet from 'axis_in_ch1_mbx'...", $realtime());
                        axis_in_ch1_mbx.get(p1_in);
                        // $display("[%0f] Packet of 'axis_in_ch1_mbx' has been received.", $realtime());
                    end
                join

                $display("[%0f] Begin parallel reading from both channels (%s)...",
                    $realtime(), curr_read_op.name());
                s_ready_ch0 <= 1'b1;
                s_ready_ch1 <= 1'b1;
                fork
                    begin
                        axis_read_ch0(p0);
                        $display("[%0f] Read  data from channel 0: tdata = 0x%x, tuser = 2'b%2b",
                            p0.timestamp, p0.tdata, p0.tuser);
                    end
                    begin
                        axis_read_ch1(p1);
                        $display("[%0f] Read  data from channel 1: tdata = 0x%x, tuser = 2'b%2b",
                            p1.timestamp, p1.tdata, p1.tuser);
                    end
                join
                $display("[%0f] End   parallel reading from both channels.",
                    $realtime());

                p0_exp.tdata     = p0_in.tdata;
                p0_exp.tuser     = tuser_expected;
                p0_exp.timestamp = p1.timestamp;

                p1_exp.tdata     = p1_in.tdata;
                p1_exp.tuser     = tuser_expected;
                p1_exp.timestamp = p0.timestamp;

                if(compare(p0, p0_exp)) begin
                    $display("[%0f] CH0 Match:\n%s",
                        $realtime(), convert_axis_out2string(p0));
                end else begin
                    $error("[%0f] CH0 Mismatch:\nrec:\n%s\nexp:\n%s",
                        $realtime(), convert_axis_out2string(p0), convert_axis_out2string(p0_exp));
                end

                if(compare(p1, p1_exp)) begin
                    $display("[%0f] CH1 Match:\n%s",
                        $realtime(), convert_axis_out2string(p1));
                end else begin
                    $error("[%0f] CH1 Mismatch:\nrec:\n%s\nexp:\n%s",
                        $realtime(), convert_axis_out2string(p1), convert_axis_out2string(p1_exp));
                end
            end
            default : $fatal(1, "Wrong 'curr_read_op' value: %s (%0d)",
                curr_read_op.name(), curr_read_op);
        endcase
        s_ready_ch0 <= 1'b0;
        s_ready_ch1 <= 1'b0;
        
        checks_proceed++;
        first_check = 0;
        prev_read_op = curr_read_op;

        $display("\n");
    endtask : predict_fifo

    task automatic fifo_predictor(
        int unsigned parallel_reading_prob=20,
        int unsigned read_clk_delay_change_prob=20,
        int unsigned read_clk_delay_min=0,
        int unsigned read_clk_delay_max=10
    );
        bit parallel_reading;
        int unsigned read_clk_delay = 0;
        int unsigned read_clk_delay_change = 0;

        forever begin
            rand_parallel_reading : assert(std::randomize(parallel_reading) with {
                parallel_reading dist {
                    0 :/ (100 - parallel_reading_prob),
                    1 :/ parallel_reading_prob
                };
            });

            rand_read_clk_delay_change : assert(std::randomize(read_clk_delay_change) with {
                read_clk_delay_change dist {
                    0 :/ (100 - read_clk_delay_change_prob),
                    1 :/ read_clk_delay_change_prob
                };
            });

            if(read_clk_delay_change) begin
                rand_read_clk_delay : assert(std::randomize(read_clk_delay) with {
                    read_clk_delay inside {[read_clk_delay_min:read_clk_delay_max]};
                });
            end

            wait(rst_n);
            repeat(read_clk_delay)
                @(posedge clk);
            predict_fifo(parallel_reading);
        end
    endtask : fifo_predictor

    // Basic test
    task basic_test();
        fork begin

            repeat(slow_mode_tr_amount) begin
                axis_in_pkt_t p;
                int unsigned write_delay;
                assert(std::randomize(write_delay) with {
                    write_delay inside {[0 : (2 * DUT_FIFO_DEPTH)]}; });
                assert(std::randomize(p));
                axis_write(p);
                repeat(write_delay)
                    @(posedge clk);
            end

            repeat(fast_mode_tr_amount) begin
                axis_in_pkt_t p;
                int unsigned write_delay;
                assert(std::randomize(p));
                axis_write(p);
            end
        end join_none

        wait(checks_proceed >= checks_amount);

        repeat(50)
            @(posedge clk);
    endtask : basic_test

    // ----------------------------------------
    // -- Processes
    // ----------------------------------------

    initial begin : s_ready_ch_0_change_proc
        s_ready_ch0 <= 1'b1;
        `ifdef RAND_TREADY
            forever begin
                repeat($urandom_range(10, 20))
                    @(posedge clk);
                s_ready_ch0 <= ~s_ready_ch0;
            end
        `endif
    end

    initial begin : s_ready_ch_1_change_proc
        s_ready_ch1 <= 1'b1;
        `ifdef RAND_TREADY
            forever begin
                repeat($urandom_range(10, 20))
                    @(posedge clk);
                s_ready_ch1 <= ~s_ready_ch1;
            end
        `endif
    end

    initial begin : reset_gen_proc
        reset_gen();
    end

    initial begin : clk_gen_proc
        clk <= 1'b0;
        forever begin
            #(CLK_PERIOD/2) clk = ~clk;
        end
    end

    initial begin : fifo_predictor_proc
        fifo_predictor();
    end

    initial begin : tests_proc
        // Reset
        reset_wait();

        // Tests
        fork
            fork
                basic_test();
                begin
                    #(1000000);
                    is_test_timeouted = 1;
                end
            join_any
            disable fork;
            if(is_test_timeouted)
                $error("[%0f] Test timeout.", $realtime());
        join
        $finish();
    end

endmodule : testbench

