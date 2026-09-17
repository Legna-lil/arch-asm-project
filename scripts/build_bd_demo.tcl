# =============================================================================
# build_bd_demo.tcl - 用"封装好的 IP 核"搭一个 Block Design 并综合
#
# 目的：证明 EES338_Core 已经是一个标准 IP —— 可以在 IP Integrator 里拖进来，
#       和 Xilinx 自带 IP（clk_wiz / proc_sys_reset / util_vector_logic）连线，
#       生成 wrapper 并综合通过。
#
# 结构：
#   外部端口 sys_clk(100MHz) -> clk_wiz_0(clk_out1=50MHz) -> soc_0/CLK
#   外部端口 rst_btn(低有效) -> inv_btn(NOT) -> rst_0/ext_reset_in
#   rst_0/peripheral_aresetn(低有效) -> inv_rst(NOT) -> soc_0/RST
#   soc_0 的 uart/bt/lcd 引脚 -> 外部端口（名字与 EES338.xdc 一致）
#
# 产物：<repo>/bd_demo/bd_demo.xpr（独立工程，不影响主工程 Lab2.xpr）
#
# 用法：
#   & 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace `
#       -source E:/VivadoProject/Lab2/scripts/build_bd_demo.tcl
# =============================================================================

set repo    E:/VivadoProject/Lab2
set ip_repo $repo/ip_repo
set bddir   $repo/bd_demo
set ipname  EES338_Core
set ipvlnv  ees338.bjut:ip:EES338_Core:1.0

if {![file exists $ip_repo/$ipname/component.xml]} {
    puts "ERROR: IP not packaged yet, run scripts/package_ip.tcl first"
    exit 1
}

file delete -force $bddir
file mkdir $bddir

puts "==================== 1) 建 BD 演示工程并挂 ip_repo ===================="
create_project -force bd_demo $bddir -part xc7a35tcsg324-1
set_property ip_repo_paths [list [file normalize $ip_repo]] [current_project]
update_ip_catalog -rebuild
puts "  IP in catalog: [get_ipdefs -quiet -filter "NAME == $ipname"]"

puts "==================== 2) 建 Block Design ===================="
create_bd_design "ees338_soc"
update_compile_order -fileset sources_1

# --- 时钟向导：100MHz 板上时钟 -> 50MHz 逻辑时钟 ---
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.USE_RESET {false} \
] [get_bd_cells clk_wiz_0]

# --- 复位同步器（Xilinx 标准复位树）---
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_0

# --- 反相器：按键(低有效) -> ext_reset_in(高有效) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 inv_btn
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] [get_bd_cells inv_btn]

# --- 反相器：peripheral_aresetn(低有效) -> soc RST(高有效) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 inv_rst
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] [get_bd_cells inv_rst]

# --- 我们封装好的 SoC IP ---
create_bd_cell -type ip -vlnv $ipvlnv soc_0

puts "==================== 3) 连线 ===================="
# 外部引脚
create_bd_port -dir I -type clk sys_clk
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports sys_clk]
create_bd_port -dir I rst_btn

connect_bd_net [get_bd_ports sys_clk] [get_bd_pins clk_wiz_0/clk_in1]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins soc_0/CLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rst_0/slowest_sync_clk]
connect_bd_net [get_bd_ports rst_btn] [get_bd_pins inv_btn/Op1]
connect_bd_net [get_bd_pins inv_btn/Res] [get_bd_pins rst_0/ext_reset_in]
connect_bd_net [get_bd_pins rst_0/peripheral_aresetn] [get_bd_pins inv_rst/Op1]
connect_bd_net [get_bd_pins inv_rst/Res] [get_bd_pins soc_0/RST]

# 外部端口 + 连线（端口名与 EES338.xdc / EES338Top.v 完全一致，可直接复用板级约束）
create_bd_port -dir O uart_txd
create_bd_port -dir I uart_rxd
create_bd_port -dir O bt_txd
create_bd_port -dir I bt_rxd
create_bd_port -dir O -from 7 -to 0 lcd_d
create_bd_port -dir O lcd_wr_n
create_bd_port -dir O lcd_rd_n
create_bd_port -dir O lcd_cs_n
create_bd_port -dir O lcd_rs
create_bd_port -dir O lcd_rst_n
create_bd_port -dir O -from 7 -to 0 seg_grp0
create_bd_port -dir O -from 3 -to 0 dn0
create_bd_port -dir O -from 7 -to 0 seg_grp1
create_bd_port -dir O -from 3 -to 0 dn1

