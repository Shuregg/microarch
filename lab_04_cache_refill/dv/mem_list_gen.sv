class mem_list_gen #(
    TAG_WIDTH,
    DATA_WIDTH,
    CELL_AMOUNT, // sets
    WAY_AMOUNT
);

    localparam CELL_WIDTH = TAG_WIDTH + DATA_WIDTH;

    typedef struct packed {
        logic [TAG_WIDTH  - 1 : 0] tag;
        logic [DATA_WIDTH - 1 : 0] data;
    } set_t;

    set_t [CELL_AMOUNT - 1 : 0][WAY_AMOUNT - 1 : 0] generated_data;
    logic [CELL_AMOUNT - 1 : 0][WAY_AMOUNT - 1 : 0] generated_valids;

    function int generate_file(
        string output_file   = "./mem_ini.list",
        string radix         = "%b",
        int    valid_prob    = 85
    );
        int exit_status = 1;
        int fd = $fopen(output_file, "w");
        radix = radix.tolower();
        if(!fd) begin
            exit_status = 0;
            $error("Cannot open the file with path: '%s'", output_file);
        end else begin
            $display("The file was opened successfuly: '%s'", output_file);
            $display("Starting generation...");
            for(int unsigned i = 0; i < CELL_AMOUNT; i++) begin
                logic [WAY_AMOUNT - 1 : 0] cell_valids;
                set_t [WAY_AMOUNT - 1 : 0] cell_value;
                rand_cell_valids : assert(std::randomize(cell_valids) with {
                    cell_valids dist {
                        1'b1 :/ (valid_prob),
                        1'b0 :/ (100 - valid_prob)
                    };
                });
                rand_cell_value : assert(std::randomize(cell_value));
                generated_data[i] = cell_value;
                generated_valids[i] = cell_valids;
                case(radix)
                    "%b", "%0b", "b", "bin": $fdisplayb(fd, cell_value);
                    "%o", "%0o", "o", "oct": $fdisplayo(fd, cell_value);
                    "%d", "%0d", "d", "dec": $fdisplay (fd, cell_value);
                    "%h", "%0h", "h", "hex": $fdisplayh(fd, cell_value);
                    default: begin
                        $error("generate_file: unsupported radix '%s'. Use 'bin', 'oct', 'dec', 'hex' or relative format specifiers.", radix);
                        exit_status = 0;
                        break;
                    end
                endcase
            end
            if(exit_status)
                $display("Generation has been completed: %s", output_file);
        end
        $fclose(fd);
        return exit_status;
    endfunction : generate_file

    function void get_generated_cells(
        ref logic [CELL_AMOUNT - 1 : 0][WAY_AMOUNT - 1 : 0] generated_valids,
        ref set_t [CELL_AMOUNT - 1 : 0][WAY_AMOUNT - 1 : 0] generated_cells
    );
        for(int unsigned i = 0; i < CELL_AMOUNT; i++) begin
            generated_cells[i]  = this.generated_data[i];
            generated_valids[i] = this.generated_valids[i];
        end
    endfunction

endclass : mem_list_gen

