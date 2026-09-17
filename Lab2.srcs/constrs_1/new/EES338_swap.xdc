## This file is a general .xdc for EES-338 (Xilinx Artix-7 XC7A35T-1CSG324C)
## ===== 实验版：把 UART_TX/UART_RX 引脚对调 =====
## 目的：验证手册第9节 "UART_TX=N5 / UART_RX=T4" 的命名是否与板子实际走线方向相反
## （若本版本能收到 Hello，说明正确接线是 uart_txd->T4, uart_rxd->N5）
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property PACKAGE_PIN T5 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]

# ---------------- UART（SWAPPED 实验）----------------
set_property PACKAGE_PIN T4 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]

set_property PACKAGE_PIN N5 [get_ports uart_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd]

# ---------------- 复位按键（低有效）----------------
set_property PACKAGE_PIN P15 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]
set_property PULLUP true [get_ports rst_btn]

# ---------------- LED0（心跳）----------------
set_property PACKAGE_PIN K2 [get_ports led0]
set_property IOSTANDARD LVCMOS33 [get_ports led0]
