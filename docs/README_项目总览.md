# arch-asm-project
北理工大四计组与汇编课程设计
## 计组部分
基于大三下计组 单周期流水线CPU 搭建，实现 五级流水线 + 硬布线 + 溢出检测
### 调整
- 五级流水线： [./Lab2.srcs/sources_1/new/PipelineCPU.v](./Lab2.srcs/sources_1/new/PipelineCPU.v)
- 模块：ALU, ControlUnit（微指令控制信号）, DataMemory（数据内存）, InstructionMemory（指令内存）, RegisterFile, PC, ImmediateGenerator
- 测试用例： [./Lab2.srcs/sim_1/new/tb_CPU.v](./Lab2.srcs/sim_1/new/tb_CPU.v) —— 执行一个冒泡排序程序；预计 CPI=1.4；其余为具体模块的单元测试

## 汇编部分
实现 UART 接口，能够通过串口双向交换信息。

顶层模块：[./Lab2.srcs/sources_1/new/EES338Top.v](./Lab2.srcs/sources_1/new/EES338Top.v)

详见 [./UART集成说明.md](./UART集成说明.md)

## 扩展接口（LCD / 蓝牙 / 数码管）与 IP 核封装

在原有 UART 之外又增加了三个板载接口，并把整个 SoC 内核封装成了 Vivado IP 核：

- **LCD**：板载 JLX128128G-81202（ST7571，8080 并口），`0x1000_0100~` 四个 MMIO 寄存器，
  CPU 轮询 busy 后写命令/数据；演示程序显示 `EES-338` / `LCD OK`。
  `LCD_CTRL.bit1/bit2` 是**运行时调试开关**（RST 极性取反 / WR#-RD# 互换），
  配套自检程序 `lcdtest` 会自动试 8 种配置并把 `CFG r s v` 打到串口。
- **蓝牙**：板载 BLE-CC41-A（9600），复用 `UartChannel`（与 USB-UART 只差一个 `BAUD_DIV`），
  `0x1000_0010/14` 两个寄存器；自检程序 `btcheck` 周期发 'K' 并把收到的字节打印成 `RX=<字符>`
  （短接 N2↔L3 即可做硬件环回冷测）。
  ⚠️ **关键（官方 lab08 才有的信息）**：模组的**电源/复位/模式**由 FPGA 另外 5 根脚驱动
  （`bt_pw_on`=D18、`bt_rst_n`=M2、`bt_master_slave`=C16、`bt_sw_hw`=H15、`bt_sw`=E18），
  用户手册 §11 **没写**。现在已实现为 **`0x1000_0018 BT_CTRL`**（复位默认 0x1B = 上电+从模式+释放复位，
  上电先给 20ms 复位脉冲），`bt`/`btcheck`/`btat` 程序启动时都会先给模块上电+复位一次 ——
  详见文档 §4.7；另注意**广播/配对是模组固件行为**，且 Windows 自带蓝牙界面看不到 BLE 透传模块（要用 nRF Connect）。
  ✅ **实测结论（模式脚扫描 `btcfg` 定位）**：可用配置就是默认的 **`BT_CTRL = 0x1B`**（`T5 m1 h0 s1` 时模组灯常亮 = 手机连上）；
  而"能扫到却连接超时"的原因是 **`btat`/`btat2` 在发 AT 命令**（模组处于命令交互状态时不接受连接）——
  所以**给手机用的演示请用 `EES338Top_bt.bit`（纯回显，全程不发 AT）**。见文档 §4.8。
- **8 位数码管**：板载 2 组×4 位动态扫描（硬件刷新，不占 CPU 时间），
  `0x1000_0200+4*i` 写每位数字 + `0x1000_0240/244/248` 控制/硬件延时；
  演示程序把**五整数冒泡排序的全过程**演出来（高亮当前比较的两位 → 数值当场互换 →
  最终 `1 3 5 7 9`），既是验收视频素材，也是"流水线算得对"的板级证据。
  左右顺序由顶层参数 `SEG_GROUP_SWAP` / `SEG_REVERSE_K` 描述（**默认已按本板实测设定为 1/1**，
  dig0..dig7 即从左到右）。
- **IP 核**：`EES338_Core.v`（CPU + 全部外设）被封装为 `ees338.bjut:ip:EES338_Core:1.0`，
  产物 `ip_repo/EES338_Core/component.xml`，并已用 Block Design（clk_wiz + proc_sys_reset）综合验证通过。

## 溢出标志位迁移 + M 扩展乘除法（本次新增）

按需求把 **Lab1 进阶 ALU** 里的"溢出标志位与处理方法"迁移进流水线 CPU，并顺手把乘除法也加了进来：

- **标志位**（`FlagReg.v`）：SF/ZF/CF/OF/PF 一起寄存（Lab1 做法）+ **粘滞溢出位 `OF_STICKY`** +
  **溢出计数 `OF_COUNT`**；只由**算术类**指令（ADD/SUB/ADDI/MUL/DIV/REM）刷新，
  `lw/sw/auipc` 等地址计算不会误报也不会把标志冲掉。
- **读/清标志**：自定义指令 `rdflags rd`（读标志到 rd）与 `clrflags`（清标志，对应 Lab1 的 CLR）；
  另把标志与计数暴露成 MMIO：`0x1000_0300 CPU_FLAGS`、`0x1000_0304 OF_COUNT`（普通 `lw` 可读）。
