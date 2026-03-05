# This file provides all tcl commands inside the Vivado Tcl console while working with the GUI.
# This can be useful for creating a project build script without a GUI.

# 1. Create project 'lab_02_ila_and_vio' with existing source files and xdc.
start_gui
create_project lab_02_ila_and_vio D:/Study/microarch/lab_02_ila_and_vio -part xc7a100tcsg324-1
add_files {D:/Study/microarch/lab_02_ila_and_vio/rtl/counter_task1.sv D:/Study/microarch/lab_02_ila_and_vio/rtl/counter_task2.sv D:/Study/microarch/lab_02_ila_and_vio/rtl/counter_task4.sv D:/Study/microarch/lab_02_ila_and_vio/rtl/counter_task3.sv D:/Study/microarch/lab_02_ila_and_vio/rtl/wrapper.sv}
add_files -fileset constrs_1 -norecurse D:/Study/microarch/lab_02_ila_and_vio/xdc/Nexys-A7-100T.xdc
update_compile_order -fileset sources_1
update_compile_order -fileset sources_1

# 1. Generate VIO IP for task 4.
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0 -dir d:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.srcs/sources_1/ip
set_property -dict [list CONFIG.C_PROBE_OUT1_INIT_VAL {0xff} CONFIG.C_PROBE_OUT0_INIT_VAL {0xff} CONFIG.C_PROBE_OUT1_WIDTH {8} CONFIG.C_PROBE_OUT0_WIDTH {8} CONFIG.C_NUM_PROBE_OUT {2} CONFIG.C_EN_PROBE_IN_ACTIVITY {0} CONFIG.C_NUM_PROBE_IN {0}] [get_ips vio_0]
generate_target {instantiation_template} [get_files d:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.srcs/sources_1/ip/vio_0/vio_0.xci]
update_compile_order -fileset sources_1
generate_target all [get_files  d:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.srcs/sources_1/ip/vio_0/vio_0.xci]
catch { config_ip_cache -export [get_ips -all vio_0] }
export_ip_user_files -of_objects [get_files d:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.srcs/sources_1/ip/vio_0/vio_0.xci] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] d:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.srcs/sources_1/ip/vio_0/vio_0.xci]
launch_runs -jobs 12 vio_0_synth_1
export_simulation -of_objects [get_files d:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.srcs/sources_1/ip/vio_0/vio_0.xci] -directory D:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.ip_user_files/sim_scripts -ip_user_files_dir D:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.ip_user_files -ipstatic_source_dir D:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.ip_user_files/ipstatic -lib_map_path [list {modelsim=D:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.cache/compile_simlib/modelsim} {questa=D:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.cache/compile_simlib/questa} {riviera=D:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.cache/compile_simlib/riviera} {activehdl=D:/Study/microarch/lab_02_ila_and_vio/lab_02_ila_and_vio.cache/compile_simlib/activehdl}] -use_ip_compiled_libs -force -quiet

# 2. Synthesis
launch_runs synth_1 -jobs 12

# 3. Set up debug (GUI) for ILA. (The current version of Nexys-A7-100T.xdc already contains this lines)

# For better automatization you should use a Tcl command
# set_property MARK_DEBUG true [get_nets –of [get_pins hier1/hier2/<flop_name>/Q]]
# instead of (* MARK_DEBUG = "TRUE" *) command in RTL description.

create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
startgroup 
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0 ]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0 ]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0 ]
endgroup
connect_debug_port u_ila_0/clk [get_nets [list CLK100MHZ_IBUF_BUFG ]]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {u_cnt_4/counter1_max_i[0]} {u_cnt_4/counter1_max_i[1]} {u_cnt_4/counter1_max_i[2]} {u_cnt_4/counter1_max_i[3]} {u_cnt_4/counter1_max_i[4]} {u_cnt_4/counter1_max_i[5]} {u_cnt_4/counter1_max_i[6]} {u_cnt_4/counter1_max_i[7]} ]]
create_debug_port u_ila_0 probe
set_property port_width 8 [get_debug_ports u_ila_0/probe1]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_cnt_4/counter2_max_i[0]} {u_cnt_4/counter2_max_i[1]} {u_cnt_4/counter2_max_i[2]} {u_cnt_4/counter2_max_i[3]} {u_cnt_4/counter2_max_i[4]} {u_cnt_4/counter2_max_i[5]} {u_cnt_4/counter2_max_i[6]} {u_cnt_4/counter2_max_i[7]} ]]
create_debug_port u_ila_0 probe
set_property port_width 8 [get_debug_ports u_ila_0/probe2]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_cnt_4/counter2_o[0]} {u_cnt_4/counter2_o[1]} {u_cnt_4/counter2_o[2]} {u_cnt_4/counter2_o[3]} {u_cnt_4/counter2_o[4]} {u_cnt_4/counter2_o[5]} {u_cnt_4/counter2_o[6]} {u_cnt_4/counter2_o[7]} ]]
create_debug_port u_ila_0 probe
set_property port_width 8 [get_debug_ports u_ila_0/probe3]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_cnt_4/counter1_o[0]} {u_cnt_4/counter1_o[1]} {u_cnt_4/counter1_o[2]} {u_cnt_4/counter1_o[3]} {u_cnt_4/counter1_o[4]} {u_cnt_4/counter1_o[5]} {u_cnt_4/counter1_o[6]} {u_cnt_4/counter1_o[7]} ]]
set_property target_constrs_file D:/Study/microarch/lab_02_ila_and_vio/xdc/Nexys-A7-100T.xdc [current_fileset -constrset]
save_constraints -force

# 4. Implementation
launch_runs impl_1 -jobs 12

# 5. Bitstream generation
launch_runs impl_1 -to_step write_bitstream -jobs 12

# 6. Hardware manager (FPGA programming)
open_hw_manager
