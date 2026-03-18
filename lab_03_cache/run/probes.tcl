database -open waves -shm -default
probe -create -shm -all -dynamic -memories -depth all
# probe -create $uvm:{uvm_test_top} -shm -all -depth all
run
