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

    mailbox#(axis_in_pkt_t)  axis_in_mbx      = new();
    mailbox#(axis_out_pkt_t) axis_out_ch0_mbx = new();
    mailbox#(axis_out_pkt_t) axis_out_ch1_mbx = new();

    event axis_write_ev;
    event axis_read_ch0_ev;
    event axis_read_ch1_ev;

    int unsigned checks_amount = 50;
    int unsigned checks_proceed = 0;

    bit fifo_predictor_en = 0;

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
        $display("[%0f] Begin AXIS Write transaction 0x%x", $realtime(), p.tdata);
        @(posedge clk);
        m_valid <= 1'b1;
        m_data  <= p.tdata;
        do begin
            @(posedge clk);
        end
        while(!m_ready);
        ->axis_write_ev;
        axis_in_mbx.put(p);

        // Drop.
        m_valid <= 1'b0;
        $display("[%0f] End AXIS Write transaction 0x%x", $realtime(), p.tdata);
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

    function automatic int compare(axis_out_pkt_t rec, axis_out_pkt_t exp);
        bit result = 0;
        result |= (rec.tdata === exp.tdata);
        result |= (rec.tuser === exp.tuser);
        return result;
    endfunction : compare

    function automatic string convert_axis_out2string(axis_out_pkt_t p);
        convert_axis_out2string = $sformatf("\tTs:    %0f\n\ttdata: 0x%x\n\ttuser: %b",
            p.timestamp, p.tdata, p.tuser);
    endfunction : convert_axis_out2string

    task fifo_predictor();
        forever begin
            if(!fifo_predictor_en) begin
                wait(fifo_predictor_en);
            end else begin
                axis_in_pkt_t  p;
                axis_out_pkt_t p0;
                axis_out_pkt_t p1;
                bit            is_timeout = 0;

                fork
                    fork
                        begin
                            fork
                                axis_in_mbx.get(p);
                                axis_out_ch0_mbx.get(p0);
                                axis_out_ch1_mbx.get(p1);
                            join
                        end
                        begin
                            #(10000);
                            is_timeout = 1;
                        end                
                    join_any
                    disable fork;
                join

                if(is_timeout) begin
                    $error("[%0f] timeout inside fifo_predictor", $realtime);
                end else begin
                    axis_out_pkt_t p0_exp;
                    axis_out_pkt_t p1_exp;

                    p0_exp.tdata = p.tdata[2 * DUT_WORD_WIDTH - 1 : DUT_WORD_WIDTH];
                    p0_exp.tuser = 2'b01;

                    p1_exp.tdata = p.tdata[DUT_WORD_WIDTH - 1 : 0];
                    p1_exp.tuser = (p0.timestamp == p1.timestamp) ? p0_exp.tuser : ~(p0_exp.tuser);

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
                    checks_proceed++;
                end
            end
        end
    endtask : fifo_predictor

    // Basic test
    task basic_test();
        fifo_predictor_en = 1;
        repeat(checks_amount) begin
            axis_in_pkt_t p;
            void'(std::randomize(p));
            axis_write(p);
            repeat($urandom_range(0, 3))
                @(posedge clk);
        end

        wait(checks_proceed >= checks_amount);
        fifo_predictor_en = 0;

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

    initial begin : axis_out_ch_0_monitor_proc
        forever begin
            axis_out_pkt_t p;
            axis_out_monitor(p, s_valid_ch0, s_ready_ch0, s_data_ch0, s_user, 0);
            ->axis_read_ch0_ev;
            axis_out_ch0_mbx.put(p);
        end
    end

    initial begin : axis_out_ch_1_monitor_proc
        forever begin
            axis_out_pkt_t p;
            axis_out_monitor(p, s_valid_ch1, s_ready_ch1, s_data_ch1, s_user, 1);
            ->axis_read_ch1_ev;
            axis_out_ch1_mbx.put(p);
        end
    end

    initial begin : fifo_predictor_proc
        fifo_predictor();
    end

    initial begin : tests_proc
        // Reset
        reset_wait();

        // Tests
        basic_test ();
        $finish();
    end

endmodule : testbench
