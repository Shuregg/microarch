`include "cache_if.sv"

module tb_cache();

    `define STRINGIFY(DEFINE) `"DEFINE`"

    parameter  CLK_PERIOD = 1;
    parameter  RTL_READ_LATENCY = 2;

    `ifdef DIRECT_MAPPED_CACHE
        parameter  SETS = 8;
        parameter  WAYS = 1;
    `elsif FOUR_WAY_SET_ASSOCIATIVE_CACHE
        parameter  SETS = 2;
        parameter  WAYS = 4;
    `elsif FULLY_ASSOCIATIVE_CACHE
        parameter  SETS = 1;
        parameter  WAYS = 8;
    `endif

    parameter  ADDR_WIDTH        = 32;
    parameter  DATA_WIDTH        = 32;
    parameter  BYTE_OFFSET_WIDTH = 2;

    localparam ADDR_WIDTH_CUT    = (ADDR_WIDTH - BYTE_OFFSET_WIDTH);
    localparam CELL_AMOUNT       = SETS;
    localparam VALID_WIDTH       = 1;
    localparam SET_WIDTH         = $clog2(SETS);
    localparam TAG_WIDTH         = ADDR_WIDTH_CUT - SET_WIDTH;
    localparam CELL_WIDTH        = TAG_WIDTH + DATA_WIDTH;

    typedef struct packed {
        logic                      valid;
        logic [TAG_WIDTH  - 1 : 0] tag;
        logic [DATA_WIDTH - 1 : 0] data;
    } set_t;


    // TB variables
    logic [CELL_AMOUNT - 1 : 0] expected_valids;
    set_t expeced_cells[CELL_AMOUNT];

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

    mem_list_gen #(TAG_WIDTH, DATA_WIDTH, CELL_AMOUNT) mem_list_gen_h;

    // Interface signals
    cache_if #(ADDR_WIDTH_CUT, DATA_WIDTH) cache_if_h (
        .clk  (clk),
        .rstn (rstn)
    );

    virtual cache_if #(ADDR_WIDTH_CUT, DATA_WIDTH) cache_vif_h;

    // DUT
    cache #(
        .SETS        (SETS),
        .WAYS        (WAYS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH_CUT)
    ) u_cache (
        .clk_i       (clk),
        .rstn_i      (rstn),
        .addr_i      (cache_if_h.addr),
        .data_o      (cache_if_h.data),
        .hit_valid_o (cache_if_h.hit_valid),
        .hit_o       (cache_if_h.hit)
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
                tag      = expeced_cells[cell_idx].tag;
                data_exp = expeced_cells[cell_idx].data;
                valid    = expected_valids;
                hit_exp  = valid[cell_idx];

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
                    logic [TAG_WIDTH  - 1 : 0] set_tmp = i;
                    logic [DATA_WIDTH - 1 : 0] tag_tmp = expeced_cells[j].tag;
                    logic [SET_WIDTH  - 1 : 0] dat_tmp = expeced_cells[j].data;
                    if((tag === tag_tmp) && (j / WAYS == set)) begin
                        hit_exp = 1;
                        data_exp = dat_tmp;
                        break;
                    end else begin
                        hit_exp = 0;
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

        // Generate cache initialization file
        mem_list_gen_h = new();
        assert(mem_list_gen_h.generate_file(cache_ini_file, "%h", 1));
        mem_list_gen_h.get_generated_cells(expected_valids, expeced_cells);

        // Initialize cache memory
        $readmemh(cache_ini_file, u_cache.sram);

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
