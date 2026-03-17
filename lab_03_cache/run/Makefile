.PHONY: sim

export SEED?=random
export PROJECT_PATH:=$(abspath ../)


sim:
	xrun \
		-input probes.tcl \
		-64bit -access +rwc \
		-l sim.log \
		-errormax 10 \
		-seed ${SEED} \
		+define+MEM_LIST_DMC=${PROJECT_PATH}/rtl


show_proj_path:
	@echo "PROJECT_PATH = ${PROJECT_PATH}"