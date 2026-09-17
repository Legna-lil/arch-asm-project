# EES338 五级流水线 RISC-V SoC（计组 + 汇编 课程项目）

EES-338 开发板（`xc7a35tcsg324-1`，Artix-7，Vivado 2019.2）上的一个完整 SoC：

* **计组部分**：五级流水线 RV32I CPU（硬布线控制器、数据前递、load-use 停顿、分支冲刷、
  **溢出检测/标志寄存器**、**M 扩展乘除法**），源码在 `Lab2.srcs/sources_1/new/cpu/`；
* **汇编部分**：存储器映射外设与驱动程序 —— USB-UART(115200) / **蓝牙 BLE(9600)** /
  JLX128128 LCD / 8 位数码管，源码在 `Lab2.srcs/sources_1/new/periph/`，
  演示程序（`.hex`）在 `Lab2.file/`，由 `*.py` 生成器产出。

> 本次新增功能（**溢出检测改进 / 蓝牙接口 / 封装 IP 核**）的说明见
> [`docs/报告_新增功能.md`](docs/报告_新增功能.md)；
> 完整接口与实现细节见 [`docs/接口设计与IP核封装说明.md`](docs/接口设计与IP核封装说明.md)。

---

## 1. 仓库结构

```
Lab2.xpr                        Vivado 工程（顶层 EES338Top，器件 xc7a35tcsg324-1）
Lab2.srcs/
├── sources_1/new/cpu/          【计组】五级流水线 CPU
│   ├── PipelineCPU.v            流水线主体（IF/ID/EX/MEM/WB + 前递/停顿/冲刷/EX-stall）
│   ├── ALU.v                    算术逻辑单元（含每类运算的溢出判据）+ M 扩展乘除
│   ├── DivUnit.v                多周期除法器（除零 / INT_MIN÷-1 溢出判定）
│   ├── FlagReg.v                标志寄存器 SF/ZF/CF/OF/OF_STICKY/PF + 溢出计数
│   ├── ControlUnit.v            主控制器（含 rdflags/clrflags 自定义指令译码）
│   ├── RegisterFile.v PC.v ImmediateGenerator.v
│   ├── InstructionMemory.v DataMemory.v
│   └── macro.vh imem_boot_init.vh dmem_boot_init.vh   （综合引导用头文件）
├── sources_1/new/periph/       【汇编】外设 + SoC 顶层
│   ├── EES338Top.v              板级顶层（MMCM 时钟 + 引脚）
│   ├── EES338_Core.v            SoC 内核（可封装成 IP 核）
│   ├── PeriphMMIO.v             总线/地址译码（UART、蓝牙、LCD、数码管、定时器、CPU_FLAGS）
│   ├── UartChannel.v UART_TX.v UART_RX.v       串口通道（USB-UART 与蓝牙共用）
│   ├── LCD128128.v SegDisplay.v SimpleTimer.v  LCD / 数码管 / 定时器
│   └── ClockGen.v               100MHz → 50MHz MMCM
├── sim_1/new/cpu/              【计组】16 个 testbench（全部自检，见 §3）
├── sim_1/new/periph/           【汇编】18 个 testbench（外设单测 + 整机 SoC）
└── constrs_1/new/EES338.xdc    引脚/时序约束
Lab2.file/                      程序与数据 hex（33 个，RTL 用 $readmemh 加载）
bitstream/                      已生成的 bitstream（各演示程序各一份）
ip_repo/EES338_Core/            封装好的 IP 核（component.xml + src）
scripts/                        仿真/出 bit/封装 IP 的脚本
docs/                           说明文档 + 新增功能报告
*.py                            汇编演示程序生成器（asm.py 等）
```

## 2. 快速使用

```powershell
# ① 全部 34 个 testbench 一键回归（命令行，不需要 GUI）
powershell -File scripts\run_sim.ps1                 # 全部
powershell -File scripts\run_sim.ps1 -Group cpu       # 只跑计组（16 个）
powershell -File scripts\run_sim.ps1 -Group periph    # 只跑汇编（18 个）
powershell -File scripts\run_sim.ps1 -Tb tb_overflow  # 单个

# ② 生成演示程序 hex（例：蓝牙→数码管演示）
python gen_uart_demo.py btseg        # 产出 Lab2.file/bt_seg.hex / bt_seg_mem.hex

# ③ 出 bitstream（综合+实现+写 bit，产物 Lab2.runs/impl_1/EES338Top.bit）
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch `
  -source scripts/run_bitstream.tcl -notrace

# ④ 重新封装 IP 核（产物 ip_repo/EES338_Core/component.xml）
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch `
  -source scripts/package_ip.tcl -notrace
```

> GPU/GUI 之外只需要 `xvlog/xelab/xsim`；脚本里 Vivado 路径可用 `-VivadoBin` 覆盖。

## 3. 回归结果

`scripts/run_sim.ps1` 一键跑 **34/34 ALL PASS**：

| 分类 | 个数 | testbench |
|------|------|-----------|
| 计组（CPU/溢出/乘除/流水线冒险） | 16 | tb_ALU、tb_alu_flags、tb_divunit、tb_overflow、tb_forward、tb_hazard、tb_branch、tb_inst_alu、tb_muldiv、tb_compare、tb_CPU、tb_CPU_pipeline、tb_CPU_singlecycle、tb_PC_IM、tb_RegisterFile、tb_ImmGen |
| 汇编（外设 + 整机） | 18 | tb_uart_tx/rx、tb_lcd128128、tb_segdisplay、tb_EES338_lcd/lcdtest/lcdread、tb_EES338_bt/btcheck/btat/btcfg/btseg、tb_EES338_sort、tb_EES338_flags、tb_flags、tb_EES338_hello/echo/helloecho |

## 4. 演示程序与对应 bitstream

| 演示 | 程序（`Lab2.file/`） | bitstream（`bitstream/`） |
|------|----------------------|---------------------------|
| Hello UART | `uart_hello.hex` | `EES338Top_hello.bit` |
| UART 回显 | `uart_echo.hex` | `EES338Top_echo.bit` |
| **蓝牙：手机字符 → 数码管** | `bt_seg.hex` | `EES338Top_btseg.bit` |
| 蓝牙 AT 探针 / 模式扫描 | `bt_at.hex` / `bt_cfg.hex` | `EES338Top_btat.bit` / `..._btcfg.bit` |
| 排序演示（数码管） | `seg_sort.hex` | `EES338Top_sort.bit` |
| 溢出/标志位演示 | `flags_demo.hex` | `EES338Top_flags.bit` |
| LCD 演示 | `lcd_demo.hex` | `EES338Top_lcd.bit` |

## 5. 存储器映射（MMIO）

| 地址 | 名称 | 说明 |
|------|------|------|
| `0x1000_0000` / `0x0004` | UART_DATA / UART_STATUS | USB-UART 收/发（115200）|
| `0x1000_0010` / `0x0014` / `0x0018` | BT_DATA / BT_STATUS / **BT_CTRL** | 蓝牙收/发/控制脚（9600，复位值 0x1B）|
| `0x1000_0100`~`0x010C` | LCD_CMD / LCD_DAT / LCD_STATUS / LCD_CTRL | LCD 命令/数据 |
| `0x1000_0200` / `0x0204` | SEG_DATA / SEG_CTRL | 8 位数码管 |
| `0x1000_0300` / `0x0304` | **CPU_FLAGS** / **OF_COUNT** | 标志寄存器 / 溢出累计次数（只读）|

自定义指令：`clrflags`（清标志）、`rdflags rd`（读标志），编码见 `cpu/macro.vh` 与 `cpu/ControlUnit.v`。
