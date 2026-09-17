# =============================================================================
# package_ip.tcl - 把 EES338_Core（五级流水线 RV32I CPU + UART/蓝牙/LCD 外设）
#                  封装成标准 Vivado IP 核，并把 ip_repo 挂到主工程里
#
# 产物：
#   <repo>/ip_repo/ees338_riscv_soc/component.xml      <- IP 描述文件（"IP 核"本体）
#   <repo>/ip_repo/ees338_riscv_soc/src/*.v,.vh        <- 源文件副本（-import_files）
#
# 用法（Windows PowerShell）：
#   & 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace `
#       -source E:/VivadoProject/Lab2/scripts/package_ip.tcl
#
# 说明（什么叫"封装 IP 核"）：
#   普通 .v 文件对 Vivado 来说只是"一堆源码"；封装(Component Packaging)是把它变成
#   IP 目录(IP Catalog)里可以复用、可以在 Block Design(IP Integrator) 里直接例化的
#   一个"黑盒"，需要额外描述：
#     ① 身份     : vendor/library/name/version (VLNV)
#     ② 文件组   : 哪些文件属于这个 IP（RTL / 头文件 / 约束 / 仿真）
#     ③ 参数     : 哪些 HDL 参数暴露给用户改（customization GUI）
#     ④ 接口     : 端口如何组成总线/时钟/复位接口（本脚本定义了 CLK / RST 两个
#                  标准 Xilinx 信号接口，让 Block Design 可以自动连线）
#   最终这些都写进 component.xml —— 这就是"IP 核"。
# =============================================================================

set repo    E:/VivadoProject/Lab2
# 目录分类：计组(cpu/) + 汇编(periph/)
set src_cpu    $repo/Lab2.srcs/sources_1/new/cpu
set src_periph $repo/Lab2.srcs/sources_1/new/periph
set ip_repo $repo/ip_repo
set workdir $repo/.workbuddy/ip_pkg

set vendor  ees338.bjut
set library ip
set name    EES338_Core
set version 1.0

file mkdir $ip_repo
file delete -force $workdir
file mkdir $workdir
file delete -force $ip_repo/$name

puts "==================== 1) 建立只含 IP 源文件的临时工程 ===================="
create_project -force ip_pkg $workdir -part xc7a35tcsg324-1
set_property target_language Verilog [current_project]

# 汇编部分（外设 + 总线）
set ip_files_periph [list \
    EES338_Core.v PeriphMMIO.v UartChannel.v UART_TX.v UART_RX.v LCD128128.v \
    SegDisplay.v SimpleTimer.v ]
# 计组部分（五级流水线 CPU 及其子模块 + 综合引导用 .vh）
set ip_files_cpu [list \
    PipelineCPU.v ALU.v ControlUnit.v DataMemory.v InstructionMemory.v \
    RegisterFile.v PC.v ImmediateGenerator.v FlagReg.v DivUnit.v \
    macro.vh imem_boot_init.vh dmem_boot_init.vh ]

foreach f $ip_files_periph {
    if {[file exists $src_periph/$f]} {
        add_files -norecurse [file normalize $src_periph/$f]
    } else {
        puts "WARN: missing periph/$f"
    }
}
foreach f $ip_files_cpu {
    if {[file exists $src_cpu/$f]} {
        add_files -norecurse [file normalize $src_cpu/$f]
    } else {
        puts "WARN: missing cpu/$f"
    }
}
set_property top EES338_Core [current_fileset]
update_compile_order -fileset sources_1

puts "==================== 2) 打包 ===================="
ipx::package_project -root_dir $ip_repo/$name -vendor $vendor -library $library \
    -taxonomy /UserIP -import_files -set_current true

set core [ipx::current_core]

# ---- 身份信息（会显示在 IP Catalog / Block Design 里）----
set_property display_name    "EES338 RISC-V 5-stage CPU + UART/BLE/LCD SoC" $core
set_property description     "EES-338 (xc7a35t) SoC: 5-stage pipelined RV32I CPU (hardwired control, forwarding/stall/flush, overflow detect) + memory-mapped peripherals: USB-UART, BLE-CC41-A bluetooth and JLX128128G ST7571 LCD. MMIO: 0x1000_0000 UART_DATA/0x1000_0004 UART_STATUS, 0x1000_0010 BT_DATA/0x1000_0014 BT_STATUS, 0x1000_0100 LCD_CMD/0x1000_0104 LCD_DAT/0x1000_0108 LCD_STATUS/0x1000_010C LCD_CTRL. Clock: single 50 MHz logic clock (use clk_wiz from the 100 MHz board clock)." $core
set_property vendor_display_name "BUIT EES338 Course Project" $core
set_property company_url     "https://github.com/Legna-lil/arch-asm-project" $core
set_property version         $version $core
set_property previous_version_for_upgrade $vendor:$library:$name $core

# ---- 文件组一览 ----
foreach fg [ipx::get_file_groups -of_objects $core] {
    puts "  file group: [get_property name $fg]"
}

# ---- 补文件：imem_boot_init.vh / dmem_boot_init.vh 只在 `ifdef SYNTHESIS 里被 include，
#      打包器的 HDL 解析器看不到它们，会报 "Unreferenced file ... not packaged"。
#      这两个文件是程序/数据被"烘焙"进片内 ROM/RAM 的内容，必须放进 IP，否则
#      别人用这个 IP 综合时会找不到 include 文件（IP 不可用）。这里手工加进合成/仿真文件组。----
set ip_srcdir $ip_repo/$name/src
foreach f {imem_boot_init.vh dmem_boot_init.vh} {
    foreach fgname {xilinx_anylanguagesynthesis xilinx_anylanguagebehavioralsimulation} {
        if {[catch {
            set fg [ipx::get_file_groups $fgname -of_objects $core]
            if {[llength [ipx::get_files -quiet -of_objects $fg -filter "NAME==$f"]] == 0} {
                ipx::add_file $ip_srcdir/$f $fg
            }
        } emsg]} { puts "  WARN add file $f -> $fgname: $emsg" }
    }
}
# 复制一份到 IP 的 src 目录（-import_files 只搬了被引用的文件）
foreach f {imem_boot_init.vh dmem_boot_init.vh} {
    if {![file exists $ip_srcdir/$f]} {
        file copy -force $src/$f $ip_srcdir/$f
        puts "  copied $f into IP src"
    }
}


