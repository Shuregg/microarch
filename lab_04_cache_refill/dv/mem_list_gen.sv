class mem_list_gen #(
    parameter TAG_WIDTH,
    parameter DATA_WIDTH,
    parameter CELL_AMOUNT // sets
);

    localparam CELL_WIDTH = TAG_WIDTH + DATA_WIDTH;

    typedef struct packed {
        logic [TAG_WIDTH  - 1 : 0] tag;
        logic [DATA_WIDTH - 1 : 0] data;
    } set_t;

    set_t generated_data [CELL_AMOUNT];

    function int generate_file(
        string output_file   = "./mem_ini.list",
        string radix         = "%b",
        bit    use_separator = 0,
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
                logic                      cell_valid
                logic [CELL_WIDTH - 1 : 0] cell_value;
                rand_cell_valid : assert(std::randomize(cell_valid) with {
                    cell_valid dist {
                        1'b1 :/ valid_prob,
                        1'b0 :/ 100 - valid_prob
                    };
                });
                rand_cell_value : assert (std::randomize(cell_value))
                cell_valids[i]    = cell_valid;
                generated_data[i] = cell_value;
                if(use_separator) begin
                    string cell_formated = format_with_sep(cell_value, radix);
                    if(cell_formated == "") begin
                        exit_status = 0;
                        break;
                    end else begin
                        $fwrite(fd, cell_formated, "\n");
                    end
                end else begin
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
            end
            if(exit_status)
                $display("Generation has been completed: %s", output_file);
        end
        $fclose(fd);
        return exit_status;
    endfunction : generate_file

    function void get_generated_cells(
        ref logic [CELL_AMOUNT - 1 : 0] cell_valids,
        ref logic [CELL_WIDTH - 1 : 0] generated_cells[CELL_AMOUNT]);
        for(int unsigned i = 0; i < CELL_AMOUNT; i++)
            generated_cells[i] = generated_data[i];
    endfunction

    function automatic string add_separators(string s, int group_size);
        int len = s.len();
        string result = "";
        int cnt = 0;
        for (int i = len-1; i >= 0; i--) begin
            if ((cnt == group_size - 1) && (i != 0)) begin
                result = {"_", s[i], result};
                cnt = 0;
            end else begin
                result = {s[i], result};
                cnt++;
            end
        end
        return result;
    endfunction

    function automatic string format_with_sep (
        input logic [CELL_WIDTH - 1 : 0] value,
        input string radix
    );
        string str;
        int group_size;

        radix = radix.tolower();
        case(radix)
            "%b", "%0b", "b", "bin": begin
                str = (radix == "%0b") ? $sformatf("%0b", value) : $sformatf("%b", value);
                group_size = 8;
            end
            "%o", "%0o", "o", "oct": begin
                str = (radix == "%0o") ? $sformatf("%0o", value) : $sformatf("%o", value);
                group_size = 3;
            end
            "%d", "%0d", "d", "dec": begin
                str = (radix == "%0d") ? $sformatf("%0d", value) : $sformatf("%d", value);
                group_size = 3;
            end
            "%h", "%0h", "h", "hex": begin
                str = (radix == "%0h") ? $sformatf("%0h", value) : $sformatf("%h", value);
                group_size = 4;
            end
            default: begin
                $error("format_with_sep: unsupported radix '%s'. Use 'bin', 'oct', 'dec', 'hex' or relative format specifiers.", radix);
                return "";
            end
        endcase
        return add_separators(str, group_size);
    endfunction

endclass : mem_list_gen
