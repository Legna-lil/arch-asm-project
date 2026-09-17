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

# ---------------- 蓝牙 BLE-CC41-A（手册 §11）----------------
#   手册标 BT_RX=N2(FPGA 出) / BT_TX=L3(FPGA 入)
#   ★与 UART 一样，若实测方向相反，把这两行对调即可（软件侧只影响收发方向）
set_property PACKAGE_PIN N2 [get_ports bt_txd]
set_property IOSTANDARD LVCMOS33 [get_ports bt_txd]

set_property PACKAGE_PIN L3 [get_ports bt_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports bt_rxd]

# ---------------- LCD JLX128128G-81202 / ST7571（手册 §13）----------------
#   8080 并口：数据总线 + WR#/RD#/CS#/RS/RST#，全部由 FPGA 驱动（只写方向）
set_property PACKAGE_PIN T1 [get_ports {lcd_d[0]}]
set_property PACKAGE_PIN M6 [get_ports {lcd_d[1]}]
set_property PACKAGE_PIN N6 [get_ports {lcd_d[2]}]
set_property PACKAGE_PIN R6 [get_ports {lcd_d[3]}]
set_property PACKAGE_PIN R5 [get_ports {lcd_d[4]}]
set_property PACKAGE_PIN V7 [get_ports {lcd_d[5]}]
set_property PACKAGE_PIN V6 [get_ports {lcd_d[6]}]
set_property PACKAGE_PIN U9 [get_ports {lcd_d[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_d[*]}]
# 数据线双向：加弱上拉，读周期若 LCD 侧没驱动（未接/接口模式不对）会读回全 1，便于判断
set_property PULLTYPE PULLUP [get_ports {lcd_d[*]}]

# 注意：xdc 不支持"命令后面跟 # 注释"，注释必须单独成行，否则 # 会被当成参数
set_property PACKAGE_PIN V9 [get_ports lcd_wr_n]     ;# LCD_WR
set_property IOSTANDARD LVCMOS33 [get_ports lcd_wr_n]

set_property PACKAGE_PIN U7 [get_ports lcd_rd_n]     ;# LCD_RD（恒 1）
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rd_n]

set_property PACKAGE_PIN U6 [get_ports lcd_cs_n]     ;# LCD_CS
set_property IOSTANDARD LVCMOS33 [get_ports lcd_cs_n]

set_property PACKAGE_PIN R7 [get_ports lcd_rst_n]    ;# LCD_RST
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rst_n]

set_property PACKAGE_PIN T6 [get_ports lcd_rs]       ;# LCD_RS
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rs]

# ---------------- 8 位数码管（手册 §6.4：共阴，位选/段选均高有效）----------------
#   8 位分两组，每组 4 位共用段选线，位选线分时点亮（本设计用 4 相位硬件扫描）
#   组0（原理图 LED0_CA..G0/DP0 + LED_BIT1..4）
set_property PACKAGE_PIN B4 [get_ports {seg_grp0[0]}]   ;# A0  LED0_CA
set_property PACKAGE_PIN A4 [get_ports {seg_grp0[1]}]   ;# B0  LED0_CB
set_property PACKAGE_PIN A3 [get_ports {seg_grp0[2]}]   ;# C0  LED0_CC
set_property PACKAGE_PIN B1 [get_ports {seg_grp0[3]}]   ;# D0  LED0_CD
set_property PACKAGE_PIN A1 [get_ports {seg_grp0[4]}]   ;# E0  LED0_CE
set_property PACKAGE_PIN B3 [get_ports {seg_grp0[5]}]   ;# F0  LED0_CF
set_property PACKAGE_PIN B2 [get_ports {seg_grp0[6]}]   ;# G0  LED0_CG
set_property PACKAGE_PIN D5 [get_ports {seg_grp0[7]}]   ;# DP0 LED0_DP
set_property IOSTANDARD LVCMOS33 [get_ports {seg_grp0[*]}]

set_property PACKAGE_PIN G2 [get_ports {dn0[0]}]        ;# DN0_K1 LED_BIT1
set_property PACKAGE_PIN C2 [get_ports {dn0[1]}]        ;# DN0_K2 LED_BIT2
set_property PACKAGE_PIN C1 [get_ports {dn0[2]}]        ;# DN0_K3 LED_BIT3
set_property PACKAGE_PIN H1 [get_ports {dn0[3]}]        ;# DN0_K4 LED_BIT4
set_property IOSTANDARD LVCMOS33 [get_ports {dn0[*]}]

#   组1（原理图 LED1_CA..G1/DP1 + LED_BIT5..8）
set_property PACKAGE_PIN D4 [get_ports {seg_grp1[0]}]   ;# A1  LED1_CA
set_property PACKAGE_PIN E3 [get_ports {seg_grp1[1]}]   ;# B1  LED1_CB
set_property PACKAGE_PIN D3 [get_ports {seg_grp1[2]}]   ;# C1  LED1_CC
set_property PACKAGE_PIN F4 [get_ports {seg_grp1[3]}]   ;# D1  LED1_CD
set_property PACKAGE_PIN F3 [get_ports {seg_grp1[4]}]   ;# E1  LED1_CE
set_property PACKAGE_PIN E2 [get_ports {seg_grp1[5]}]   ;# F1  LED1_CF
set_property PACKAGE_PIN D2 [get_ports {seg_grp1[6]}]   ;# G1  LED1_CG
set_property PACKAGE_PIN H2 [get_ports {seg_grp1[7]}]   ;# DP1 LED1_DP
set_property IOSTANDARD LVCMOS33 [get_ports {seg_grp1[*]}]

set_property PACKAGE_PIN G1 [get_ports {dn1[0]}]        ;# DN1_K1 LED_BIT5
set_property PACKAGE_PIN F1 [get_ports {dn1[1]}]        ;# DN1_K2 LED_BIT6
set_property PACKAGE_PIN E1 [get_ports {dn1[2]}]        ;# DN1_K3 LED_BIT7
set_property PACKAGE_PIN G6 [get_ports {dn1[3]}]        ;# DN1_K4 LED_BIT8
set_property IOSTANDARD LVCMOS33 [get_ports {dn1[*]}]

# ---------------- 蓝牙模块控制脚（官方 lab08 工程里的接法；手册 §11 未列出）----------------
# 这 5 根必须由 FPGA 驱动，否则蓝牙模组不上电/一直复位（实测：AT 无应答、手机搜不到）
set_property PACKAGE_PIN D18 [get_ports bt_pw_on]        ;# 模块电源开关
set_property IOSTANDARD LVCMOS33 [get_ports bt_pw_on]
set_property PACKAGE_PIN C16 [get_ports bt_master_slave] ;# 主/从模式选择
set_property IOSTANDARD LVCMOS33 [get_ports bt_master_slave]
set_property PACKAGE_PIN H15 [get_ports bt_sw_hw]
set_property IOSTANDARD LVCMOS33 [get_ports bt_sw_hw]
set_property PACKAGE_PIN E18 [get_ports bt_sw]
set_property IOSTANDARD LVCMOS33 [get_ports bt_sw]
set_property PACKAGE_PIN M2 [get_ports bt_rst_n]         ;# 模块复位（低有效）
set_property IOSTANDARD LVCMOS33 [get_ports bt_rst_n]

# 其余 LED/开关/按键若需要可按下表补充：
# LED0..3: K2 J2 J3 H4 ; LED4..7: J4 G3 G4 F6
# SW0..7 : R1 N4 M4 R2 P2 P3 P4 P5
# PB0..4 : R11 R17 R15 V1 U4
