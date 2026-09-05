## This file is a general .xdc for EES-338 (Xilinx Artix-7 XC7A35T-1CSG324C)
## 引脚来源：EES-338 User Manual v1.0 + 实测修正
##   第8节  板载时钟 100MHz   SYS_CLK = T5
##   第9节  USB-UART CP2102    手册标 UART_TX=N5 / UART_RX=T4
##   ★实测修正：上板验证（hello_swap.bit）说明板子走线与手册方向相反，
##     正确接法是 uart_txd -> T4(FPGA 出)，uart_rxd -> N5(FPGA 入)。
##   6.1节  复位按键 RST       FPGA_RES = P15(低有效)
##   6.3节  LED0               D0 = K2
## 注意：IOSTANDARD 按 3.3V LVCMOS 假设填写；若与板子实测不符请修改。

# ---------------- 配置 bank 电压（消除 DRC 警告，板子配置电压为 3.3V） ----------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ---------------- 时钟 ----------------
set_property PACKAGE_PIN T5 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]

# ---------------- UART（实测修正：与手册标注相反） ----------------
set_property PACKAGE_PIN T4 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]

set_property PACKAGE_PIN N5 [get_ports uart_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd]

# ---------------- 复位按键（低有效）----------------
set_property PACKAGE_PIN P15 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]
set_property PULLUP true [get_ports rst_btn]

# ---------------- LED0（心跳，可选）----------------
set_property PACKAGE_PIN K2 [get_ports led0]
set_property IOSTANDARD LVCMOS33 [get_ports led0]

# 其余 LED/开关/按键若需要可按下表补充：
# LED0..3: K2 J2 J3 H4 ; LED4..7: J4 G3 G4 F6
# SW0..7 : R1 N4 M4 R2 P2 P3 P4 P5
# PB0..4 : R11 R17 R15 V1 U4
