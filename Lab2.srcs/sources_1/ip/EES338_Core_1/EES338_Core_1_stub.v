// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
// Date        : Thu Sep 17 14:21:23 2026
// Host        : LAPTOP-DQ5VL70C running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               e:/VivadoProject/Lab2/Lab2.srcs/sources_1/ip/EES338_Core_1/EES338_Core_1_stub.v
// Design      : EES338_Core_1
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a35tcsg324-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "EES338_Core,Vivado 2019.2" *)
module EES338_Core_1(clk, rst, uart_rxd, uart_txd, bt_rxd, bt_txd, lcd_d, 
  lcd_wr_n, lcd_rd_n, lcd_cs_n, lcd_rs, lcd_rst_n, seg_grp0, dn0, seg_grp1, dn1)
/* synthesis syn_black_box black_box_pad_pin="clk,rst,uart_rxd,uart_txd,bt_rxd,bt_txd,lcd_d[7:0],lcd_wr_n,lcd_rd_n,lcd_cs_n,lcd_rs,lcd_rst_n,seg_grp0[7:0],dn0[3:0],seg_grp1[7:0],dn1[3:0]" */;
  input clk;
  input rst;
  input uart_rxd;
  output uart_txd;
  input bt_rxd;
  output bt_txd;
  output [7:0]lcd_d;
  output lcd_wr_n;
  output lcd_rd_n;
  output lcd_cs_n;
  output lcd_rs;
  output lcd_rst_n;
  output [7:0]seg_grp0;
  output [3:0]dn0;
  output [7:0]seg_grp1;
  output [3:0]dn1;
endmodule
