class mem_list_gen #(
    parameter WORD_WIDTH,
    parameter WORD_AMOUNT // Equal to max address without byte offset bits
);

    logic [WORD_WIDTH - 1 : 0] generated_data [WORD_AMOUNT];

    function int generate_file(
        const string output_dir_path  = ".",
        const string output_file_name = "mem_ini.list"
    );
        int exit_status;
        string output_file_path = $sformatf("%s/%s", output_dir_path, output_file_name);
        int fd = $fopen(output_file_path, "w");
        if(!fd) begin
            exit_status = 0;
            $error("Cannot open the file with path: '%s'", output_file_path);
        end else begin
            exit_status = 1;
            $display("The file was opened successfuly: '%s'", output_file_path);
            $display("Starting generation...");
            for(longint unsigned i = 0; i <= WORD_AMOUNT; i++) begin
                logic [WORD_WIDTH - 1 : 0] word;
                rand_word : assert(std::randomize(word));
                generated_data[i] = word;
                $fdisplayb(fd, word);
            end
            $display("Generation has been completed: %s", output_file_path);
        end
        $fclose(fd);
        return exit_status;
    endfunction : generate_file

    function void get_expected_words_array(ref logic [WORD_WIDTH - 1 : 0] expeced_words_array[WORD_AMOUNT]);
        for(longint unsigned i = 0; i < WORD_AMOUNT; i++)
            expeced_words_array[i] = generated_data[i];
    endfunction

endclass : mem_list_gen