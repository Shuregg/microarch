.PHONY: sim view clean

export SEED?=random
export PROJECT_PATH:=$(abspath ../)
export TB_PATH:=$(PROJECT_PATH)/dv
export RTL_PATH:=$(PROJECT_PATH)/rtl

sim:
	xrun \
		-input probes.tcl \
		-64bit -access +rwc \
		-timescale 1ns/1ps \
		-l sim.log \
		-errormax 10 \
		-seed ${SEED} \
		-define CACHE_INI_FILE="${TB_PATH}/cache_ini.list" \
		${TB_PATH}/mem_list_gen.sv \
		${TB_PATH}/tb_cache.sv \
		${RTL_PATH}/cache.sv

clean:
	rm -rf xcelium.d waves.shm

view:
	simvision waves.shm &
