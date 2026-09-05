# UART 接口集成说明（EES-338 上板）

本文档说明如何把五级流水线 RV32I CPU 与 **UART(TX+RX)** 控制器集成，
并通过 Vivado 2019.2 生成可在 EES-338 开发板上运行的 bitstream。

---

## 1. 总体结构

```
        ┌───────────── 100MHz (T5) ────────────┐
        ▼                                       │
   MMCM(ClockGen.v) ─ 50MHz ────────────────────┤
        │                                       │
   ┌────┴────────────────────────────────────┐  │
   │  EES338Top.v（板上 SoC 顶层）             │  │
   │  ┌─────────────┐    MMIO 窗口译码        │  │
   │  │ PipelineCPU │ ◄──0x1000_0000/04─────►│  │
   │  │ (5级流水,18条)│        │               │  │
   │  └─────────────┘        ▼               │  │
   │   IMEM 0x00400000    UART_TX(UART_TX.v)  │  │
   │   DMEM 0x10010000    UART_RX(UART_RX.v)  │  │
   └──────────────────────────────────────────┘  │
                        │ uart_txd(N5)           │
                        ▼                        ▼
                   CP2102 ◄──► PC(USB串口)    T4 uart_rxd
```

为什么内部降到 **50MHz**：
原 CPU 在 100MHz 下综合/实现后 WNS≈-2.3ns（EX→ALU→分支→PC 同拍关键路径）。
用 MMCM 把板上 100MHz 分频为 50MHz 后 **Setup WNS=+5.3ns，时序完全收敛**，
保证上板稳定。UART 波特率 115200 不变（BAUD_DIV = 50MHz/115200 = 434）。

### 存储器映射（CPU 只靠普通 lw/sw，不新增指令）

| 地址 | 用途 |
|---|---|
| `0x0040_0000` 起 | 指令 ROM（PC 复位初值） |
| `0x1001_0000` ~ `0x10010FFF` | 数据 RAM（1024 字，DataMemory.v） |
| `0x1000_0000` | `UART_DATA`：`sw`=把低 8 位送入 TX；`lw`=读最近 RX 字节并清“可读”位 |
| `0x1000_0004` | `UART_STATUS`：bit0=`TX_BUSY`；bit1=`RX_READY` |

MMIO 窗口判断在 `PipelineCPU.v` 的 MEM 级：`addr[31:16]==16'h1000`。
命中窗口时 `mem_rdata` 改由外设提供、写信号送外设；原 `DataMemory` 基址
`0x10010000` 在窗口之外，天然互不干扰。

---

## 2. 新增/修改的文件

### 新增 RTL（Lab2.srcs/sources_1/new/）
| 文件 | 作用 |
|---|---|
| `ClockGen.v` | MMCME2_BASE：100MHz → 50MHz（Artix-7） |
| `UART_TX.v` | 115200/8N1 发送器，LSB 先发，busy 标志 |
| `UART_RX.v` | 起始位中点确认 + 数据位中点采样接收器 |
| `EES338Top.v` | 板上顶层：MMCM、复位、CPU、MMIO 寄存器、UART 实例、LED 心跳 |

