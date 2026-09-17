# =============================================================================
# run_bitstream_swap.tcl
# 生成 UART_TX/UART_RX 引脚对调版本的测试 bit（排查 N5/T4 方向用）
# 产物: bitstream/EES338Top_hello_swap.bit
# 完成后自动把工程约束恢复为默认 EES338.xdc
# =============================================================================

set proj_dir E:/VivadoProject/Lab2
set src      $proj_dir/Lab2.srcs/sources_1/new/periph
set src_cpu  $proj_dir/Lab2.srcs/sources_1/new/cpu
set c_orig   $proj_dir/Lab2.srcs/constrs_1/new/EES338.xdc
set c_swap   $proj_dir/Lab2.srcs/constrs_1/new/EES338_swap.xdc

open_project $proj_dir/Lab2.xpr

# 确保设计源在工程中
foreach f {ClockGen.v UART_TX.v UART_RX.v EES338Top.v} {
    set fp $src/$f
    if {[llength [get_files -quiet $fp]] > 0} { remove_files $fp }
    add_files -norecurse $fp
}
foreach f {imem_boot_init.vh dmem_boot_init.vh macro.vh} {
    set fp $src_cpu/$f
    if {[llength [get_files -quiet $fp]] > 0} { remove_files $fp }
    add_files -norecurse $fp
}
set_property top EES338Top [current_fileset]
update_compile_order -fileset sources_1

# 换成 SWAP 约束
if {[llength [get_files -quiet $c_orig]] > 0} { remove_files $c_orig }
if {[llength [get_files -quiet $c_swap]] > 0} { remove_files $c_swap }
add_files -fileset constrs_1 -norecurse $c_swap

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

file mkdir $proj_dir/bitstream
file copy -force $proj_dir/Lab2.runs/impl_1/EES338Top.bit \
                  $proj_dir/bitstream/EES338Top_hello_swap.bit

# 恢复默认约束
remove_files $c_swap
add_files -fileset constrs_1 -norecurse $c_orig
puts "================ SWAP BIT DONE ================"
close_project