# ---- 参数：打包器已把顶层 HDL 参数自动转成"用户参数"(user parameter)，
#      在 IP 的 Customization GUI 里就能改；这里补上友好的显示名/描述并排序 ----
array set pdesc {
    BAUD_DIV       "USB-UART 每 bit 时钟数 = 50MHz/波特率 (115200 -> 434)"
    BAUD_DIV_BT    "蓝牙每 bit 时钟数 = 50MHz/波特率 (9600 -> 5208)"
    LCD_WR_CYCLES  "LCD WR# 低电平宽度（50MHz 周期数）"
    LCD_RST_CYCLES "LCD 上电复位低电平宽度（50MHz 周期数，200000 = 4ms）"
    SEG_SCAN_DIV   "数码管扫描相位长度（50MHz 周期数，16384 ≈ 760Hz 刷新）"
    TIMER_DELAY    "硬件延时长度（50MHz 周期数，20000000 = 0.4s）"
    HEX_FILE       "仿真用指令 hex 文件路径"
    DATA_FILE      "仿真用数据 hex 文件路径"
}
foreach {pname ptext} [array get pdesc] {
    if {[catch {
        set up [ipx::get_user_parameters $pname -of_objects $core]
        if {$up ne ""} {
            set_property display_name $pname $up
            set_property description  $ptext $up
        }
    } emsg]} { puts "  WARN param $pname: $emsg" } else { puts "  param $pname -> ok" }
}
if {[catch {ipx::infer_user_parameter_order $core} emsg]} { puts "  WARN order: $emsg" }

# ---- 接口：打包器会按端口名自动推断出 clk / rst 两个 Xilinx 标准信号接口；
#      这里把它们规范成 CLK / RST 并补参数，Block Design 就能自动连线；
#      同时删掉被误判成"复位接口"的 lcd_rst_n（它是送给 LCD 屏的输出，不是复位输入） ----
if {[catch {
    set bi [ipx::get_bus_interfaces lcd_rst_n -of_objects $core -quiet]
    if {$bi ne ""} { ipx::remove_bus_interface lcd_rst_n $core }
} emsg]} { puts "  WARN remove lcd_rst_n: $emsg" } else { puts "  removed bogus reset iface lcd_rst_n" }

# --- CLK ---
if {[catch {
    set clkif [ipx::get_bus_interfaces clk -of_objects $core -quiet]
    if {$clkif eq ""} {
        set clkif [ipx::add_bus_interface CLK $core]
        ipx::add_port_map CLK $clkif
        set_property physical_name clk [ipx::get_port_maps CLK -of_objects $clkif]
    } else {
        set_property name CLK $clkif
    }
    set_property abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0 $clkif
    set_property bus_type_vlnv         xilinx.com:signal:clock:1.0     $clkif
    set_property interface_mode        slave                           $clkif
    set_property display_name          CLK                             $clkif
    set_property description           "SoC logic clock (50 MHz)"      $clkif
    ipx::add_bus_parameter ASSOCIATED_RESET $clkif
    set_property value RST [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clkif]
} emsg]} { puts "  WARN CLK interface: $emsg" } else { puts "  interface CLK  -> ok" }

# --- RST ---
if {[catch {
    set rstif [ipx::get_bus_interfaces rst -of_objects $core -quiet]
    if {$rstif eq ""} {
        set rstif [ipx::add_bus_interface RST $core]
        ipx::add_port_map RST $rstif
        set_property physical_name rst [ipx::get_port_maps RST -of_objects $rstif]
    } else {
        set_property name RST $rstif
    }
    set_property abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0 $rstif
    set_property bus_type_vlnv         xilinx.com:signal:reset:1.0     $rstif
    set_property interface_mode        slave                           $rstif
    set_property display_name          RST                             $rstif
    set_property description           "Active high reset"             $rstif
    ipx::add_bus_parameter POLARITY $rstif
    set_property value ACTIVE_HIGH [ipx::get_bus_parameters POLARITY -of_objects $rstif]
} emsg]} { puts "  WARN RST interface: $emsg" } else { puts "  interface RST  -> ok" }

foreach bi [ipx::get_bus_interfaces -of_objects $core] {
    puts "  iface: [get_property name $bi] mode=[get_property interface_mode $bi]"
}

# ---- 收尾：生成 GUI 文件 + 校验和 + 保存 ----
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

puts "==================== 3) 把 ip_repo 挂到主工程 ===================="
close_project
open_project $repo/Lab2.xpr
set_property ip_repo_paths [list [file normalize $ip_repo]] [current_project]
update_ip_catalog -rebuild
puts "  ip_repo_paths = [get_property ip_repo_paths [current_project]]"
set found [get_ipdefs -quiet -filter "NAME == $name"]
if {[llength $found] == 0} {
    puts "ERROR: IP not visible in catalog! (looked for NAME == $name)"
} else {
    puts "OK: IP visible in IP Catalog -> $found"
}
close_project

file delete -force $workdir
puts "==================== DONE ===================="
puts "component.xml : $ip_repo/$name/component.xml"
