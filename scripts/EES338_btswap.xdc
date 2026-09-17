# =============================================================================
# EES338_btswap.xdc - 可选约束：把蓝牙 TX/RX 两个引脚对调（A/B 对比用）
#
#   只为 run_bitstream_btswap.tcl 服务：正常构建时这个文件**不加进工程**。
#   动机：本板手册曾把 USB-UART 的 TX/RX 标反（实测方向与手册相反），
#         蓝牙手册标注同样可疑，于是出两份 bitstream 让实物决定：
#           · 正常版：bt_txd -> N2，bt_rxd -> L3（手册默认）
#           · 对调版：bt_txd -> L3，bt_rxd -> N2（本文件）
#   端口方向不变，只是"哪个脚接哪个信号"换了。
# =============================================================================

set_property PACKAGE_PIN L3 [get_ports bt_txd]
set_property PACKAGE_PIN N2 [get_ports bt_rxd]
