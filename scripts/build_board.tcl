set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root build board]
set result [file join $work build_result.txt]
set result_tmp "$result.tmp"
file delete -force $result $result_tmp
file mkdir $work
cd $work
# Vivado 2019.2 sets PYTHONHOME/PYTHONPATH for its bundled Python 2.7.
# Ignore those variables when launching the host's Python 3 assembler helper.
puts [exec python -E [file join $root scripts build_board_program.py]]
read_verilog [file join $root rtl core single_cycle_cpu.v]
foreach source [glob [file join $root rtl peripherals *.v]] {read_verilog $source}
read_verilog [file join $root rtl soc lab_soc.v]
read_verilog [file join $root rtl soc ees338_top.v]
read_xdc [file join $root constraints ees338.xdc]
synth_design -top ees338_top -part xc7a35tcsg324-1
report_utilization -file utilization_synth.rpt
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -delay_type min_max -report_unconstrained -file timing.rpt
report_utilization -file utilization.rpt
report_drc -file drc.rpt
report_clock_interaction -file clocks.rpt
write_checkpoint -force routed.dcp
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup]==0 || [llength $hold]==0} {error "Missing timed paths"}
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
if {$wns<0 || $whs<0} {error "Timing failure setup=$wns hold=$whs"}
write_bitstream -force ees338_single_cycle.bit
set bit [file join $work ees338_single_cycle.bit]
package require sha256
set bit_sha256 [::sha2::sha256 -hex -filename $bit]
set f [open $result_tmp w]
puts $f "PASS BOARD_BUILD part=xc7a35tcsg324-1 cpu_mhz=10 setup_slack=$wns hold_slack=$whs bitstream_sha256=$bit_sha256"
close $f
file rename -force $result_tmp $result
