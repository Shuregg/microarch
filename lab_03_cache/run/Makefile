.PHONY: sim view clean

export SEED?=random
export PROJECT_PATH:=$(abspath ../)
export TB_PATH:=$(PROJECT_PATH)/dv
export RTL_PATH:=$(PROJECT_PATH)/rtl
export CACHE_TYPE?=DIRECT_MAPPED_CACHE

USER_DEFINES:= \
	-define CACHE_INI_FILE="${TB_PATH}/cache_ini.list" \

ifneq ($(filter $(CACHE_TYPE),DIRECT_MAPPED_CACHE FOUR_WAY_SET_ASSOCIATIVE_CACHE FULLY_ASSOCIATIVE_CACHE),)
	USER_DEFINES += -define ${CACHE_TYPE}
endif

XRUN_OPTS:= \
	-input probes.tcl \
	-64bit -access +rwc \
	-timescale 1ns/1ps \
	-l sim.log \
	-errormax 10 \
	-seed ${SEED} \
	${USER_DEFINES} \
    -incdir ${TB_PATH} \
	${TB_PATH}/mem_list_gen.sv \
	${TB_PATH}/tb_cache.sv \
	${RTL_PATH}/cache.sv

sim:
	xrun $(XRUN_OPTS)

clean:
	rm -rf xcelium.d waves.shm

view:
	simvision waves.shm &

