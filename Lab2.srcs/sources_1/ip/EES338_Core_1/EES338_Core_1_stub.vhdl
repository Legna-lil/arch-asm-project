-- Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
-- Date        : Thu Sep 17 14:21:23 2026
-- Host        : LAPTOP-DQ5VL70C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               e:/VivadoProject/Lab2/Lab2.srcs/sources_1/ip/EES338_Core_1/EES338_Core_1_stub.vhdl
-- Design      : EES338_Core_1
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a35tcsg324-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity EES338_Core_1 is
  Port ( 
    clk : in STD_LOGIC;
    rst : in STD_LOGIC;
    uart_rxd : in STD_LOGIC;
    uart_txd : out STD_LOGIC;
    bt_rxd : in STD_LOGIC;
    bt_txd : out STD_LOGIC;
    lcd_d : out STD_LOGIC_VECTOR ( 7 downto 0 );
    lcd_wr_n : out STD_LOGIC;
    lcd_rd_n : out STD_LOGIC;
    lcd_cs_n : out STD_LOGIC;
    lcd_rs : out STD_LOGIC;
    lcd_rst_n : out STD_LOGIC;
    seg_grp0 : out STD_LOGIC_VECTOR ( 7 downto 0 );
    dn0 : out STD_LOGIC_VECTOR ( 3 downto 0 );
    seg_grp1 : out STD_LOGIC_VECTOR ( 7 downto 0 );
    dn1 : out STD_LOGIC_VECTOR ( 3 downto 0 )
  );

end EES338_Core_1;

architecture stub of EES338_Core_1 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk,rst,uart_rxd,uart_txd,bt_rxd,bt_txd,lcd_d[7:0],lcd_wr_n,lcd_rd_n,lcd_cs_n,lcd_rs,lcd_rst_n,seg_grp0[7:0],dn0[3:0],seg_grp1[7:0],dn1[3:0]";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "EES338_Core,Vivado 2019.2";
begin
end;