### 修改 RTL
| 文件 | 改动 |
|---|---|
| `PipelineCPU.v` | ①新增参数 `DATA_FILE`；②新增 5 个 MMIO 总线端口（`memio_rdata/read/write/addr/wdata`），纯 CPU 仿真可不接，不影响原测试 |
| `InstructionMemory.v` | 仿真走 `$readmemh`；综合走 `` `ifdef SYNTHESIS`` 字面量初始化（内容由脚本生成，保证进 bitstream） |
| `DataMemory.v` | 同上（数据区内容同样被烘焙进 bitstream） |

### 生成/脚本/文档
| 文件 | 作用 |
|---|---|
| `gen_uart_demo.py` | 生成 `uart_hello.hex` / `uart_hello_mem.hex` / `uart_echo.hex` 及综合用 `imem_boot_init.vh`、`dmem_boot_init.vh` |
| `imem_boot_init.vh` | InstructionMemory 综合初始化的字面量赋值（当前为 hello 程序） |
| `dmem_boot_init.vh` | DataMemory 综合初始化的字面量赋值（当前为 hello 字符串） |
| `Lab2.srcs/constrs_1/new/EES338.xdc` | 引脚约束 + 10ns 主时钟（50MHz 由 MMCM 自动生成） |
| `scripts/run_bitstream.tcl` | 一键 综合→实现→写 bitstream |

### 仿真测试（Lab2.srcs/sim_1/new/）
`tb_uart_tx.v`、`tb_uart_rx.v`（UART 单元级）、`tb_EES338_hello.v`、
`tb_EES338_echo.v`（整机级：CPU 打印/回显，自动 PASS/FAIL）。

---

## 3. 演示程序

### 3.1 hello：**每 burst 连发两条** `Hello, EES-338!`（周期重复）
- 上电立即发送一次，每个 burst **连续发两条**（两条之间无空闲），再间隔约 0.4s 重复；
- 为什么连发两条：部分 USB 转串口桥在“线路空闲后再起传”时会把 burst 开头的 1~N 个
  字节丢掉。连发两条后，若第一条开头被吞，紧接的第二条必然完整 → 屏幕总能读到整行。
程序要点：`auipc` 得到 UART 基址与数据区基址 → 逐字取字符串
（`uart_hello_mem.hex`，内容为两条 Hello）→ 轮询 TX 空闲后 `sw` 发送 → 发完延时再发。

### 3.2 echo：PC 发字符，CPU 原样回显
轮询 `UART_STATUS.bit1`（RX 可读）→ `lw UART_DATA` 读字符
→ 等 TX 空闲 → `sw UART_DATA` 回发。用串口助手发送即可看到回显。

### 3.3 helloecho：**每 burst 连发两条 Hello + 随时 RX 回显**（日常/自检推荐）
- 每个 burst 连续发两条 Hello（无空闲、防吞开头），间隔约 0.8s 重复；
- 同时**每一轮主循环都轮询 RX**：PC 任何时候发来字节都会立即原样回显
  （回显优先，与打印互不干扰、不丢字节）；
- 一次下载即可同时验证 TX（连发两条 Hello）与 RX+TX（回显）。
生成：`python gen_uart_demo.py helloecho`，产出 `uart_helloecho.hex`。

> 注意：AUIPC 立即数加的是“当前指令 PC”。第二条 `auipc x11,0x0fc10`
> 在 PC+8 处执行，算出的地址是 `0x10010008`，所以 hello 程序里补了
> `addi x11,x11,-8` 修正到 `0x10010000`。若自己改程序，务必核对基址。

---

## 4. 操作步骤

### 4.1 生成/切换演示程序（可选）
```powershell
cd e:\VivadoProject\Lab2
python gen_uart_demo.py hello       # 上电打印 Hello（默认，init 同步成 hello）
python gen_uart_demo.py helloecho   # 自检：先打印 Hello 再回显（TX+RX 全测）
python gen_uart_demo.py echo        # 纯回显
```
切换程序后要重新生成 bitstream（见 4.3）。

### 4.2 仿真（任选）
* **Vivado GUI**：打开 `Lab2.xpr` → 在 sim 中把顶层选为
  `tb_EES338_hello`（或 `tb_uart_tx` 等）→ Run Behavioral Simulation。
* **命令行（本机已配好 unisims 流程）**：参见开发日志中 xvlog/xelab/xsim 用法；
  若要仿真含 MMCM 的整机，需要编译 unisims 库。

### 4.3 生成 bitstream
```powershell
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -source E:/VivadoProject/Lab2/scripts/run_bitstream.tcl
```
产物：
```
E:/VivadoProject/Lab2/Lab2.runs/impl_1/EES338Top.bit   （当前 gen 模式对应的 bit）
```
已归档（不会被重新综合清掉）：
```
bitstream/EES338Top_hello.bit        hello：每 burst 连发两条 Hello，约0.4s一次（TX 测试）
bitstream/EES338Top_helloecho.bit    hello+echo：连发两条 + 随时回显（TX/RX 全测，推荐）
```
> 引脚已按上板实测修正（uart_txd→T4、uart_rxd→N5），直接用即可；
> 早期用于定位问题的 `EES338Top_hello_swap.bit` 已废弃删除。
> 注意：`Lab2.runs/impl_1` 目录会在每次重新综合时被清空重建，别把备份放里面。

报告在 `scripts/`：synth_util.rpt / synth_timing.rpt / impl_util.rpt / impl_timing.rpt。
（已实测：xc7a35tcsg324-1，实现后 **Setup WNS=+5.3ns@50MHz 收敛**，DRC 0 错误。）

> 脚本会自动把工程器件改为 `xc7a35tcsg324-1`、把顶层设为 `EES338Top`、
> 加入新源文件与约束。工程 `Lab2.xpr` 目前已经是该配置。

### 4.4 下载与观察
1. USB 线连接 EES-338 的 **Type-C** 口（USB-UART / USB-JTAG 一体）；
2. 若 PC 未识别串口，先装 **CP210x VCP 驱动**；
3. Vivado Hardware Manager 打开 JTAG，加载 `EES338Top.bit`；
4. 打开串口助手/终端，选 COM 口，**波特率 115200，8 数据位，无校验，1 停止位**；
5. 下载完成即收到 `Hello, EES-338!`（LED0 心跳闪烁）；发送字符可看到回显（echo 模式）。

### 4.5 串口读写逐项自检方法（PC 端即可完成，不需要示波器）

**前提**：设备管理器能看到 COM 口（CP210x 驱动）；串口助手设 **115200-8-N-1**。

**① 只测 TX（发送）—— 下载 `EES338Top_hello.bit`**
1. Vivado Hardware Manager 加载 `bitstream/EES338Top_hello.bit`；
2. 打开串口助手，应看到**每个 burst 连续出现两行** `Hello, EES-338!`，约 0.4s 一组；
   （第一条偶尔被吞掉开头也无妨，紧跟的第二条必然完整）
3. 按复位键也照常周期输出 → 证明 TX 每次启动都正常（丢开头也没关系，下一条马上又来了）。

**② RX 回显 —— 下载 `bitstream/EES338Top_helloecho.bit` 后**：
1. 上电即周期收到 `Hello, EES-338!`（顺带验证 TX）；
2. 在串口助手“发送区”输入任意字符/字符串后点发送（发送新行可关可不关）；
3. PC 端应**原样收到你发的每个字节**，即输入 `abc` 回显 `abc`。
   - 回显成功 ⇒ RX 路径（N5 收 → CPU 读 → T4 回发）完整正确；
   - 能看到周期 Hello 但收不到回显 ⇒ 问题在 RX 方向/接线（N5）；
   - 周期 Hello 与回显都没有 ⇒ 先查 TX（T4）方向/接线与 COM/波特率。

**③ 用终端软件逐字回显**（可选）：XShell/PuTTY 等终端下，helloecho 模式每敲一键应
立刻回显一字符（关掉终端的“本地回显 Local Echo”，否则无法区分）。

**④ 串口环回接线检查（硬件级）**：板子断电，把 UART 两脚 **T4 与 N5 短接**再上电跑
helloecho：此时发送的字节会“自收自回”，你随便发一个字符如 `k`，屏幕上会持续出现
大量 `k`（板子把它不断回环回显）。注意 hello 本来就周期重发，所以判断要以“发一个字符后
出现该字符洪流”为准，而不是看 Hello 重复。

**⑤ 如果上述都无输出**，用万用表/示波器量 **T4**（实测输出脚）在发送期间是否有约
115200 的跳变；或换一条 Type-C 数据线/USB 口再试。

---

## 5. 已实测确认 / 待确认项

1. ✅ **引脚方向（已实测确认，XDC 已按此修正）**：本板 USB-UART(CP2102) 的实际走线
   与手册第 9 节标注**相反**——正确接法是 **`uart_txd → T4`(FPGA 出)、`uart_rxd → N5`(FPGA 入)**。
   曾用手册方向出 bit 收不到数据，换成上表接法后立即收到 Hello。
2. **IO 电平**：约束统一按 **3.3V LVCMOS33**（含配置电压 3.3V）。若与板子实测
   bank 电压不符，改 `EES338.xdc`；
3. **复位键 P15 低有效**：即使极性相反，上电也会自动复位约 255 拍后运行
   （`EES338Top.v` 内 `rst_cnt`），按键只作可选的手动复位。若按复位没反应，把
   `cpu_rst` 里 `~rst_btn` 改成 `rst_btn` 即可。

---

## 6. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 下载后无输出 | 检查串口号/波特率(115200)；确认 CP210x 驱动；确认约束引脚正确 |
| 打印乱码 | 波特率不匹配（终端必须 115200-8N1） |
| 想换演示程序 | 运行 `gen_uart_demo.py` 选择 hello/echo，再重新跑 run_bitstream.tcl |
| 想恢复 100MHz | 移除 `ClockGen.v` 例化并让 `cpu_clk=sys_clk`，BAUD_DIV 改回 868；但时序有违例，不推荐 |
| 只想要 TX | 不用管 RX 程序逻辑，hello 模式已经满足；`uart_rxd` 悬空/置高均可 |

---

## 7. 设计要点（写报告用）
- CPU 侧零改动指令集，外设通过 **存储器映射**（lw/sw）访问；
- `PipelineCPU.v` 只新增了 MEM 级 MMIO 总线端口，**CPU 原有流水线逻辑与全部旧测试均未受影响**；
- 程序/字符串 ROM 内容通过 `` `ifdef SYNTHESIS`` 分支的字面量初始化文件
  （`imem_boot_init.vh`/`dmem_boot_init.vh`）烘焙进 bitstream，不依赖综合时读文件；
- UART 发送采用“轮询 busy”握手，接收采用“RX_READY + 读数据自动清位”握手，
  代码逻辑少、易仿真、易讲解；
- 性能对比仍按原方案用 CPI/CPU 时间，此处 UART 为挂接外设，不改变 CPU 性能指标。
