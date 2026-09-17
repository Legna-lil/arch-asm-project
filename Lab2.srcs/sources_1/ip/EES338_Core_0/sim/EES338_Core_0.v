// (c) Copyright 1995-2026 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
// DO NOT MODIFY THIS FILE.


// IP VLNV: ees338.bjut:ip:EES338_Core:1.0
// IP Revision: 1

`timescale 1ns/1ps

(* IP_DEFINITION_SOURCE = "package_project" *)
(* DowngradeIPIdentifiedWarnings = "yes" *)
module EES338_Core_0 (
  clk,
  rst,
  uart_rxd,
  uart_txd,
  bt_rxd,
  bt_txd,
  lcd_d,
  lcd_wr_n,
  lcd_rd_n,
  lcd_cs_n,
  lcd_rs,
  lcd_rst_n,
  seg_grp0,
  dn0,
  seg_grp1,
  dn1
);

(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK, ASSOCIATED_RESET RST, FREQ_HZ 100000000, PHASE 0.000, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK CLK" *)
input wire clk;
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST, POLARITY ACTIVE_HIGH, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST RST" *)
input wire rst;
input wire uart_rxd;
output wire uart_txd;
input wire bt_rxd;
output wire bt_txd;
output wire [7 : 0] lcd_d;
output wire lcd_wr_n;
output wire lcd_rd_n;
output wire lcd_cs_n;
output wire lcd_rs;
output wire lcd_rst_n;
output wire [7 : 0] seg_grp0;
output wire [3 : 0] dn0;
output wire [7 : 0] seg_grp1;
output wire [3 : 0] dn1;

  EES338_Core #(
    .HEX_FILE("../../../../Lab2.file/uart_hello.hex"),
    .DATA_FILE("../../../../Lab2.file/uart_hello_mem.hex"),
    .BAUD_DIV(434),
    .BAUD_DIV_BT(5208),
    .LCD_WR_CYCLES(10),
    .LCD_RST_CYCLES(200000),
    .SEG_SCAN_DIV(16384),
    .SEG_GROUP_SWAP(1),
    .SEG_REVERSE_K(1),
    .TIMER_DELAY(20000000)
  ) inst (
    .clk(clk),
    .rst(rst),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .bt_rxd(bt_rxd),
    .bt_txd(bt_txd),
    .lcd_d(lcd_d),
    .lcd_wr_n(lcd_wr_n),
    .lcd_rd_n(lcd_rd_n),
    .lcd_cs_n(lcd_cs_n),
    .lcd_rs(lcd_rs),
    .lcd_rst_n(lcd_rst_n),
    .seg_grp0(seg_grp0),
    .dn0(dn0),
    .seg_grp1(seg_grp1),
    .dn1(dn1)
  );
endmodule
