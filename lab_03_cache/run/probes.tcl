database -open waves -shm -default
probe -create -shm -all -depth all
# probe -create $uvm:{uvm_test_top} -shm -all -depth all
run
