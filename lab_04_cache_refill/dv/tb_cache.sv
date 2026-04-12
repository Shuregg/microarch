import cache_param_pkg::*;

`include "cache_if.sv"

module tb_cache();

    `define STRINGIFY(DEFINE) `"DEFINE`"

    parameter  CLK_PERIOD = 1;
    parameter  RTL_READ_LATENCY = 2;

    typedef struct packed {
        logic [TAG_WIDTH  - 1 : 0] tag;
        logic [DATA_WIDTH - 1 : 0] data;
    } set_t;


    // TB variables
    logic [CELL_AMOUNT - 1 : 0][WAYS - 1 : 0] expected_valids;
    set_t [CELL_AMOUNT - 1 : 0][WAYS - 1 : 0] expected_cells;


    int unsigned error_cnt = 0;
    bit          is_hit_valid_timeout = 0;

    logic                      clk;
    logic                      rstn;
    logic                      valid;
    logic [TAG_WIDTH  - 1 : 0] tag;
    logic [SET_WIDTH  - 1 : 0] set;
    logic [DATA_WIDTH - 1 : 0] data_exp;
    logic [DATA_WIDTH - 1 : 0] data_rec;
    logic                      hit_exp;
    logic                      hit_rec;

    string cache_ini_file = `STRINGIFY(`CACHE_INI_FILE);

    mem_list_gen #(TAG_WIDTH, DATA_WIDTH, CELL_AMOUNT, WAYS) mem_list_gen_h;

    // Interface signals
    cache_if #(ADDR_WIDTH, DATA_WIDTH) cache_if_h (
        .clk  (clk),
        .rstn (rstn)
    );

    virtual cache_if #(ADDR_WIDTH, DATA_WIDTH) cache_vif_h;

    // DUT
    cache_top #(
        .SETS        (SETS),
        .WAYS        (WAYS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) u_cache_top (
        .clk_i          (cache_if_h.clk),
        .rstn_i         (cache_if_h.rstn),

        .s_valid_i      (cache_if_h.s_valid),
        .s_ready_o      (cache_if_h.s_ready),

        .m_valid_o      (cache_if_h.m_valid),
        .m_ready_i      (cache_if_h.m_ready),

        .addr_i         (cache_if_h.addr),
        .data_o         (cache_if_h.data),
        .hit_valid_o    (cache_if_h.hit_valid),
        .hit_o          (cache_if_h.hit),

        .ext_mem_req_o  (cache_if_h.ext_mem_req),
        .ext_mem_addr_o (cache_if_h.ext_mem_addr),
        .ext_mem_data_i (cache_if_h.ext_mem_data),
        .ext_mem_ack_i  (cache_if_h.ext_mem_ack)
    );

    task automatic reset_gen();
        rstn <= 1'b0;
        #(5*CLK_PERIOD);
        rstn <= 1'b1;
    endtask : reset_gen

    task automatic compare_hit_and_data(
        logic                      hit_rec,
        logic                      hit_exp,
        logic [DATA_WIDTH - 1 : 0] data_rec,
        logic [DATA_WIDTH - 1 : 0] data_exp
    );
        if(hit_rec === hit_exp) begin
            $display("[%0t] Right 'hit_o'  value. Received: %0b",
                $time(), hit_rec);
            if(hit_rec) begin
                if(data_rec === data_exp) begin
                    $display("[%0t] Right 'data_o' value. Received: 0x%x",
                        $time(), data_rec);
                end else begin
                    error_cnt++;
                    $error("[%0t] Wrong 'data_o' value. Received: 0x%x, Expected: 0x%x (#%0d)",
                        $time(), data_rec, data_exp, error_cnt);
                end
            end
        end else begin
            error_cnt++;
            $error("[%0t] Wrong 'hit_o' value. Received = %0b, expected = %0b. (#%0d)",
                $time(), hit_rec, hit_exp, error_cnt);
       end
    endtask : compare_hit_and_data

    task automatic check_cache_hit();
        for(int unsigned i = 0; i < SETS; i++) begin
            for(int unsigned j = 0; j < WAYS; j++) begin
                int unsigned cell_idx = (i * WAYS + j);
                $display("");
                set      = i;
                tag      = expected_cells[i][j].tag;
                data_exp = expected_cells[i][j].data;
                valid    = expected_valids[i][j];
                hit_exp  = valid;

                if(SETS != 1)
                    cache_vif_h.addr <= {tag, set};
                else
                    cache_vif_h.addr <= tag;

                repeat(RTL_READ_LATENCY)
                    @(posedge cache_vif_h.clk);
                is_hit_valid_timeout = 0;
                fork
                    fork
                        wait(cache_vif_h.hit_valid === 1'b1);
                        begin
                            repeat(4)
                                @(posedge cache_vif_h.clk)
                            is_hit_valid_timeout = 1;
                        end
                    join_any
                    disable fork;
                join

                @(negedge cache_vif_h.clk);
                hit_rec  = cache_vif_h.hit;
                data_rec = cache_vif_h.data;

                if(is_hit_valid_timeout) begin
                    error_cnt++;
                    $error("[%0t] Cannot wait for high value of 'hit_valid_o'. Received: %0b. (#%0d)",
                        $time(), cache_vif_h.hit_valid, error_cnt);
                end else begin
                    compare_hit_and_data(hit_rec, hit_exp, data_rec, data_exp);
                end
            end
        end
    endtask : check_cache_hit

   task automatic check_cache_miss(int unsigned checks = 10);
        for(int unsigned set = 0; set < SETS; set++) begin
            for(int i = 0; i < checks; i++) begin
                $display("");
                rand_tag : assert(std::randomize(tag));
                hit_exp = 0;
                for(int j = 0; j < CELL_AMOUNT; j++) begin
                    bit tag_match = 0;
                    for(int k = 0; k < WAYS; k++) begin
                        logic [SET_WIDTH  - 1 : 0] set_tmp = i;
                        logic [TAG_WIDTH  - 1 : 0] tag_tmp = expected_cells[j][k].tag;
                        logic [DATA_WIDTH - 1 : 0] dat_tmp = expected_cells[j][k].data;
                        if((tag === tag_tmp) && (j / WAYS == set)) begin
                            hit_exp = 1;
                            data_exp = dat_tmp;
                            tag_match = 1;
                            break;
                        end else begin
                            hit_exp = 0;
                        end
                    end

                end

                cache_vif_h.addr <= {tag, set};
                repeat(RTL_READ_LATENCY)
                    @(posedge cache_vif_h.clk);
                is_hit_valid_timeout = 0;
                fork
                    fork
                        wait(cache_vif_h.hit_valid === 1'b1);
                        #(4 * CLK_PERIOD) is_hit_valid_timeout = 1;
                    join_any
                    disable fork;
                join

                @(negedge cache_vif_h.clk);
                hit_rec  = cache_vif_h.hit;
                data_rec = cache_vif_h.data;

                if(is_hit_valid_timeout) begin
                    error_cnt++;
                    $error("[%0t] Cannot wait for high value of 'hit_valid_o'. Received: %0b. (#%0d)",
                        $time(), cache_vif_h.hit_valid, error_cnt);
                end else begin
                    compare_hit_and_data(hit_rec, hit_exp, data_rec, data_exp);
                end
                if(hit_exp)
                    checks++; // Because we want to check cache misses
            end
        end
    endtask : check_cache_miss

    initial begin : main_tb_proc
        // Connect interface
        cache_vif_h = cache_if_h;

        cache_vif_h.addr <= 0;
        cache_vif_h.addr <= 0;
        cache_vif_h.m_ready <= 1'b1; // Testbench is always ready to receive data
        cache_vif_h.s_valid <= 1'b1; // Testbench always sends valid address

        // Generate cache initialization file
        mem_list_gen_h = new();
        assert(mem_list_gen_h.generate_file(cache_ini_file, "%h", 85));
        mem_list_gen_h.get_generated_cells(expected_valids, expected_cells);

        // Initialize cache memory
        $readmemh(cache_ini_file, u_cache_top.u_cache_sram.sram);
        u_cache_top.u_cache_ctrl.sram_valids_ff = expected_valids;

        // Wait for reset done
        @(negedge cache_vif_h.rstn);
        @(posedge cache_vif_h.rstn);
        repeat(2) @(posedge cache_vif_h.clk);

        // Start checks
        check_cache_hit();
        check_cache_miss();

        // Some drain time
        repeat(10)
            @(posedge cache_vif_h.clk);

        if(error_cnt)
            $display("\n\t\tTEST FAILED! (error counter = %0d)\n", error_cnt);
        else
            $display("\n\t\tTEST PASSED!\n");
        $finish();
    end

    initial begin : reset_gen_proc
        reset_gen();
    end

    initial begin : clk_gen_proc
        clk <= 1'b0;
        forever begin
            #(CLK_PERIOD / 2.0) clk = ~clk;
        end
    end

endmodule : tb_cache

