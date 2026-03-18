module tb_cache();

    `define STRINGIFY(DEFINE) `"DEFINE`"

    parameter  CLK_PERIOD        = 1;
    parameter  SETS              = 8;
    parameter  WAYS              = 1;
    parameter  ADDR_WIDTH        = 32;
    parameter  DATA_WIDTH        = 32;
    parameter  BYTE_OFFSET_WIDTH = 2;

    localparam ADDR_WIDTH_CUT    = (ADDR_WIDTH - BYTE_OFFSET_WIDTH);
    localparam CELL_AMOUNT       = SETS * WAYS;
    localparam VALID_WIDTH       = 1;
    localparam SET_WIDTH         = $clog2(SETS);
    localparam TAG_WIDTH         = ADDR_WIDTH_CUT - SET_WIDTH;
    localparam CELL_WIDTH        = VALID_WIDTH + TAG_WIDTH + DATA_WIDTH;

    typedef struct packed {
        logic                      valid;
        logic [TAG_WIDTH  - 1 : 0] tag;
        logic [DATA_WIDTH - 1 : 0] data;
    } set_t;


    // Interface signals
    logic clk;
    logic rstn;
    logic [ADDR_WIDTH_CUT - 1 : 0] addr_cut;
    logic [DATA_WIDTH     - 1 : 0] data;
    logic hit_valid;
    logic hit;

    // TB variables
    set_t expeced_cells[CELL_AMOUNT];

    int unsigned error_cnt = 0;
    bit          is_hit_valid_timeout = 0;

    logic                      valid;
    logic [TAG_WIDTH  - 1 : 0] tag;
    logic [SET_WIDTH  - 1 : 0] set;
    logic [DATA_WIDTH - 1 : 0] data_exp;
    logic [DATA_WIDTH - 1 : 0] data_rec;
    logic                      hit_exp;
    logic                      hit_rec;

    string cache_ini_file = `STRINGIFY(`CACHE_INI_FILE);

    mem_list_gen #(TAG_WIDTH, DATA_WIDTH, CELL_AMOUNT) mem_list_gen_h;

    cache #(
        .SETS        (8),
        .WAYS        (1),
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH_CUT)
    ) u_direct_mapped_cache (
        .clk_i       (clk),
        .rstn_i      (rstn),
        .addr_i      (addr_cut),
        .data_o      (data),
        .hit_valid_o (hit_valid),
        .hit_o       (hit)
    );

    task automatic reset_gen();
        rstn <= 1'b0;
        #(5*CLK_PERIOD);
        rstn <= 1'b1;
    endtask : reset_gen

    task automatic check_cache(
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
                    $error("[%0t] Right 'data_o' value. Received: 0x%x, Expected: 0x%x (#%0d)",
                        $time(), data_rec, data_exp, error_cnt);
                end
            end
        end else begin
            error_cnt++;
            $error("[%0t] Wrong 'hit_o' value. Received = %0b, expected = %0b. (#%0d)",
                $time(), hit_rec, hit_exp, error_cnt);
       end
    endtask : check_cache

    initial begin : main_tb_proc
        mem_list_gen_h = new();
        assert(mem_list_gen_h.generate_file(cache_ini_file, "%h", 1));
        mem_list_gen_h.get_generated_cells(expeced_cells);
        $readmemh(cache_ini_file, u_direct_mapped_cache.sram);

        @(negedge rstn);
        @(posedge rstn);
        repeat(2) @(posedge clk);
        
        for(int unsigned i = 0; i < SETS; i++) begin
            $display("");
            set      = i;
            tag      = expeced_cells[i].tag;
            data_exp = expeced_cells[i].data;
            valid    = expeced_cells[i].valid;
            hit_exp  = valid;
            addr_cut <= {tag, set};

            @(posedge clk);
            is_hit_valid_timeout = 0;
            fork
                fork
                    wait(hit_valid === 1'b1);
                    #(2 * CLK_PERIOD) is_hit_valid_timeout = 1;
                join_any
                disable fork;
            join

            @(negedge clk);
            hit_rec  = hit;
            data_rec = data;

            if(is_hit_valid_timeout) begin
                error_cnt++;
                $error("[%0t] Cannot wait for high value of 'hit_valid_o'. Received: %0b. (#%0d)",
                    $time(), hit_valid, error_cnt);
            end else begin
               check_cache(hit_rec, hit_exp, data_rec, data_exp);
            end
        end

        repeat(10)
            @(posedge clk);
        $display("");
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