connect_bd_net [get_bd_ports uart_txd]  [get_bd_pins soc_0/uart_txd]
connect_bd_net [get_bd_ports uart_rxd]  [get_bd_pins soc_0/uart_rxd]
connect_bd_net [get_bd_ports bt_txd]    [get_bd_pins soc_0/bt_txd]
connect_bd_net [get_bd_ports bt_rxd]    [get_bd_pins soc_0/bt_rxd]
connect_bd_net [get_bd_ports lcd_d]     [get_bd_pins soc_0/lcd_d]
connect_bd_net [get_bd_ports lcd_wr_n]  [get_bd_pins soc_0/lcd_wr_n]
connect_bd_net [get_bd_ports lcd_rd_n]  [get_bd_pins soc_0/lcd_rd_n]
connect_bd_net [get_bd_ports lcd_cs_n]  [get_bd_pins soc_0/lcd_cs_n]
connect_bd_net [get_bd_ports lcd_rs]    [get_bd_pins soc_0/lcd_rs]
connect_bd_net [get_bd_ports lcd_rst_n] [get_bd_pins soc_0/lcd_rst_n]
connect_bd_net [get_bd_ports seg_grp0] [get_bd_pins soc_0/seg_grp0]
connect_bd_net [get_bd_ports dn0]      [get_bd_pins soc_0/dn0]
connect_bd_net [get_bd_ports seg_grp1] [get_bd_pins soc_0/seg_grp1]
connect_bd_net [get_bd_ports dn1]      [get_bd_pins soc_0/dn1]

regenerate_bd_layout
validate_bd_design

puts "==================== 4) 生成 wrapper + 加板级约束 ===================="
set bd_file [get_files -quiet *ees338_soc.bd]
if {[llength $bd_file] == 0} { puts "ERROR: BD file not found"; exit 1 }
generate_target all $bd_file
make_wrapper -files $bd_file -top

# wrapper 生成在 <bd 目录>/hdl/ees338_soc_wrapper.v（2019.2 的 make_wrapper 不会
# 自动把它加进工程，这里把它找出来/加进来）
set wrapper [get_files -quiet -all *ees338_soc_wrapper.v]
if {[llength $wrapper] == 0} {
    set projdir  [get_property DIRECTORY [current_project]]
    set projname [get_property NAME [current_project]]
    set wpath [file join $projdir "${projname}.srcs" sources_1 bd ees338_soc hdl ees338_soc_wrapper.v]
    if {[file exists $wpath]} {
        add_files -norecurse $wpath
        set wrapper [get_files -quiet $wpath]
    }
}
if {[llength $wrapper] == 0} {
    puts "ERROR: wrapper not generated"
    exit 1
}
puts "  wrapper: $wrapper"
update_compile_order -fileset sources_1
set_property top ees338_soc_wrapper [current_fileset]

# 复用主工程的板级引脚约束（端口名一致；led0 在这个 BD 里不存在，只会报 warning）
add_files -fileset constrs_1 -norecurse [file normalize $repo/Lab2.srcs/constrs_1/new/EES338.xdc]

puts "==================== 5) 综合（验证 IP 集成后能通过）===================="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set st [get_property STATUS [get_runs synth_1]]
puts "  synth_1 status: $st"
if {[catch {open_run synth_1 -name synth_1}]} {
    puts "ERROR: synthesis failed - see $bddir/bd_demo.runs/synth_1/runme.log"
} else {
    report_utilization    -file $repo/scripts/bd_synth_util.rpt
    report_timing_summary -file $repo/scripts/bd_synth_timing.rpt
    puts "  reports: scripts/bd_synth_util.rpt / scripts/bd_synth_timing.rpt"
}
# 注意：BD 在 close_project 时会随工程一起保存（早期版本这里在 close 之后调用
# save_bd_design，会报 "No open project"，已删除）。
catch {close_project}
puts "==================== DONE (BD demo) ===================="
puts "project : $bddir/bd_demo.xpr"
