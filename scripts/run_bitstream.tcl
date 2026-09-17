# =============================================================================
# run_bitstream.tcl
# EES-338 (xc7a35tcsg324-1) Hello UART demo —— 一键 综合+实现+bitstream
#
# 用法（Windows PowerShell）：
#   & 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -source E:/VivadoProject/Lab2/scripts/run_bitstream.tcl -notrace
#
# 产物：Lab2.runs/impl_1/EES338Top.bit
# 报告：scripts/synth_util.rpt  scripts/synth_timing.rpt
#       scripts/impl_util.rpt   scripts/impl_timing.rpt
# =============================================================================

set proj_dir E:/VivadoProject/Lab2
set part     xc7a35tcsg324-1
# 目录分类：计组(cpu/) + 汇编(periph/)
set src_cpu    $proj_dir/Lab2.srcs/sources_1/new/cpu
set src_periph $proj_dir/Lab2.srcs/sources_1/new/periph
set cfile    $proj_dir/Lab2.srcs/constrs_1/new/EES338.xdc
set tb_cpu    $proj_dir/Lab2.srcs/sim_1/new/cpu
set tb_periph $proj_dir/Lab2.srcs/sim_1/new/periph

# 1) 打开工程并改器件为 EES-338 的 Artix-7
open_project $proj_dir/Lab2.xpr
set_property part $part [current_project]

# 2) 确保设计源/约束/测试文件都在工程里（先删后加，保证幂等）
#    汇编部分：外设 + SoC 顶层
foreach f {ClockGen.v UART_TX.v UART_RX.v UartChannel.v LCD128128.v SegDisplay.v SimpleTimer.v \
           PeriphMMIO.v EES338_Core.v EES338Top.v} {
    set fp $src_periph/$f
    if {[llength [get_files -quiet $fp]] > 0} { remove_files $fp }
    add_files -norecurse $fp
}
#    计组部分：五级流水线 CPU 及其子模块（含 include 用的 .vh）
foreach f {PipelineCPU.v SingleCycleCPU.v ALU.v ControlUnit.v DataMemory.v InstructionMemory.v \
           RegisterFile.v PC.v ImmediateGenerator.v FlagReg.v DivUnit.v \
           imem_boot_init.vh dmem_boot_init.vh macro.vh} {
    set fp $src_cpu/$f
    if {[llength [get_files -quiet $fp]] > 0} { remove_files $fp }
    add_files -norecurse $fp
}
if {[llength [get_files -quiet $cfile]] > 0} { remove_files $cfile }
add_files -fileset constrs_1 -norecurse $cfile

foreach tb {tb_uart_tx.v tb_uart_rx.v tb_lcd128128.v tb_segdisplay.v \
            tb_EES338_hello.v tb_EES338_echo.v tb_EES338_helloecho.v \
            tb_EES338_lcd.v tb_EES338_lcdtest.v tb_EES338_lcdread.v tb_EES338_bt.v \
            tb_EES338_btcheck.v tb_EES338_btat.v tb_EES338_btcfg.v tb_EES338_btseg.v \
            tb_EES338_sort.v tb_EES338_flags.v tb_flags.v} {
    set fp $tb_periph/$tb
    if {[llength [get_files -quiet $fp]] > 0} { remove_files $fp }
    add_files -fileset sim_1 -norecurse $fp
}
foreach tb {tb_ALU.v tb_alu_flags.v tb_divunit.v tb_muldiv.v tb_overflow.v tb_forward.v \
            tb_hazard.v tb_branch.v tb_inst_alu.v tb_compare.v tb_CPU.v tb_CPU_pipeline.v \
            tb_CPU_singlecycle.v tb_PC_IM.v tb_RegisterFile.v tb_ImmGen.v} {
    set fp $tb_cpu/$tb
    if {[llength [get_files -quiet $fp]] > 0} { remove_files $fp }
    add_files -fileset sim_1 -norecurse $fp
}

# 3) 顶层设为 EES338Top（工程在 close_project 时自动保存）
set_property top EES338Top [current_fileset]
update_compile_order -fileset sources_1

# 2b) 可选开关：蓝牙 TX/RX 两个引脚对调后重新约束
#     （本板 USB-UART 的手册标注就是反的，蓝牙手册标注也可能反；
#      端口方向不变，只是"哪个脚接哪个信号"对调，用第二份 bitstream 做 A/B 对比）
#     两种触发方式：
#       a) vivado -mode batch -source scripts/run_bitstream.tcl -tclargs btswap
#       b) 直接跑 scripts/run_bitstream_btswap.tcl（内部 set btswap 1 后 source 本脚本）
set do_bt_swap 0
if {[info exists btswap] && $btswap != 0} { set do_bt_swap 1 }
if {[llength $argv] > 0 && [lindex $argv 0] eq "btswap"} { set do_bt_swap 1 }

# 注意：PACKAGE_PIN 必须在**约束文件**里给（脚本里直接 get_ports 会报
# "No open design"），所以对调版是用一个额外的 XDC 覆盖后加的：
set swapxdc $proj_dir/scripts/EES338_btswap.xdc
if {[llength [get_files -quiet $swapxdc]] > 0} { remove_files $swapxdc }
if {$do_bt_swap} {
    add_files -fileset constrs_1 -norecurse $swapxdc
    puts "  ★ BT pins SWAPPED (via scripts/EES338_btswap.xdc): bt_txd -> L3, bt_rxd -> N2"
} else {
    puts "  BT pins: bt_txd -> N2, bt_rxd -> L3 (手册默认，未加 swap 约束)"
}

# 4) 综合
set_property part $part [get_runs synth_1]
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[catch {open_run synth_1 -name synth_1}]} {
    puts "ERROR: synthesis open_run failed, check synth log"
} else {
    report_utilization    -file $proj_dir/scripts/synth_util.rpt
    report_timing_summary -file $proj_dir/scripts/synth_timing.rpt
}

# 5) 实现 + 写 bitstream
set_property part $part [get_runs impl_1]
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[catch {open_run impl_1 -name impl_1}]} {
    puts "ERROR: implementation open_run failed, check impl log"
} else {
    report_utilization    -file $proj_dir/scripts/impl_util.rpt
    report_timing_summary -file $proj_dir/scripts/impl_timing.rpt
}

puts "================ DONE ================"
puts "bitstream : $proj_dir/Lab2.runs/impl_1/EES338Top.bit"
close_project
