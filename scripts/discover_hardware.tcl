open_hw_manager
connect_hw_server -url localhost:3121
puts "DISCOVERY_SERVER [get_hw_servers]"
foreach target [get_hw_targets] {
    puts "DISCOVERY_TARGET $target"
    current_hw_target $target
    open_hw_target
    foreach device [get_hw_devices] {
        puts "DISCOVERY_DEVICE $device"
        puts "DISCOVERY_PART [get_property PART $device]"
        puts "DISCOVERY_IDCODE [get_property IDCODE_HEX $device]"
    }
    close_hw_target
}
disconnect_hw_server
close_hw_manager
exit