- **M 扩展**：`mul/mulh/mulhu/mulhsu`（单周期，DSP48）+ `div/divu/rem/remu`（多周期 `DivUnit.v`，
  加减交替法迁移自 Lab1 `mult_alu.v`，EX 级停顿 33 拍，收尾拍写 EX/MEM 可直接前递）。
  MUL 的溢出判据与 Lab1 完全一致（64 位积能否被低 32 位符号扩展表示）；除零与 `INT_MIN÷(-1)` 置 OF=1。
- **上板演示**：`bitstream/EES338Top_flags.bit` —— 8 位数码管逐位显示 `SF ZF CF OF STK PF SEEN CNT`，
  循环 5 个场景（溢出加法 → 不溢出加法 → 借位减法 → 乘法溢出 → `clrflags`）。
- 迁移动机、与 Lab1 的差异、时序问题（WNS 曾被乘法器拖到 -0.009ns，用独立分支比较器修复）与
  完整验证记录见 [./接口设计与IP核封装说明.md](./接口设计与IP核封装说明.md) **§11**。

| 目标 | 命令 |
|---|---|
| 一键仿真（全部 23 个 tb：ALU/标志/除法单元 + CPU 级 M 扩展 + 整机 LCD/蓝牙/数码管/标志） | `powershell -File scripts\run_sim.ps1` |
| 生成演示程序（hello/helloecho/echo/**bt**/**lcd**/**sort**/**lcdtest**/**btcheck**/**flags**） | `python gen_uart_demo.py flags` |
| 出 bitstream | `vivado -mode batch -source scripts/run_bitstream.tcl` |
| **封装 IP 核** | `vivado -mode batch -source scripts/package_ip.tcl` |
| **用 IP 搭 Block Design 并综合** | `vivado -mode batch -source scripts/build_bd_demo.tcl` |

详见 [./接口设计与IP核封装说明.md](./接口设计与IP核封装说明.md)

> 接口功能部分（LCD/蓝牙/数码管/IP 封装）**没有改动 CPU 内部逻辑**：新功能全部是新文件 +
> `EES338Top.v`/`EES338.xdc` 的增量改动。
> 之后的"溢出标志位迁移"按需求**有意修改了** `ALU.v` / `ControlUnit.v` / `PipelineCPU.v`
> （新增 `FlagReg.v` / `DivUnit.v`），改动清单见文档 §11；`RegisterFile.v`、`PC.v`、
> `ImmediateGenerator.v`、`DataMemory.v`、`InstructionMemory.v`、`UART_TX/RX.v` 仍未改动。

### 已归档的 bitstream（一个 bit ≈ 一个演示程序）

| 文件 | 现象 |
|---|---|
| `bitstream/EES338Top_sort.bit` | 数码管演五整数排序（`9 3 7 1 5` → `1 3 5 7 9`，循环） |
| `bitstream/EES338Top_flags.bit` | **溢出标志位演示**：数码管逐位显示 `SF ZF CF OF STK PF SEEN CNT`，循环 5 个场景 |
| `bitstream/EES338Top_lcd.bit` | 串口（115200-8N1）收到 `LCD OK`，板载 LCD 显示 `EES-338` / `LCD OK` |
| `bitstream/EES338Top_lcdtest.bit` | **LCD 诊断 v3**：串口 `C<k>/A/P/EV01234567`；屏上依次应出现 0xA5 全屏变黑 → 半屏图案（左黑右白）→ 8 档对比度扫描 |
| `bitstream/EES338Top_lcdread.bit` | **LCD 读回自检**：写 `0x5A/0x3C` 进显示 RAM 再读回，数码管逐位 + 串口打印 `1=xxxxxxxx`（判读表见文档 §3.5） |
| `bitstream/EES338Top_bt.bit` | 手机 BLE 助手（9600）发什么回什么（程序启动先给模块上电+复位） |
| `bitstream/EES338Top_btcheck.bit` | **蓝牙诊断**：周期发 'K' + 把收到的字节打印成 `RX=<字符>`（短接 N2↔L3 可做环回冷测） |
| `bitstream/EES338Top_btat.bit` | **蓝牙 AT 探针**：轮流传 `AT`/`AT\r\n`/`AT+NAME?\r\n` 并打印模组回显（实测上板后 **`B: OK`** = 模组活了，见文档 §4.7） |
| `bitstream/EES338Top_btat2.bit` | **蓝牙 AT 探索器**：问版本/名字/MAC/角色/波特率 + `AT+RESET` 重新广播（用来确定模块型号与 AT 集） |
| `bitstream/EES338Top_btseg.bit` | **蓝牙→数码管**：手机发字符 → 数码管 16 进制滚动显示最近 4 个字节（最新带小数点）+ 原样回发 + 串口 `RX=<字符>`（见文档 §4.9） |
| `bitstream/EES338Top_btcfg.bit` | **蓝牙模式脚扫描**：8 种 `BT_CTRL` 组合各停 10s，串口打印 `T<k> m.. h.. s..`，用来找出"手机能连上"的模式（见文档 §4.8） |
| `bitstream/EES338Top_btat_swap.bit` | 同上但**蓝牙两脚对调**（`bt_txd→L3`、`bt_rxd→N2`），与上一份做 A/B 对比（本板手册有把 UART TX/RX 标反的先例） |
| `bitstream/EES338Top_helloecho.bit` | 串口周期 `Hello, EES-338!` + 字符回显 |
| `bitstream/EES338Top_hello.bit` | 串口周期 `Hello, EES-338!` |

详见 [./接口设计与IP核封装说明.md](./接口设计与IP核封装说明.md) 的 §1.3「上板验证速查」。

