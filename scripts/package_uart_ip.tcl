set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root ip uart_control]
file mkdir [file join $root build ip_pack]
cd [file join $root build ip_pack]
create_project -in_memory -part xc7a35tcsg324-1
foreach name {uart_tx uart_rx uart_control} {add_files [file join $root rtl peripherals ${name}.v]}
set_property top uart_control [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $out -vendor wohuishuo.org -library teaching -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property name uart_control $core
set_property display_name {UART light controller and CPU telemetry} $core
set_property description {8N1 UART: light override, beep/reset pulses, and atomic 40-byte telemetry response. See docs/soc.md for protocol.} $core
set_property version 1.0 $core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity -quiet $core
ipx::save_core $core
close_project
# Discover the packaged VLNV from a fresh project and instantiate it again.
create_project -in_memory -part xc7a35tcsg324-1
set_property ip_repo_paths [file join $root ip] [current_project]
update_ip_catalog
create_ip -vlnv wohuishuo.org:teaching:uart_control:1.0 -module_name packaged_uart
generate_target all [get_ips packaged_uart]
puts "PASS UART_IP_PACKAGE vlnv=wohuishuo.org:teaching:uart_control:1.0"
close_project
