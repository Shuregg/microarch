database -open waves -shm -default
probe -create -shm -all -dynamic -memories -depth all -unpacked 536870912
# probe -create $uvm:{uvm_test_top} -shm -all -depth all
run
