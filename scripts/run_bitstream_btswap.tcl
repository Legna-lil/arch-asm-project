# =============================================================================
# run_bitstream_btswap.tcl - 出第二份 bitstream：把蓝牙 TX/RX 两个引脚对调
#
#   用法（Windows PowerShell）：
#     & 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace `
#         -source E:/VivadoProject/Lab2/scripts/run_bitstream_btswap.tcl
#
#   产物：Lab2.runs/impl_1/EES338Top.bit（归档为 bitstream/EES338Top_btat_swap.bit）
#   目的：本板手册曾把 USB-UART 的 TX/RX 标反，蓝牙手册标注同样可疑；
#         与正常版本做 A/B 对比，判断哪种接法才是对的（见文档 §4.6）。
#   出这份前请先跑 `python gen_uart_demo.py btat`（烘焙 AT 探针程序）。
# =============================================================================

set btswap 1
source [file join [file dirname [info script]] run_bitstream.tcl]
