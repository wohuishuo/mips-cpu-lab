set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build board ees338_single_cycle.bit]
set result [file join $root build board build_result.txt]
if {![file exists $bit] || ![file exists $result]} {error "Build and timing evidence missing"}
set f [open $result r]
set evidence [string trim [read $f]]
close $f
if {![regexp {^PASS BOARD_BUILD .* bitstream_sha256=([[:xdigit:]]{64})$} $evidence -> expected_sha256]} {
 error "Build evidence is incomplete or invalid; rebuild before programming"
}
package require sha256
set actual_sha256 [::sha2::sha256 -hex -filename $bit]
if {![string equal -nocase $expected_sha256 $actual_sha256]} {
 error "Build evidence does not match the bitstream; rebuild before programming"
}
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
if {[llength $targets]!=1} {error "Expected exactly one connected target"}
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices xc7a35t*]
if {[llength $devices]!=1} {error "Expected exactly one XC7A35T"}
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bit $device
program_hw_devices $device
refresh_hw_device $device
puts "PASS BOARD_PROGRAM device=[get_property PART $device]"
close_hw_target
disconnect_hw_server
close_hw_manager
