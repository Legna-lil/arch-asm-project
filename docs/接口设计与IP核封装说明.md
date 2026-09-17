# 汇编/接口部分设计说明（UART / LCD / 蓝牙 / 数码管 + Vivado IP 核封装）

> 本文档把「五级流水线 CPU 之外的所有接口工作」整合成一份，包含：
> **USB-UART、LCD、蓝牙、8 位数码管**四个接口 + **把整个 SoC 内核封装成 Vivado IP 核**，
> 以及设计、软件协议、演示程序、仿真/上板验证记录、复现命令与风险说明。
> 面向课程最终验收与报告/答辩。

---

## 0. 选型结论

| 候选接口 | 器件/线材（依据 EES-338 手册） | 是否需要额外器材 | 结论 |
|---|---|---|---|
| VGA（§7） | J1，14 位（RGB 各 4 位 + HS/VS），引脚 F5…C4 | **需要 VGA 线 + 显示器** | ❌ 放弃（无器材，无法验证） |
| USB-UART（§9） | 板载 CP2102，T4/N5 | 不需要 | ✅ 已实现（原有功能） |
| **LCD（§13）** | 板载 **JLX128128G-81202**（驱动 IC ST7571），8080 并口 13 根脚 | **不需要任何线材** | ✅ 已实现 |
| **蓝牙（§11）** | 板载 **BLE-CC41-A**，走串口（N2/L3），默认 9600 | 不需要线材（验证需手机 BLE App） | ✅ 已实现 |
| **数码管（§6.4）** | 板载 8 位数码管，2 组×4 位动态扫描（16 段选 + 8 位选） | 不需要 | ✅ 已实现（★ 排序过程可视化） |

---

## 1. 系统总览

```
        sys_clk(T5,100MHz) ─► ClockGen(MMCM) ─► cpu_clk(50MHz)
                                    │
   ┌────────────────────────────────▼─────────────────────────────────┐
   │ EES338Top.v （板级胶水：MMCM + 上电/按键复位 + 两级同步 + LED 心跳）│
   │  ┌────────────────────────────────────────────────────────────┐  │
   │  │ EES338_Core.v  ← 这一个模块被封装成 IP 核                    │  │
   │  │   ┌──────────────────┐        MEM 级 MMIO(addr[31:16]==1000)│  │
   │  │   │ PipelineCPU.v    │◄──────────────┐                      │  │
   │  │   │ 五级流水 RV32I   │               │                      │  │
   │  │   └──────────────────┘               ▼                      │  │
   │  │   IMEM 0x0040_0000   ┌───────────────────────────────┐      │  │
   │  │   DMEM 0x1001_0000   │ PeriphMMIO.v  地址译码 + 外设    │      │  │
   │  │                      │  ├ UartChannel#1 → USB-UART    │      │  │
   │  │                      │  ├ UartChannel#2 → 蓝牙 BLE     │      │  │
   │  │                      │  ├ LCD128128.v   8080 并口      │      │  │
   │  │                      │  ├ SegDisplay.v  8 位数码管扫描  │      │  │
   │  │                      │  └ SimpleTimer.v 硬件延时/定时  │      │  │
   │  │                      └───────────────────────────────┘      │  │
   │  └────────────────────────────────────────────────────────────┘  │
   └──┬──────────┬───────────┬──────────────┬───────────────────────┘
      │          │           │              │
  CP2102      BLE-CC41-A  JLX128128G/ST7571  8 位数码管
  T4/N5        N2/L3      D0-D7/WR#/RD#/CS#/RS/RST#   2 组×4 位扫描
```

### 1.1 存储器映射（CPU 只用普通 `lw/sw`，**未新增任何指令**）

| 地址 | 名称 | 读 | 写 |
|---|---|---|---|
| `0x1000_0000` | UART_DATA | 最近收到的字节（读后清 ready） | 低 8 位送 USB-UART 发送器 |
| `0x1000_0004` | UART_STATUS | bit0=TX_BUSY，bit1=RX_READY | — |
| `0x1000_0010` | BT_DATA | 最近收到的字节（读后清 ready） | 低 8 位送蓝牙发送器 |
| `0x1000_0014` | BT_STATUS | bit0=TX_BUSY，bit1=RX_READY | — |
| `0x1000_0018` | **BT_CTRL** | — | 蓝牙模块**电源/复位/模式**控制脚（官方 lab08 才有的信息！）<br>bit0=`bt_pw_on`(D18) bit1=`bt_master_slave`(C16) bit2=`bt_sw_hw`(H15) bit3=`bt_sw`(E18) bit4=`bt_rst_n`(M2)<br>复位默认 `0x1B`（上电+从模式+释放复位），见 §4.7 |
| `0x1000_0100` | LCD_CMD | — | 低 8 位作为命令(RS=0)送 LCD |
| `0x1000_0104` | LCD_DAT | — | 低 8 位作为数据(RS=1)送 LCD |
| `0x1000_0108` | LCD_STATUS | bit0=LCD_BUSY | — |
| `0x1000_010C` | LCD_CTRL | — | bit0=1 触发一次 LCD 硬复位脉冲；bit1=RST 取反；bit2=WR#/RD# 互换 |
| `0x1000_0110` | **LCD_RCTRL** | — | bit0=1 启动一次"读显示 RAM"（8080 读周期） |
| `0x1000_0114` | **LCD_RDATA** | 最近一次读回的字节（8 位） | — |
| `0x1000_0200 + 4*i` | **SEG_DIG[i]** (i=0..7) | — | 第 i 位数码管：bits[3:0]=值(0..15，0xF=空白)，bit4=1 点亮该位小数点(高亮) |
| `0x1000_0240` | **SEG_CTRL** | — | bit0=1 使能显示（0=整屏熄灭，上电默认 1） |
| `0x1000_0244` | **TIMER_CTRL** | — | bit0=1 启动一次硬件延时（长度 = RTL 参数） |
| `0x1000_0248` | **TIMER_VALUE** | 剩余拍数，0=延时结束 | — |
| `0x1000_0300` | **CPU_FLAGS** | 状态标志寄存器（CPU 内部 `FlagReg.v` 的只读镜像）：<br>bit0=SF bit1=ZF bit2=CF bit3=OF bit4=OF粘滞 bit5=PF bit6=SEEN | — |
| `0x1000_0304` | **OF_COUNT** | 算术溢出累计次数（32 位，`clrflags` 指令清零） | — |

> 为什么不用改 CPU：`PipelineCPU.v` 的 MEM 级外设窗口判定本来就是
> `addr[31:16]==16'h1000`（覆盖 0x1000_0000~0x1000_FFFF），新外设只是"往窗口里加地址"。
> 数据 RAM 基址 0x1001_0000 在窗口之外，天然不冲突。
> （`CPU_FLAGS`/`OF_COUNT` 是例外：标志寄存器本体在 CPU 里，CPU 只多了两个**输出**端口
>  `flags_o`/`of_count_o` 送给 `PeriphMMIO`，流水线逻辑不受影响，详见 §11。）

### 1.2 新增/修改文件清单

| 文件 | 状态 | 作用 |
|---|---|---|
| `UartChannel.v` | 新增 | 一路"MMIO UART 通道"（原 EES338Top 的 UART 寄存器逻辑搬入，UART/蓝牙各例化一份） |
| `LCD128128.v` | 新增 | ST7571 8080 并口控制器（上电复位 + 四段写时序 + busy 握手） |
| `SegDisplay.v` | 新增 | 8 位数码管动态扫描控制器（七段译码 + 位选扫描 + 小数点高亮） |
| `SimpleTimer.v` | 新增 | 一次性硬件延时外设（长度参数化 → 仿真/上板同一份程序） |
| **`FlagReg.v`** | 新增（本次） | **状态标志寄存器**：SF/ZF/CF/OF/PF + 粘滞溢出位 + 溢出计数（Lab1 标志位处理方法的迁移，见 §11） |
| **`DivUnit.v`** | 新增（本次） | **多周期除法单元**：加减交替法（非恢复余数），有符号/无符号商与余数（迁移自 Lab1 `mult_alu.v`） |
| `PeriphMMIO.v` | 新增 | 外设地址译码 + 2×UartChannel + LCD + 数码管 + 定时器 + 读数据多路选择 |
| `EES338_Core.v` | 新增 | **可封装为 IP 的 SoC 内核**（PipelineCPU + PeriphMMIO） |
| `EES338Top.v` | 修改 | 变薄为板级胶水（MMCM/复位/同步/LED），新增 bt/lcd/数码管端口 |
| `EES338.xdc` | 修改 | 追加蓝牙、LCD、数码管引脚约束 |
| `gen_uart_demo.py` | 修改 | 演示程序生成器（`hello/helloecho/echo/bt/lcd/sort/lcdtest/btcheck/flags` 九种模式） |
| `lcd_demo.py` | 新增 | LCD 字模 / 初始化命令表 / 显示内容 / 期望帧缓存 |
| `sort_demo.py` | 新增 | 数码管演示程序：五整数排序 + 期望显示轨迹 |
| `tb_lcd128128.v` / `tb_segdisplay.v` | 新增 | 两个控制器的单元测试 |
| `tb_EES338_lcd.v` / `tb_EES338_bt.v` / `tb_EES338_sort.v` | 新增 | 三个整机级自检（LCD 帧缓存比对 / 蓝牙回显 / 数码管排序轨迹比对） |
| `scripts/package_ip.tcl` | 新增 | 封装 IP 核 → `ip_repo/EES338_Core/component.xml` |
| `scripts/build_bd_demo.tcl` | 新增 | 用封装好的 IP 搭 Block Design 并综合 |
| `scripts/run_sim.ps1` | 新增 | 命令行一键仿真（xvlog/xelab/xsim，自动编译 unisims） |

> `PipelineCPU.v`、`ALU.v`、`ControlUnit.v`、`DataMemory.v`、`InstructionMemory.v`、
> `RegisterFile.v`、`PC.v`、`ImmediateGenerator.v`、`UART_TX.v`、`UART_RX.v` **一行未改**。
>
> ⚠️ **上面这条在本次"溢出标志位迁移"之后不再成立**：`ALU.v` / `ControlUnit.v` / `PipelineCPU.v`
> 为迁移 Lab1 的标志位与乘除法做了扩展，改动清单与语义见 **§11**（`RegisterFile.v`、`PC.v`、
> `ImmediateGenerator.v`、`DataMemory.v`、`InstructionMemory.v`、`UART_TX/RX.v` 仍然一行未改）。

### 1.3 ★ 上板验证速查：哪个 bitstream 看什么

**注意**：一块 FPGA 里只能烧一份 bitstream，而**演示程序是"烘焙"在 bitstream 里的**
（由最后一次 `python gen_uart_demo.py <模式>` 决定）。所以每个演示对应一个 `.bit` 文件，
`bitstream/` 目录里已经给你准备好了 5 份，直接烧对应的那份即可：

| bitstream 文件 | 演示程序 | 烧进去后**应该看到什么** | 怎么测 |
|---|---|---|---|
| **`EES338Top_sort.bit`** | `sort` | **8 位数码管**演排序：`9 3 7 1 5 0 0` → 小数点轮流跳到正在比较的两位 → 数值当场互换 → … → `1 3 5 7 9 0 7`（交换 7 次）→ 停约 1.2s → 回到乱序重来一轮（每轮约 8s，一直循环）。**串口无输出** | 上电直接看数码管（可录视频） |
| **`EES338Top_lcd.bit`** | `lcd` | ① 串口助手（**115200-8N1**）收到一次 **`LCD OK`**；② **板载 LCD 屏**显示两行 `EES-338` / `LCD OK`。程序随后停在死循环，屏上内容保持 | 串口助手 115200-8N1 → 下载（或按 P15 复位） |
| **`EES338Top_lcdtest.bit`** ★诊断 | `lcdtest` | LCD 自检 **v3**（每种配置 4 步）：串口打印 **`C<k>` → `A` → `P` → `EV01234567`**；屏上依次应看到 **0xA5 全屏变黑**、**半屏图案（左黑右白）**、**8 档对比度扫描**。判读表见 §3.4 | 见 §3.4「屏不亮怎么查」 |
| **`EES338Top_flags.bit`** ★新 | `flags` | **8 位数码管**从左到右显示标志寄存器 **SF ZF CF OF STK PF SEEN CNT**（每位显示 0/1，`STK` 那位的小数点点亮 = 曾经溢出过）；循环演 5 个场景（溢出加法 → 不溢出加法 → 借位减法 → 乘法溢出 → `clrflags` 清零）。串口打印 `FLAGS DEMO` | 见 §11.7 |
| **`EES338Top_lcdread.bit`** ★新 | `lcdread` | **LCD 读回自检**：写 `0x5A/0x3C` 进显示 RAM 再读回来，数码管逐位 + 串口打印 `1=xxxxxxxx` / `2=xxxxxxxx`。判读表见 §3.5 | 见 §3.5 |
| **`EES338Top_bt.bit`** | `bt` | **蓝牙回显**：手机 BLE 助手连上模块后，发什么字符原样回什么 | 见 §4.4 |
| **`EES338Top_btcheck.bit`** ★诊断 | `btcheck` | 串口先打印 `BT SELF-TEST`，之后**每 0.4s 打印一次 `RX=K`**（板子在蓝牙口发 'K'；若用跳线短接 N2↔L3，这个 'K' 会被自己收到并报出来）。手机连上后发的字符会显示成 `RX=<字符>`。程序启动时会先给模块**上电+复位**（`BT_CTRL`） | 见 §4.5 / §4.7 |
| **`EES338Top_btat.bit`** ★ | `btat` | **蓝牙 AT 探针**（已含上电/复位序列）：轮流传 `AT` / `AT\r\n` / `AT+NAME?\r\n`，把模组回显直接打印（期望 `A: OK` / `B: OK` / `C: OK+NAME=…`）→ 判断"模组在不在听、引脚方向/波特率对不对" | 见 §4.6 / §4.7 |
| **`EES338Top_btat2.bit`** ★ | `btat2` | **蓝牙 AT 命令探索器**：轮流传 `AT`/`AT+VERSION?`/`AT+NAME?`/`AT+NAME`/`AT+ADDR?`/`AT+ROLE?`/`AT+BAUD?`/`AT+RESET` 并打印回显 → 问出模块型号/名字/MAC/角色/波特率，最后复位重新广播 | 见 §4.7 |
| **`EES338Top_btseg.bit`** ★新 | `btseg` | **蓝牙→数码管**：手机发字符 → 数码管以 16 进制滚动显示最近 4 个字节（最新字节在小数点位置高亮）+ 原样回发 + 串口打印 `RX=<字符>`。**全程不发 AT 命令**（这样手机才能连上，见 §4.8/§4.9） | 见 §4.9 |
| **`EES338Top_btcfg.bit`** ★ | `btcfg` | **蓝牙模式脚扫描**：8 种 `BT_CTRL` 组合（主从/sw_hw/sw）各"先复位再释放"并停 10s，串口打印 `T<k> m.. h.. s..`；哪种组合时手机能连上就固化哪种 | 见 §4.8 |
| **`EES338Top_btat_swap.bit`** ★ | `btat` | 同上，但**蓝牙两个引脚对调**（`bt_txd→L3`、`bt_rxd→N2`），用于和上面那份做 A/B 对比（手册可能标反） | 见 §4.6 |
| `EES338Top_helloecho.bit` | `helloecho` | 串口**每约 2s** 收到一行 `Hello, EES-338!`；发任意字符会**原样回显** | 串口助手 115200-8N1 |
| `EES338Top_hello.bit` | `hello` | 串口周期收到 `Hello, EES-338!`（只测发送方向） | 串口助手 115200-8N1 |

常见疑问：

* **"烧了 LCD 的 bit，预期是什么？"** → 串口出现 `LCD OK` ＋ 屏上出现 `EES-338` / `LCD OK`。
  若只有串口 `LCD OK`、屏不亮 → **先烧 `EES338Top_lcdtest.bit` 按 §3.4 排查**（多半是初始化时序/引脚标法问题）。
* **"蓝牙扫不到设备"** → 见 §4.5：**广播/配对是 BLE 模组自己的固件行为，FPGA 代码影响不到它**；
  先用 `EES338Top_btcheck.bit` + 一跳线短接 N2↔L3 证明 FPGA 侧收发通道是好的。
* 想换演示：`python gen_uart_demo.py <模式>` **然后**跑 `scripts/run_bitstream.tcl`，
  新 bit 在 `Lab2.runs/impl_1/EES338Top.bit`（建议复制到 `bitstream/` 存档）。
* 任何时候按 **P15 复位键** 都能让程序从头开始。

---

## 2. USB-UART 接口（原有功能，已上板验证）

* 硬件：板载 CP2102（手册 §9）。**实测引脚方向与手册标注相反**：
  `uart_txd → T4`（FPGA 出）、`uart_rxd → N5`（FPGA 入），XDC 已按实测修正。
* 逻辑：`UartChannel.v` = TX 数据寄存器 + busy/ready 握手 + `UART_TX`/`UART_RX`；
  115200-8N1，`BAUD_DIV = 50MHz/115200 = 434`。
* 软件协议：`sw UART_DATA` 发一个字节（先轮询 STATUS.bit0 忙）；`lw UART_DATA` 读回收到的字节
  （读后硬件自动清 STATUS.bit1）。
* 演示程序：`hello`（周期打印）、`echo`（回显）、`helloecho`（打印+随时回显，日常推荐）。
* 上板自检：Vivado Hardware Manager 下载 bitstream → 串口助手 **115200-8N1** →
  看到 `Hello, EES-338!`；发送任意字符可看到回显。

---

## 3. LCD 接口（JLX128128G-81202 / ST7571，8080 并口）

### 3.1 硬件（手册 §13）

| 信号 | FPGA 引脚 | 说明 |
|---|---|---|
| LCD_D0..D7 | T1, M6, N6, R6, R5, V7, V6, U9 | 8 位数据总线 |
| LCD_WR# | V9 | 写选通（低有效） |
| LCD_RD# | U7 | 读选通（本设计只写，恒为高） |
| LCD_CS# | U6 | 片选（低有效） |
| LCD_RST# | R7 | 硬复位（低有效） |
| LCD_RS | T6 | 寄存器选择：0=命令，1=数据 |

屏为 128×128 单色点阵，8 页 × 128 列（每页 8 行，字节的 bit0 = 页内最上一行）。

### 3.2 RTL 设计（`LCD128128.v`）

握手方式与 `UART_TX` 的 `tx_busy` **完全一致**（刻意如此，便于讲解与软件复用）：

* `busy=1` = 控制器占用总线（上电复位脉宽中 / 一次写时序进行中）；
* CPU 先读 `LCD_STATUS` 轮询 `busy==0`，再写 `LCD_CMD`/`LCD_DAT`；
* 控制器自动产生 `[建立 → WR# 拉低 → WR# 拉高 → 保持]` 四段时序：
  `WR_CYCLES=10`(200ns)、`SETUP=4`(80ns)、`HOLD=4`(80ns)，一次写共 18 拍；
* 上电后自动拉低 `LCD_RST#` `RST_CYCLES=200000` 拍（4ms）再释放，期间 `busy=1`；
* 写 `LCD_CTRL.bit0=1` 可再来一次软复位脉冲。

### 3.3 演示程序（`python gen_uart_demo.py lcd`）

1. 等 LCD 上电复位结束（轮询 busy）；
2. 发**初始化命令表**（14 条，ST7571/ST7565 兼容：软复位 → 关显示 → ADC/BIAS/COM 方向 →
   显示起始行 → 内部电阻比 → 电源 VC/VR/VF → 电子音量(对比度) → 开显示）；
3. **清屏**（8 页 × 128 列全 0，循环算出，不占数据表空间）；
4. **写字符图案**：DMEM 里是一张"命令/数据混合流"表（每条目 bit8=RS），循环取出后轮询 busy 写入；
5. 通过 USB-UART 打印 `LCD OK` 作为**串口回执**（即使屏没亮也能确认程序跑完）。

显示内容与字模都在 `lcd_demo.py`（当前显示 `EES-338` / `LCD OK`，5×7 点阵放在 8×16 字符格）。
直接运行 `python lcd_demo.py` 会把期望显示效果打成 ASCII 预览，改字模时肉眼校对：

```
.........####....####.....###....#####....###.....###.....###...
.........#.......#.......#............#.......#...#...#...#.....
.........#.......#.......#............#.......#...#...#...#.....
.........####....####.....###....#####....###.....###.....###...
```

### 3.4 ★ 屏不亮怎么查（实测踩坑：初始化必须等电源稳定）

**先说结论（已修复）**：我们第一版初始化序列把 14 条命令在 **5µs 内一口气发完**就立刻写像素，
而 ST7565/ST7571 系列要求 **电源命令（0x2C/0x2E/0x2F）之后等电源稳定（约 100ms）再开显示（0xAF）**，
否则常见现象就是"**屏全黑、完全不亮**"（程序流程却全都跑完了，串口照样有 `LCD OK`）。
现在序列里插了 4 个"等待"（在硬件定时器上，上板每次 0.4s，共约 1.6s 启动时间），
见 `lcd_demo.py` 里的 `LCD_INIT`（`DELAY` 标记）与本文 §3.2。

**如果改完还是不亮**，直接烧 **`bitstream/EES338Top_lcdtest.bit`**（LCD 自检 **v3**）。
它比 v2 强的地方：**加了"与 RAM 无关"的 0xA5 全屏点亮测试**、**画"半屏图案"**（左半黑右半白，
不是一片均匀的亮/暗，能区分"数据没进屏"和"对比度不对"）、并且**每种配置里扫 8 档对比度**。

每种配置 k=0..7（`k = RST 极性×4 + WR/RD 互换×2 + 初始化变体`）依次做：

| 串口输出 | 屏上应该看到 |
|---|---|
| `C0`…`C7` | 开始第 k 种配置（调试开关 + 硬复位 + 初始化表） |
| `A` | 已发 **0xA5（全屏点亮，与 RAM 内容无关）**，停 0.8s → **屏应整屏变黑** |
| `P` | 已发 0xA4 恢复正常，并画好**半屏图案**（左半屏全亮、右半屏全灭）→ 屏上应出现**左黑右白的竖直分界** |
| `EV` 后逐个出现的 `0`…`7` | 对比度扫描：档 i 对应 **EV = i×8**（0x00,0x08,0x10,…,0x38），每档 0.4s。图案的可见度应该在这一串里"由看不见 → 出现 → 过深"变化 |

**判读表（把结论对号入座，然后告诉我）**

| 观察到 | 结论 | 下一步 |
|---|---|---|
| `A` 之后屏**整屏变黑** | 面板、电源、电荷泵、对比度都活着 | 再看 `P`：出现左黑右白 → **全部正常**，只需把当时的 `C k / EV` 固化进演示程序 |
| `A` 不变，但 `EV` 扫到某一档**出现分界** | 总线数据是通的，只是**对比度**不在合适档 | 我把那个 EV 值写进 `lcd_demo.py` 的 `LCD_INIT`（不用改 Verilog），重出 `lcd` 演示 bitstream |
| 8 档 `EV` 全程**毫无变化**，`A` 也无变化 | 数据没进屏（总线/引脚层面） | 下一步我做"**读回自检**"：ST7571 支持 8080 读，写一个字节再读回来比对，就能判定"是否真的写进去了"，而不依赖肉眼 |
| 串口只打印到某一行就停了 | 程序卡住了（很可能是 `LCD_STATUS.busy` 一直为 1） | 把停住的那一行告诉我，这本身也是重要线索 |
| 只有**部分** `C k` 有反应 | 该 `k` 对应的极性/互换配置才是对的 | 告诉我 `k`，我固化配置 |

> 小技巧：FSTN 屏对比度偏低时，**斜着看或用手电筒照**能看见隐约的图案；整屏"均匀深色"往往说明
> **对比度(V0)太高**，这时 EV 扫描的低档位反而会显示出图案 —— 8 档扫描就是为这种情况准备的。

另外三个可以直接在代码里调的旋钮（`LCD_CTRL` 的 bit0/bit1/bit2）：

| 位 | 作用 |
|---|---|
| `LCD_CTRL.bit0` | 写 1 → 发一次硬复位脉冲（正常演示程序启动时用不到） |
| `LCD_CTRL.bit1` | 1 = LCD_RST 输出**取反**（若实测复位是高有效） |
| `LCD_CTRL.bit2` | 1 = LCD_WR# 与 LCD_RD# **互换输出**（若实测这两个脚标反） |

### 3.5 ★ 读回自检（v4）：不用眼睛判断"数据到底进没进屏"

**背景**：v3 的 8 种配置（含 0xA5 全屏点亮、半屏图案、8 档对比度扫描）在板上**屏面毫无变化**，
说明问题不在"极性/对比度"，而在更底层 —— **LCD 是否真的收到并接受了命令**。
到这一步肉眼已经分辨不出来，于是给 LCD 控制器加了 **8080 读通路**，把判断变成**数值比对**。

**做法**（`bitstream/EES338Top_lcdread.bit`，`python gen_uart_demo.py lcdread`）：

1. 硬复位 + 初始化（标准配置，不带任何调试开关）；
2. 往显示 RAM 写两个已知字节：`(页0,列0)=0x5A`、`(页0,列1)=0x3C`；
3. 列地址设回 0，然后**读 3 次**（ST7571 规定第 1 次是"空读"，第 2/3 次才是真数据）；
4. 把第 2、3 次读到的字节**同时**显示在 **8 位数码管**（dig0=bit7 … dig7=bit0）
   和 **USB-UART**（形如 `1=01011010`），循环刷新。

| 串口/数码管读到 | 结论 | 下一步 |
|---|---|---|
| `1=01011010`（=0x5A，就是写进去的值） | **数据总线、片选、读写选通、位序全部正常**，控制器也在工作 → 问题只在"显示"这一层（对比度/V0/显示模式/面板本体） | 继续在初始化上做文章：换 BIAS/电阻比/EV 区间、试 `0xA7` 反显、调 `0x2C/0x2E/0x2F` 顺序 |
| `1=11111111`（全 1） | 数据总线**没有任何一方驱动**（XDC 给 `lcd_d` 加了弱上拉，悬空就是全 1）→ LCD 侧没接上 / 接口模式不是 8080 / 引脚与手册不符 | **必须查硬件**：20 针排线是否插到底、模块接口选择跳线（PS/IM）、转接板丝印，必要时拍照确认（对照手册 §13 的 20 针定义） |
| 其它值（例如个别位不对） | 数据线**位序或个别引脚**有问题 | 把读到的值告诉我，我按位序做映射修正 |
| 串口只打印到 `LCD READBACK` 就停了 | 读周期卡住（RD# 没回来） | 告诉我，这也是线索 |

**实现说明**（报告可写）：`LCD128128.v` 增加读状态 `S_RDLOW` —— `CS#=0、RS=1、RD#` 拉低
`RD_CYCLES=30` 拍（600ns）后采样数据总线，然后释放总线、恢复写方向；数据线改成 **`inout`**
（写时驱动、读时高阻）。新增 MMIO：

| 地址 | 名称 | 读写 |
|---|---|---|
| `0x1000_0110` | **LCD_RCTRL** | w：bit0=1 启动一次"读显示 RAM"周期 |
| `0x1000_0114` | **LCD_RDATA** | r：最近一次读回的字节 |

验证：`tb_lcd128128.v` 增加读周期断言（RD# 低 12 拍、RS=1、CS# 低、结束时采到总线值）；
新增 `tb_EES338_lcdread.v` 让 testbench **扮演屏**并在读周期驱动 `0xA5`，
检查程序打印出 `1=10100101`（刻意与写进去的 `0x5A` 不同，证明数据确实来自总线）→ **ALL PASS**。

### 3.6 ★★ 官方结论：板载 LCD 是 **SPI** 接口（我们之前的 8080 并口方向错了）

**证据**（`labdoc/lab10_LCD_display.pdf` + 官方工程 `project/lab10_lcd_display`）：

1. 官方 SDK 代码头注释写得很清楚 —— LCD 只有 5 根信号：
   `bit4 lcd_cs / bit3 lcd_rstn / bit2 lcd_rs / bit1 lcd_sck / bit0 lcd_mosi`，即 **SPI**。
2. 官方 `system.xdc` 的引脚：

   | 信号 | FPGA 引脚 | 对应手册 §13 里的哪根 |
   |---|---|---|
   | `lcd_sck` | **V6** | 手册标 `LCD_D6` |
   | `lcd_mosi` | **U9** | 手册标 `LCD_D7` |
   | `lcd_rs` | **T6** | 手册标 `LCD_RS` |
   | `lcd_rstn` | **R7** | 手册标 `LCD_RST` |
   | `lcd_cs` | **U6** | 手册标 `LCD_CS` |

   → **同一批物理引脚，但板子是把模组接在"串行模式"上**；手册给的是模组**并口用法**的引脚名
   （所以 D0..D5/WR/RD 这些并口信号在这块板上根本没接到可用位置）。
3. 官方初始化序列（`lcd_func.c: initial_lcd()`，实测可用）：
   `RSTN` 低 500µs → 高 100µs → `0x2C` → `0x2E` → `0x2F` → `0xAE` → `0x38` → `0xB8` → `0xC8`
   → `0xA0` → `0x44 0x00` → `0x40 0x00` → `0xAB` → `0x67` → `0x26` → `0x81 0x36` → `0x54`
   → `0xF3 0x04` → `0x93` → `0xAF`
   （命令集比 ST7565 多几条扩展命令 —— **照官方的发就对了**）
4. 收发时序（`transfer_command` / `transfer_data`）：**CS# 拉低 → RS=0(命令)/1(数据) →
   8 位 MSB 先出，每位在 SCK 上升沿被采样 → CS# 拉高**；每条命令/数据各自带一次 CS# 低-高。
5. RAM 组织：**16 页**（`0xB0+page`，page 0..15）× 128 列，而且**每列要写 2 个字节**
   （屏是 4 灰度 2bpp）—— 单色图案要**把同一个字节连写两次**（官方 `clear_screen` /
   `display_graphic` 就是这么干的）。

**结论**：我们之前按"8080 并口"（D0..D7 + WR#/RD#）实现的驱动**和这块板对不上**，
所以出现"屏毫无反应 + 读回全 1"这一整串现象（§3.4/§3.5 的所有扫描都注定无效）。

**下一步（待实现）**：把 `LCD128128.v` 改成 **SPI 驱动** ——
端口改成 `lcd_sck / lcd_mosi / lcd_cs_n / lcd_rs / lcd_rst_n`，
初始化表换成上面官方序列，数据按"每列 2 字节"写；
MMIO 的 "写命令/写数据/busy" 接口**保持不变**（CPU 侧程序只改初始化表与双写），
`EES338.xdc` 里把 `lcd_d[6]→SCK(V6)`、`lcd_d[7]→MOSI(U9)` 等重新按上表约束即可。

---

## 4. 蓝牙接口（BLE-CC41-A）

### 4.1 硬件（手册 §11）

| 信号 | FPGA 引脚 | 方向 |
|---|---|---|
| BT_RX（模块收） | **N2** | FPGA 输出（本设计 `bt_txd`） |
| BT_TX（模块发） | **L3** | FPGA 输入（本设计 `bt_rxd`） |

模块与 FPGA 之间就是**一路普通串口**，默认波特率 **9600**。

### 4.2 RTL 设计：复用同一条 UART 通道

把 UART 寄存器逻辑抽成 `UartChannel.v` 后例化两份，只差一个参数：

```verilog
UartChannel #(.BAUD_DIV   (434) ) u_uart (...);   // CP2102 115200 @50MHz
UartChannel #(.BAUD_DIV   (5208)) u_bt   (...);   // 蓝牙    9600  @50MHz
```

`50_000_000 / 9600 = 5208.33`，取 5208（误差 0.006%）完全够用。

### 4.3 演示程序（`python gen_uart_demo.py bt`）

与 `echo` 完全同构，地址从 `0x1000_0000/04` 换成 `0x1000_0010/14`：

```asm
poll_rx:
        lw    x11, 20(x10)     # BT_STATUS
        andi  x12, x11, 2      # RX_READY?
        beq   x12, x0, poll_rx
        lw    x13, 16(x10)     # BT_DATA（读走同时清 ready）
wait_tx:
        lw    x14, 20(x10)
        andi  x15, x14, 1      # TX_BUSY?
        bne   x15, x0, wait_tx
        sw    x13, 16(x10)     # 原样回发
        jal   x0, poll_rx
```

### 4.4 上板验证（需要一部手机）

1. 先把演示程序换成蓝牙回显：`python gen_uart_demo.py bt` 再出 bitstream
   （**bitstream 里烘焙的是最后生成的那份程序**）；
2. 手机装 **BLE 串口调试 App**，扫描连接 `BLE-CC41-A`，输入任意字符发送；
3. 板上 CPU 会原样回复（回显）。


### 4.5 ★ 蓝牙扫不到设备怎么查（重要：广播不是我们控制的）

**关键认知**：`BLE-CC41-A` 的**广播名、是否可被扫描、能不能配对**全部由**模组自己的固件**决定；
FPGA 只负责"往串口发字节/从串口收字节"。所以：

* **扫不到设备 ⇒ 与我们的 RTL/程序完全无关**（换任何一个 bitstream 结果都一样）；
* 我们的代码写得再好也无法让模组变得"可被发现"。

**正确的扫描方法**（PC 自带蓝牙设置通常扫不到 BLE 外设，也不支持"BLE 串口"）：

| 平台 | 用什么 |
|---|---|
| Android / iOS | **nRF Connect**、**LightBlue**、**BLE 调试助手**（这些能列出所有 BLE 广播） |
| Windows | **nRF Connect for Desktop**（Windows 的"蓝牙和其他设备"只看键盘/耳机这类，不容易列出 BLE 透传模组） |

扫的时候找这些名字：`CC41-A`、`BLE-CC41-A`、`HMSoft`、`AT-09` 之类（不同批次固件名字不同）。
扫不到就依次查：

1. 模组**电源/指示灯**是否亮（板上 3.3V 是否上电）；
2. 板上是否有**蓝牙使能跳线/开关**（手册 §11 只给了串口两根脚，没提使能脚，可能另有电路）；
3. 手机蓝牙**开的是 BLE 扫描**（不是"经典蓝牙 SPP"）；
4. 换个手机/换个 App 再扫（有些手机对 BLE 广播名过滤较严）。

**用 `EES338Top_btcheck.bit` 判断"到底是谁的问题"**（不需要手机、不需要模组正常）：

| 步骤 | 操作 | 现象 | 结论 |
|---|---|---|---|
| 1 | 烧 `EES338Top_btcheck.bit`，**用跳线/镊子短接 N2 与 L3** | 串口每 ~0.4s 出现一行 **`RX=K`** | FPGA 的蓝牙收发通道 + 引脚方向**全部正常**，问题在模组/手机侧 |
| 2 | 同上，但**不短接** | 只有 `BT SELF-TEST`，之后**没有任何 `RX=K`** | 正常（没人回话）——说明也不是"自己乱收" |
| 3 | 把跳线去掉，手机连上模组后发字符 | 串口出现 **`RX=<你发的字符>`** | 链路全通（FPGA↔模组↔手机），可以直接用回显演示了 |
| 4 | 手机发的字符不出现 | 短接时能收到 `RX=K`，说明 FPGA 侧好 → 问题在**模组与手机的连接/波特率**（App 里波特率设 9600） | — |

> 短接 N2↔L3 就是"把板子自己的蓝牙 TX 接回自己的 RX"，等价于串口的环回自检：
> 程序每 0.4s 发 'K'，环回后自己收到就打印 `RX=K`。这一步把"板子侧"和"模组侧"彻底分开，
> 是排查"到底是硬件还是软件"最省事的办法。

### 4.6 ★ "手机/电脑找不到蓝牙"怎么排查（推荐流程）

**先记住两件事**：

1. **广播/配对是 BLE 模组自己的固件行为，与 FPGA 里烧什么程序无关**。
   BLE-CC41-A 只要上电且固件正常，就会自己广播，手机用 BLE 扫描 App 就能看到名字 ——
   这一步**完全不需要 FPGA 参与**。所以"扫不到设备"直接指向：模组没上电 / 固件不广播 /
   扫描方式不对（**Windows 自带"添加蓝牙设备"看不到 BLE 透传模组**，
   要用 **nRF Connect**（手机 App 或 Desktop）或 LightBlue，名字一般是
   `CC41-A` / `HMSoft` / `AT-09` 之类）。
2. **LED0 心跳只证明"下载成功 + 时钟在工作"**（心跳计数器在 `EES338Top` 里，和 CPU 无关），
   它**不能**证明 CPU 里的蓝牙程序在跑。要证明 CPU 在跑，必须看**串口有没有输出**
   （`btcheck` / `btat` 这两个演示）。

**三步定位（每步 1~2 分钟，按顺序做）**

| 步骤 | 烧哪个 bitstream | 操作 | 期望现象 | 结论 |
|---|---|---|---|---|
| ① 证明 CPU 在跑 | `EES338Top_btcheck.bit` | 打开串口助手 **115200-8N1** | 出现 `BT SELF-TEST` | FPGA/CPU/串口打印链路正常 |
| ② 证明 FPGA 蓝牙收发通道（板子侧） | 同上 | **用跳线/镊子短接 N2 ↔ L3** | 每 0.4s 出现一行 `RX=K` | FPGA 的蓝牙 TX→RX、引脚方向、内部通道**全通**（与模组无关） |
| ③ 与模组"对话" | **`EES338Top_btat.bit`**（新增） | 拔掉跳线，串口助手看输出 | 轮流传 `AT` / `AT\r\n` / `AT+NAME?\r\n`，并把模组回显直接打印：期望看到 `A: OK`、`B: OK`、`C: OK+NAME=xxx` | 模组在听、波特率/引脚方向都对 → 剩下的只是"广播/手机扫描"问题 |

**③ 的判读表**（串口形如 `A: ` 后面跟着模组回的内容）

| 现象 | 结论 | 下一步 |
|---|---|---|
| `A: OK` / `B: OK` / `C: OK+NAME=...` | 模组**活着且在听**，9600 波特率与引脚方向都对 | 问题只剩"广播/手机扫描"：换 **nRF Connect** 扫、看模组指示灯、确认手机蓝牙是 BLE 扫描 |
| 三行都是空（只有 `A: ` `/ `B: ` `/ `C: ` 没内容） | 模组**没在听**：没上电 / RX-TX 与手册相反 / 波特率不是 9600 / 已坏 | 试 **`EES338Top_btat_swap.bit`**（把 `bt_txd`/`bt_rxd` 两个引脚对调，A/B 对比）；还不行就查供电 |
| 只回了一部分字符（如只有一个 `K`） | 波特率或引脚方向勉强对上但不可靠 | 也用 `btat_swap` 对比；必要时改用 9600 之外的波特率（改 `BAUD_DIV_BT` 参数重出） |

> `EES338Top_btat_swap.bit` 是用 **`scripts/run_bitstream_btswap.tcl`** 生成的"**蓝牙引脚对调**"版本
> （内部 `set btswap 1` 后 source `run_bitstream.tcl`；对调是靠额外加一份约束
> `scripts/EES338_btswap.xdc`（`bt_txd → L3`、`bt_rxd → N2`）实现的 —— 注意 PACKAGE_PIN 必须在
> **约束文件**里给，脚本里直接 `get_ports` 会报 `No open design`）。
> 做这份 A/B 的原因很实在：**本板手册把 USB-UART 的 TX/RX 标反了**，蓝牙手册标注同样可疑。
> 两份 bitstream 一烧，就知道哪种接法是对的（两份 .bit 内容确实不同，已验证）。

**新增的 MMIO/程序**：无新增寄存器（AT 探针只用既有的 `BT_DATA 0x1000_0010` /
`BT_STATUS 0x1000_0014`）；新增演示模式 `python gen_uart_demo.py btat`
（`bt_at.hex` / `bt_at_mem.hex`），并新增 `tb_EES338_btat.v` —— 该 tb **扮演 BLE 模组**
（收到字节后静默一段时间再回 `OK\r\n`），验证程序把回显打印成 `A: OK` / `B: OK` → **ALL PASS**。

### 4.7 ★★ 根因：蓝牙模组需要 FPGA 驱动"电源 / 复位 / 模式"这 5 根脚

**现象**：`btcheck` 能打印 `BT SELF-TEST`（说明 CPU、程序、串口、MMIO 全都正常），
但 `btat` 的 AT 命令**永远收不到任何回显**（只有 `A: ` / `B: ` / `C: ` 三个空行），
手机/电脑也**搜不到**这个模组。

**根因**（在 `labdoc/lab08_Bluetooth.pdf` 与官方工程 `project/lab08_Bluetooth` 里找到）：
本板蓝牙模组的**电源、复位、模式选择**由 FPGA 的**另外 5 根脚**驱动 ——
**用户手册 §11 只写了串口两根线（N2/L3），完全没提这 5 根**；只有官方 `bluetooth.xdc` 里才有：

| 信号 | FPGA 引脚 | 作用 |
|---|---|---|
| `bt_pw_on` | **D18** | 模块**电源开关**（1 = 上电） |
| `bt_rst_n` | **M2** | 模块**复位**（低有效） |
| `bt_master_slave` | **C16** | 主/从模式选择（1 = 从模式，手机可连接） |
| `bt_sw_hw` | H15 | 官方例程接 SW1（**置低**） |
| `bt_sw` | E18 | 官方例程接 SW3（**置高**） |

官方 `bt_uart.v` 里就是把这 5 根直接接到板上拨码开关：

```verilog
assign bt_master_slave = sw_pin[0];
assign bt_sw_hw        = sw_pin[1];
assign bt_rst_n        = sw_pin[2];
assign bt_sw           = sw_pin[3];
assign bt_pw_on        = sw_pin[4];
```

lab08 步骤 5 写得更直接：**SW1 置低、SW0/SW2/SW3/SW4 置高，再用 SW2 把蓝牙拉低再拉高复位**，
此时模组才进入 **slave 模式**开始广播（状态灯 LED2 慢闪；连接后 LED2 常亮；配对密码
`123456`，不对再试 `000000`/`1234`/`0000`）。

**我们的设计此前一根都没接** → 模组很可能**一直没上电 / 一直处于复位** →
既不会广播（⇒ 搜不到），也不会应答 AT（⇒ `A: / B: / C: ` 全空）。**这一条同时解释了全部现象。**

**修复（本次实现，已仿真验证）**

* `PeriphMMIO.v` 新增 **`0x1000_0018 BT_CTRL`**（写：bit0 `bt_pw_on`、bit1 `bt_master_slave`、
  bit2 `bt_sw_hw`、bit3 `bt_sw`、bit4 `bt_rst_n`）；复位默认 `5'b11011` = 官方可用状态，
  并且**上电先输出 20ms 低电平复位脉冲**再释放（等价于官方"用 SW2 复位一次"）。
* `EES338_Core.v` / `EES338Top.v` 新增这 5 个输出端口；`EES338.xdc` 按官方接法约束
  D18 / M2 / C16 / H15 / E18。
* 演示程序 `bt` / `btcheck` / `btat` 启动时先写 `BT_CTRL`：`0x0B`（上电 + 从模式、复位有效）
  → 等一个硬件延时 → `0x1B`（释放复位）——就是官方"拉低再拉高"那一步。
* `tb_EES338_btat.v` 新增断言：`bt_pw_on=1`、`bt_master_slave=1`、`bt_rst_n` 出现低→高复位序列
  → **ALL PASS**。

**上板实测（2026-09-17，修复后立刻见效）**：烧 `EES338Top_btat.bit` 后串口输出

```
BT AT PROBE
A: 
B: OK
C: +NAME=?
OK
```

* **`B: OK`** ⇒ **模组活了、在听、并且应答**（此前是 `A: / B: / C: ` 三行全空）——
  "上电/复位没驱动"这条根因**得到确认**；
* 裸 `AT`（无 CRLF）无应答 ⇒ 本板模组**必须带行结束符 `\r\n`**（HM-10 那种裸 "AT" 在这里不行）；
* `AT+NAME?` 回 `+NAME=?` + `OK` ⇒ 它的 AT 命令集**不是 HM-10 风格**（更像 CC41/JDY 系），
  于是又做了 **`btat2` 探索器**（见下）。

**`btat2`：AT 命令探索器**（`python gen_uart_demo.py btat2` → `bitstream/EES338Top_btat2.bit`）

轮流传 8 条命令并把回显原样打印，用来问出模块身份与状态：
`AT` / `AT+VERSION?` / `AT+NAME?` / `AT+NAME` / `AT+ADDR?` / `AT+ROLE?` / `AT+BAUD?` / `AT+RESET`
（最后一条 `AT+RESET` 让模块复位并**重新开始广播**，正好配合手机扫描）。

| 回显 | 含义 |
|---|---|
| `AT` → `OK` | 链路通 |
| `AT+VERSION?` → `+VERSION=xxx` | 固件版本 ⇒ 可据此确定模块型号与 AT 集 |
| `AT+NAME?` / `AT+NAME` → 名字 | 手机扫描时看到的名字 |
| `AT+ADDR?` → MAC | 模块蓝牙 MAC（手机按这个认设备） |
| `AT+ROLE?` → 0/1 | 0=从、1=主（要能被手机连，必须是从模式） |
| `AT+BAUD?` → 波特率档位 | 若不是 9600，改 `BAUD_DIV_BT` 重出 bitstream |


**上板怎么验**（烧 `bitstream/EES338Top_btat.bit`）：

1. **先看模组上的状态指示灯 LED2**：开始**慢闪** = 已进入 slave 模式在广播（这就是我们要的）；
2. 串口应出现 **`A: OK` / `B: OK` / `C: OK+NAME=...`**；
3. 手机用 **nRF Connect / LightBlue** 扫描（**别用 Windows 自带"添加蓝牙设备"**），
   应能看到模组名（`CC41-A` / `HMSoft` / `AT-09` 之类），配对密码按官方提示试
   `123456` / `000000` / `1234` / `0000`。

| 观察 | 结论 / 下一步 |
|---|---|
| LED2 慢闪 + AT 有回显 | **修好了**：链路全通，接着用手机连（`EES338Top_bt.bit` 回显演示） |
| LED2 仍不亮 | 供电/复位脚还有问题：可用 `BT_CTRL` **逐位**试（比如把 bit4 置 0/1 手动复位、或改 bit1 试主模式），必要时量 D18/M2 电平 |
| LED2 闪但没有 AT 回显 | 串口两根线的**方向**可能和手册相反 → 烧 **`EES338Top_btat_swap.bit`**（N2/L3 对调那一版） |

### 4.8 ★ 手机能扫到但"连接超时（GATT CONN TIMEOUT）"怎么查

**现象**：`btat2` 跑起来后，手机 nRF Connect **能扫到模组**（说明模块已上电、在广播 ✓ 上电/复位修复生效），
但一点连接就报 **GATT CONN TIMEOUT**。

**`btat2` 的 AT 回显告诉我们两件事**：

| 命令 | 回显 | 说明 |
|---|---|---|
| `AT` | `OK` | 链路正常 |
| `AT+RESET` | `OK` | 支持复位 |
| `AT+VERSION?` / `AT+ADDR?` | （无回显） | 不支持 |
| `AT+ROLE?` / `AT+BAUD?` | `ERR` | 不支持 |
| `AT+NAME?` / `AT+NAME` | `+NAME=?` | 名字查询返回 `?`（名字可能就叫 `?`，或格式不同） |

⇒ 这个模组**只认极少数 AT 命令**，"能不能被连接"**不是 AT 配的**，而是由
**`BT_CTRL` 里的 3 个模式位**（`bt_master_slave` / `bt_sw_hw` / `bt_sw`，即官方 lab08 的 SW0/SW1/SW3）决定的。
所以做了 **`btcfg` 模式脚扫描**（`python gen_uart_demo.py btcfg` → `bitstream/EES338Top_btcfg.bit`）：

* 把 3 个模式位组合成 **8 种**（`BT_CTRL = 0x11 | (k<<1)`，`k=0..7`）；
* 每种都是"**先复位、再按该组合释放**"，停 **~10s** 让手机端试连接；
* 串口打印 **`T<k> m<m> h<h> s<s>`**（m=主从位、h=sw_hw、s=sw）。

**上板怎么用**：烧了以后，nRF Connect 里**反复点连接**，同时看串口当前是哪一行 `T..`，
**哪一行的窗口里能连上（同时模组 LED2 变常亮）**，就是这组模式位对了——把那行发我，
我把这组值固化进 `BT_CTRL` 默认值（演示程序就不用再扫了）。

| 观察 | 结论 |
|---|---|
| 某个 `T<k>` 期间连上了 | **找到正确模式组合** → 固化 |
| 8 种全部连接超时 | 说明"连接"还受别的东西影响：可试 `AT+RESET` 后立刻连、确认手机没有配对残留（先"忘记设备"）、或换一个 BLE App（nRF Connect ↔ LightBlue） |
| 扫都扫不到了 | 该组合把模块弄成了不广播的状态 → 等下一行 `T..` 再看 |

**★ 上板实测结论（2026-09-17 晚，已成功）**：在 **`T5 m1 h0 s1`** 那一行（= `BT_CTRL = 0x1B`，
**正好就是我们的默认值**）期间，模组的蓝牙灯**由闪变常亮** = **手机连接成功** ✓

由此得到两条重要结论：

1. **正确的模式组合就是 `0x1B`**（pw_on=1、master_slave=1、sw_hw=0、sw=1、rst_n=1）——
   **RTL 与默认值都不用改**，`bt_pw_on`/`bt_master_slave`/`bt_sw` 的极性也都与我们原先的假设一致 ✓
2. 之前"**能扫到但连接超时**"的真正原因很可能是：**`btat` / `btat2` 一直在发 AT 命令** ——
   模组处于"命令交互"状态时**不接受连接**；而 `btcfg` 只摆模式脚、**不发任何 AT 命令**，所以能连上 ✓

⇒ **给手机用的演示程序必须"不碰 AT 命令"**：直接用 `bitstream/EES338Top_bt.bit`
（`bt` 回显演示：程序只做"上电 + 写 `BT_CTRL=0x1B`"，全程不发 AT）✓

---

### 4.9 ★ 手机发字符 → 8 位数码管显示（`btseg`，验收演示）

**`bitstream/EES338Top_btseg.bit`**（`python gen_uart_demo.py btseg`，程序 265 条指令）

程序做的事（**关键：全程不发任何 AT 命令**，只写 `BT_CTRL = 0x1B`）：

1. 手机（BLE 助手 / nRF Connect 的可写特征）发一个字节；
2. FPGA 轮询 `BT_STATUS.RX_READY` → 读 `BT_DATA` 得到该字节；
3. **数码管按十六进制滚动显示最近 4 个字节**：`b3 b2 b1 b0`，每个字节 2 位十六进制，
   **最新那个字节在最右两位，并且小数点同时点亮**，一眼就能看出刚收到什么；
4. **原样回发给手机**（手机上立刻能看到自己发的字符回来了）；
5. 同时用 USB-UART 打印 `RX=<字符>`，串口助手里能看到记录。

举例：手机依次发 `A`、`B`（0x41 / 0x42）——

| 数码管（从左到右） | 含义 |
|---|---|
| `00` `00` `41.` `42.` | 最新是 `B`(0x42)、上一个是 `A`(0x41)，带小数点的是最新 |
| 串口 | `BT SEG DEMO` → `RX=A` → `RX=B` |

**实现要点**（本 ISA 没有右移指令，所以取十六进制位要绕一下）：
"取第 i 位"= `slli` 左移到位 31 + `slt` 与 0 比较，再把 4 个位按 1/2/4/8 加权相加得到 0..15；
`{mark, value[3:0]}` 写进 `0x1000_0200+4*i` 即可（bit4 = 小数点）。

**验证**：新增 `tb_EES338_btseg.v` —— tb **扮演 BLE 模组**，按 9600bps 发 `'A'`、`'B'`，
然后断言：① 回显的两个字节正确；② **BT 线上只有这两个回显、没有任何 AT 命令**（把 §4.8 的教训写成测试）；
③ 数码管 `dig6=0x14`/`dig7=0x12`（`B` 的高/低半字节 + 小数点）、`dig4=0x04`/`dig5=0x01`（`A` 被左移）；
④ 串口出现 `BT SEG DEMO`/`RX=A`/`RX=B`；⑤ `bt_pw_on=1` → **ALL PASS**。

---

**目标**：原来流水线的正确性靠 `tb_CPU.v` 在终端打印结果来验证；本接口把**同一个冒泡排序程序**
的运行过程实时显示到板载数码管上 —— 不但能"看"到排序结果 `1 3 5 7 9`，还能看到每一次比较
（亮点高两位）和每一次**交换**（数值当场互换），适合录成验收视频。

### 5.1 硬件结构（手册 §6.4）

板载 8 位数码管分成**两组、每组 4 位**，同组共用段选线、用位选线分时点亮：

| 组 | 段选（7 段 + 小数点） | 位选（4 位独热） |
|---|---|---|
| 组0 | A0/G0/DP0… = B4 A4 A3 B1 A1 B3 B2 D5 | DN0_K1..K4 = G2 C2 C1 H1 |
| 组1 | A1/G1/DP1… = D4 E3 D3 F4 F3 E2 D2 H2 | DN1_K1..K4 = G1 F1 E1 G6 |

手册明确：**位选、段选都是高电平有效**（共阴极由三极管驱动）。因此本设计：
`seg_grp0[7:0] = {DP,G,F,E,D,C,B,A}`（bit=1 点亮），`dn0[3:0]` 为独热位选。

### 5.2 RTL 设计（`SegDisplay.v` + `SimpleTimer.v`）

**① 刷新交给硬件，CPU 只写"这一位显示什么"**

```
CPU: sw SEG_DIG[i]  ──►  8 个 5bit 寄存器 {mark, value[3:0]}（dig[0] 在最左）
                              │
                    4 相位扫描（每相位 SCAN_DIV 拍；pos = 0..3 是"模块内位置"）
                              │
   每个相位：左半边模块显示逻辑位 0..3 的第 pos 位，右半边显示逻辑位 4..7 的第 pos 位
     ├ 哪条总线驱动左边/右边 ← SEG_GROUP_SWAP（本板 =1：组0 那块模块在右）
     └ 这个位置对应哪条位选线 ← SEG_REVERSE_K （本板 =1：用 dn bit (3-pos)）
```
* 一次完整刷新 = 4 相位；`SCAN_DIV=16384`（50MHz 下 328µs/相位）→ 刷新率约 **760Hz**，无闪烁；
* 每个数字的占空比 1/4（动态扫描的常规代价）；
* `value=0..9` 显示数字，`A..E` 显示字母，**`0xF` = 空白**；
* `mark=1` → 该位小数点(DP)点亮，用作"正在比较/交换的两位"的高亮标记；
* `SEG_CTRL.bit0=0` → 段选、位选全拉低（整屏熄灭）。

**② 每步之间的停顿用硬件定时器，长度是参数**

`SimpleTimer` 是"启动后倒数 DELAY_CYCLES"的一次性定时器：

* 上板：`TIMER_DELAY = 20_000_000` → 50MHz 下 **0.4s**，人眼看得清每一步；
* 仿真：`TIMER_DELAY = 64` → 同一份机器码瞬间跑完。

> 这是本设计的关键取舍：如果把延时写成软件空循环，仿真要跑几亿个周期（几秒仿真时间）根本跑不动，
> 也就没法做**逐步比对**的自动验证。做成硬件参数后，**仿真验证的程序和烧进板子的程序是同一份机器码**。

**③ 上板确认用参数（只改参数，不改逻辑；已在 RTL 顶层/IP 参数里暴露）**

| 参数 | 含义 |
|---|---|
| `SEG_SCAN_DIV` | 扫描相位长度（默认 16384 ≈ 328µs → 刷新率约 760Hz） |
| `SEG_GROUP_SWAP` | =1 时**由 seg_grp0/dn0 驱动的模块在右边**（组1 在左）；=0 则相反 |
| `SEG_REVERSE_K` | =1 时**模块内 K1..K4 与"从左到右"相反**（K1 是最右那位）；=0 则相反 |

> ★ 本板实测：`SEG_GROUP_SWAP=1` 且 `SEG_REVERSE_K=1` 时，`dig0..dig7` 才是**从左到右**排列
> （即数组显示成 `9 3 7 1 5 …`，而不是镜像的 `… 5 1 7 3 9`）。**默认值已按实测设定**，
> 所以现在直接出 bitstream 就是正确方向。若换板子发现左右反了，把这两个参数**一起**翻过来即可。

### 5.3 显示布局与演示程序（`sort_demo.py`）

```
 数码管:  [0] [1] [2] [3] [4] | [5] [6] | [7]
 含义:     数组 a[0..4]        | 交换次数(十/个) | 空白
 高亮:     正在比较/交换的两位 → 小数点亮
```

程序（92 条指令，只用已有的 18 条指令子集）每轮做**同一个 5 元素冒泡排序**：

1. 把初值 `9,3,7,1,5` 写回数据区并刷新数码管，停一拍；
2. 双层循环：对每对 `(a[j], a[j+1])`：
   * 先**高亮**这两位（写 `值|0x10`），启动定时器停 0.4s → 观众看清"在比哪两个"；
   * 比较：`slt` 判断 `a[j+1] < a[j]`，若是则交换内存里的两个数、更新这两位数码管、交换次数 +1；
   * **取消高亮**（写回不带标记的值），再停 0.4s → 观众看清交换后的结果；
3. 排序结束显示 `1 3 5 7 9` + 交换次数 `07`，多停 1.2s；
4. 回到第 1 步重来一轮（方便录视频，不用反复按复位）。

寄存器分工：`x10`=MMIO 基址、`x11`=数据区基址、`x5`=轮次 i、`x6`=n-1、`x8`=j、`x9`=j 上界、
`x7`=`&a[j]`、`x20`=第 j 位数码管指针、`x28/x29`=`a[j]/a[j+1]`、`x14/x15`=交换次数个/十位。

> 数据与算法与 `tb_CPU.v` 用的流水线测试程序一致（`9,3,7,1,5 → 1,3,5,7,9`，`mem_clean.hex` 同一组数），
> 所以它同时也是"流水线算得对"的板级证据。

### 5.4 仿真验证：把显示轨迹逐状态比对（等效"文字版视频"）

`tb_EES338_sort.v` 干的事：把数码管的 8080 扫描总线**当成真实引脚采样**，还原出 8 位数字，
过滤掉连续 `sw` 造成的瞬态（同一状态连续 3 帧才算稳定），再与 `sort_demo.py` 生成的
**期望显示轨迹**逐状态比对（值 + 高亮位），实测输出如下：

```
  [1050000] state  0 : [93715]  mark[.....]  swap[00]     ← 乱序初值 9 3 7 1 5
  [2970000] state  1 : [93715]  mark[**...]  swap[00]     ← 高亮第 1、2 位（比较 9 和 3）
  [4650000] state  2 : [39715]  mark[.....]  swap[01]     ← 交换 ! 9>3 → 3 9 7 1 5
  [6330000] state  3 : [39715]  mark[.**..]  swap[01]     ← 高亮第 2、3 位
  [8130000] state  4 : [37915]  mark[.....]  swap[02]     ← 交换 9>7 → 3 7 9 1 5
  [9930000] state  5 : [37915]  mark[..**.]  swap[02]
 [11610000] state  6 : [37195]  mark[.....]  swap[03]     ← 交换 9>1
 [13290000] state  7 : [37195]  mark[...**]  swap[03]
 [15090000] state  8 : [37159]  mark[.....]  swap[04]     ← 交换 9>5（第一轮结束）
 [17010000] state  9 : [37159]  mark[**...]  swap[04]     ← 第二轮开始
 [18570000] state 10 : [37159]  mark[.....]  swap[04]     ← 3<7 不交换
 [20250000] state 11 : [37159]  mark[.**..]  swap[04]
 [22170000] state 12 : [31759]  mark[.....]  swap[05]     ← 交换 7>1
 [23850000] state 13 : [31759]  mark[..**.]  swap[05]
 [25530000] state 14 : [31579]  mark[.....]  swap[06]     ← 交换 7>5
 [27570000] state 15 : [31579]  mark[...**]  swap[06]
 [29370000] state 16 : [13579]  mark[.....]  swap[07]     ← 交换 3>1 → 排序完成 1 3 5 7 9
 [30930000] state 17 : [13579]  mark[.**..]  swap[07]
 [32610000] state 18 : [13579]  mark[.....]  swap[07]
 [34530000] state 19 : [13579]  mark[...**]  swap[07]
 [36090000] state 20 : [13579]  mark[.....]  swap[07]     ← 保持显示结果
 [42690000] state 21 : [93715]  mark[.....]  swap[00]     ← 回到乱序初值，重来一轮
```

对应的自动断言（全部 PASS）：

| 断言 | 含义 |
|---|---|
| `trace matches expected (values)` | **21 个显示状态逐个与期望轨迹一致**（含交换次数） |
| `initial state = 9 3 7 1 5` | 初值显示正确 |
| `final state = 1 3 5 7 9` | **排序结果正确 → 流水线算得对** |
| `final swap count = 07` | 交换次数正确（该数据冒泡排序共 7 次交换） |
| `swapped digits were the highlighted ones` | 值变化的位置 == 上一状态高亮的两位（高亮逻辑正确） |
| `highlight is always an adjacent pair` | 高亮永远是相邻两位或全灭 |
| `program restarts (state repeats)` | 程序会重来一轮（循环正常） |

### 5.5 上板验证与录制视频建议

1. 下载 `bitstream/EES338Top_sort.bit`（这份 bitstream 里烘焙的就是数码管排序演示程序）；
2. 上电即可看到数码管（**从左到右**）：`9 3 7 1 5 0 0` → 两位小数点轮流跳到正在比较的位置 →
   数值当场互换 → …… → `1 3 5 7 9 0 7`，停约 1.2s 后回到乱序重来；
3. 录视频建议：固定机位拍数码管 + 串口助手窗口，录 2~3 轮（每轮约 8s）；
   讲解点：① 亮点位置就是"当前比较的两位"；② 数值变化就是"交换发生"；
   ③ 最终 `1 3 5 7 9` 与终端 `tb_CPU.v` 的打印结果一致，说明流水线功能正确。

| 现象 | 排查 |
|---|---|
| 整屏不亮 | 检查是否把 `SEG_CTRL.bit0` 写成 0；或 bitstream 里烘焙的是别的演示程序（重新 `python gen_uart_demo.py sort` 再出 bitstream） |
| 数字左右顺序反了 | 把顶层参数 `SEG_GROUP_SWAP` 与 `SEG_REVERSE_K` **一起**翻转（0↔1），重新出 bitstream；不用改逻辑 |
| 个别段不亮/常亮 | 该段的引脚约束或硬件；对照 §5.1 引脚表核对 `EES338.xdc` |
| 闪烁/暗 | 扫描相位 `SCAN_DIV` 太大或太小；760Hz 刷新率下正常不应闪 |


---

## 6. 在 Vivado 里"封装 IP 核"

### 6.1 什么是"封装 IP 核"

普通 `.v` 文件对 Vivado 只是"一堆源码"：换工程要重新 `Add Sources`、自己例化、自己连线。
**封装（Component Packaging）就是把它变成 IP 目录里可复用、能在 Block Design(IP Integrator)
里拖拽例化的黑盒**，需要补四类元数据，最终写进 **`component.xml`**（这个文件 + 源码目录就是"IP 核"）：

| 元数据 | 本设计对应 |
|---|---|
| ① 身份 VLNV | `ees338.bjut:ip:EES338_Core:1.0` |
| ② 文件组 | 19 个 .v/.vh（synthesis 与 behavioralSimulation 两组） |
| ③ 参数（GUI 可改） | `BAUD_DIV`、`BAUD_DIV_BT`、`LCD_WR_CYCLES`、`LCD_RST_CYCLES`、`SEG_SCAN_DIV`、`TIMER_DELAY`、`HEX_FILE`、`DATA_FILE` |
| ④ 接口 | `CLK`(xilinx.com:signal:clock)、`RST`(signal:reset, ACTIVE_HIGH) → BD 可自动连线 |

### 6.2 封装对象：为什么把顶层拆成两层

把原 `EES338Top.v` 拆成（**只搬代码不改逻辑**）：

* `EES338Top.v` —— 板级胶水：MMCM(100→50MHz) + 上电/按键复位 + 输入两级同步 + LED 心跳；
* `EES338_Core.v` —— **被封装的部分**：`PipelineCPU` + `PeriphMMIO`（UART/蓝牙/LCD/数码管/定时器），
  只接受稳定的 `clk`(50MHz) 与高有效 `rst`，不含任何 Xilinx 原语。

好处：① IP 内没有 MMCM → 在 BD 里用标准 `clk_wiz` 供时钟；
② 仿真可直接例化 `EES338_Core`，**不需要编译 unisims 库**；
③ 顶层结构与原来一致，老测试（`tb_EES338_helloecho`）原样通过。

### 6.3 执行封装（已实际运行并通过）

```powershell
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace `
    -source E:/VivadoProject/Lab2/scripts/package_ip.tcl
```

脚本流程：建一个只含 IP 源文件的临时工程 → `ipx::package_project -import_files` →
填身份信息/参数说明/CLK+RST 接口 → 删掉被打包器误判为"复位接口"的 `lcd_rst_n` →
`create_xgui_files` + `update_checksums` + `save_core` → 把 `ip_repo` 挂到主工程 `Lab2.xpr`。

实测关键输出：

```
OK: IP visible in IP Catalog -> ees338.bjut:ip:EES338_Core:1.0
component.xml : E:/VivadoProject/Lab2/ip_repo/EES338_Core/component.xml
```

产物：

```
ip_repo/EES338_Core/
├── component.xml             <- IP 本体（VLNV/文件组/参数/接口）
├── src/  *.v, *.vh           <- 源文件副本（-import_files 自动搬入）
└── xgui/EES338_Core_v1_0.tcl <- 定制化 GUI 骨架
```

### 6.4 用封装好的 IP 搭 Block Design（已实际运行并通过）

```powershell
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace `
    -source E:/VivadoProject/Lab2/scripts/build_bd_demo.tcl
```

结构（全用标准 IP + 我们的 IP，没有手写胶水逻辑）：

```
sys_clk(100MHz) ─► clk_wiz_0 ──50MHz──┬─► soc_0/CLK            (我们的 IP)
                                       └─► rst_0/slowest_sync_clk
rst_btn(低有效) ─► inv_btn(NOT) ─► rst_0/ext_reset_in
rst_0/peripheral_aresetn ─► inv_rst(NOT) ─► soc_0/RST   (低有效 → 高有效)
soc_0 的 uart/bt/lcd/数码管引脚 ─► 顶层端口（名字与 EES338.xdc 一致，约束可直接复用）
```

实测结果：

```
IP in catalog: ees338.bjut:ip:EES338_Core:1.0
Synthesis finished with 0 errors, 0 critical warnings and 1 warnings.
  synth_1 status: synth_design Complete!
All user specified timing constraints are met.
Slice LUTs 1710 (8.22%)   Slice Registers 911 (2.19%)   Bonded IOB 43 (20.5%)
```

工程在 `bd_demo/bd_demo.xpr`（**独立工程，不影响已验证的主工程 `Lab2.xpr`**）。
GUI 打开即可看到 Block Design 图（`ees338_soc.bd`），可直接截图放进报告。

### 6.5 为什么没做成 AXI 接口（重要设计分析）

常见做法是把 CPU 核做成 **AXI4-Lite Master**（挂 AXIS Interconnect 接 AXI Uartlite/GPIO）。
本设计没这么做，原因是**会导致对已验证 CPU 代码的大幅改动**：

* 本 CPU 的 MMIO 读是 **MEM 级同拍组合返回**：`memio_rdata` 必须在 `memio_read` 拉高的那一拍有效；
* AXI4-Lite 读有**地址握手 + 多拍响应延迟**，无法同拍返回数据；
* 要让 CPU 支持"变长延迟访存"，必须给流水线加 `mem_ready/mem_stall`（冻结 MEM/WB、保持 EX/MEM、
  停 PC/IF/ID……）——正是"避免大幅修改 CPU 代码"要避免的事。

所以选择**保留同步 MMIO 语义**，用"自定义 IP + 标准 CLK/RST 接口"实现可复用。
后续若确实要接 AXI 外设，建议的增量路线：给 `PipelineCPU.v` 加一个 `mem_ready` 输入 +
在 MEM 级插一个 `AxiLiteMasterBridge.v`，CPU 其他部分不动（适合写进报告的"后续工作"）。

---

## 7. 测试与验证记录（全部实测）

### 7.1 仿真（`scripts/run_sim.ps1` 一键跑，25 个 tb 全 PASS）

| 测试平台 | 覆盖内容 | 关键数据 | 结果 |
|---|---|---|---|
| `tb_segdisplay.v` | 数码管控制器 + 定时器单元级：上电全空白、位选独热、4 相位扫描、8 位数值/位置、小数点高亮、0xF 空白、en 熄灭、刷新周期 = 4×SCAN_DIV、定时器倒数 | 25 项断言 | **ALL PASS** |
| `tb_EES338_sort.v` | **整机**：跑排序演示程序，从扫描总线还原 8 位数字，与期望显示轨迹**逐状态比对** | 21 个状态全对、最终 `1 3 5 7 9` + 交换 7 次 | **ALL PASS** |
| `tb_lcd128128.v` | LCD 控制器单元级：上电复位脉宽、WR# 低 10 拍、CS# 低 18 拍、锁存数据/RS、忙时忽略写、软复位 | 16 项断言 | **ALL PASS** |
| `tb_EES338_lcd.v` | 整机：8080 总线建模 → 128×128 帧缓存与 Python 期望图**逐字节比对** + 串口回执 | 命令 50 条、数据 1232 字节、帧缓存 0 处不符、收到 `LCD OK` | **ALL PASS** |
| `tb_EES338_bt.v` | 整机蓝牙回显（9600bps 灌 4 字节） | 4/4 正确回显 | **ALL PASS** |
| `tb_EES338_helloecho.v`（回归） | 原 UART 功能：周期 Hello + 回显，例化含 MMCM 的完整 `EES338Top` | `Hello, EES-338!` + `A b 3 !` | **ALL PASS** |
| `tb_uart_tx.v` / `tb_uart_rx.v`（回归） | UART 收发器单元级 | 各 4 字节收发正确 | **ALL PASS** |
| `tb_ALU.v`（改造为自检式） | ALU 层：ADD/SUB/OR/AND/XOR/SLT/SLL 结果与 zero 共 10 组 | 逐项比对 | **ALL PASS** |
| `tb_alu_flags.v` / `tb_divunit.v`（新增） | **标志位迁移**：ALU 的 SF/ZF/CF/OF/PF 与 MUL 家族 20 组；除法单元 13 组（除零/INT_MIN÷-1/无符号） | 逐项比对 | **ALL PASS** |
| `tb_muldiv.v` / `tb_flags.v`（新增） | **M 扩展与标志寄存器**：CPU 级 24 个结果 + 溢出计数 6；SoC 级 12 项（rdflags/MMIO 两条读通路一致性、粘滞位、逻辑指令不刷新） | 见 §11.8 | **ALL PASS** |
| `tb_EES338_flags.v`（新增） | 整机：溢出标志位演示程序的数码管显示（5 个场景逐位比对） | 见 §11.7 | **ALL PASS** |
| `tb_EES338_lcdread.v`（新增） | 整机：LCD **读回**通路（tb 扮演屏、读周期驱动 `0xA5`，检查程序打印 `1=10100101`）+ `tb_lcd128128.v` 新增读周期断言（RD# 低 12 拍、RS=1、CS# 低、总线采样） | 见 §3.5 | **ALL PASS** |
| `tb_EES338_btat.v`（新增） | 整机：**蓝牙 AT 探针**——tb **扮演 BLE 模组**（收到字节后静默一段时间再回 `OK\r\n`），验证程序把回显打印成 `A: OK` / `B: OK` / `C: OK` | 见 §4.6 | **ALL PASS** |

### 7.2 上板 bitstream（主工程 `Lab2.xpr`）

```powershell
python gen_uart_demo.py sort        # 选演示程序：hello|helloecho|echo|bt|lcd|sort
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace `
    -source E:/VivadoProject/Lab2/scripts/run_bitstream.tcl
```

实测（xc7a35tcsg324-1，50MHz 逻辑时钟）：

```
【接口功能阶段】All user specified timing constraints are met.
                Setup WNS = +4.84ns, TNS = 0, THS = 0
                Slice LUTs 1654 (7.95%)   Slice Registers 914 (2.20%)
                bitstream -> 已归档 bitstream/EES338Top_sort.bit (数码管排序演示)
                             另归档 EES338Top_lcd.bit( LCD 演示 ) / EES338Top_bt.bit( 蓝牙回显 )
                                    EES338Top_hello.bit / EES338Top_helloecho.bit
                                    EES338Top_lcdtest.bit / EES338Top_btcheck.bit (两个诊断包)

【溢出标志位迁移 + M 扩展之后】(见 §11.6，分支判定已改为独立比较器)
                All user specified timing constraints are met.
                Setup WNS = +0.335ns, TNS = 0, THS = 0
                Slice LUTs 2722 (13.09%)  Slice Registers 1140 (2.74%)
                bitstream -> 已归档 bitstream/EES338Top_flags.bit (溢出标志位演示)
```

### 7.3 演示程序一览（`python gen_uart_demo.py <模式>`）

| 模式 | 产物 hex | 现象 |
|---|---|---|
| `hello` | `uart_hello.hex` | 周期打印 `Hello, EES-338!` |
| `helloecho` | `uart_helloecho.hex` | 周期打印 + 随时回显（TX/RX 全测） |
| `echo` | `uart_echo.hex` | 纯回显 |
| `bt` | `bt_echo.hex` | 蓝牙回显（9600） |
| `lcd` | `lcd_demo.hex` + `lcd_demo_mem.hex` + `lcd_fb_expected.hex` | LCD 显示 `EES-338`/`LCD OK` + 串口回执（初始化带"等电源稳定"） |
| `lcdtest` | `lcd_test.hex` + `lcd_test_mem.hex` | LCD 自检：自动试 8 种配置、全屏点亮、串口报 `CFG r s v` |
| `btcheck` | `bt_check.hex` + `bt_check_mem.hex` | 蓝牙自检：周期发 'K' 并把收到的字节打印成 `RX=<字符>`（可做环回冷测） |
| **`flags`** | `flags_demo.hex` + `flags_demo_mem.hex` | 溢出标志位演示：数码管显示 8 个标志位，循环 5 个场景（见 §11.7） |
| **`lcdread`** | `lcd_read.hex` + `lcd_read_mem.hex` | LCD 读回自检：写 `0x5A/0x3C` 再读回，数码管+串口显示读到的字节（见 §3.5） |
| **`btat`** | `bt_at.hex` + `bt_at_mem.hex` | 蓝牙 AT 探针：发 `AT`/`AT\r\n`/`AT+NAME?\r\n` 并打印模组回显（见 §4.6/§4.7） |
| **`btat2`** | `bt_at2.hex` + `bt_at2_mem.hex` | 蓝牙 AT 探索器：问版本/名字/MAC/角色/波特率，最后 `AT+RESET` 重新广播（见 §4.7） |
| **`btcfg`** | `bt_cfg.hex` + `bt_cfg_mem.hex` | 蓝牙**模式脚扫描**：8 种 `BT_CTRL` 组合各停 10s，串口打印 `T<k> m.. h.. s..`（见 §4.8） |
| **`btseg`** | `bt_seg.hex` + `bt_seg_mem.hex` | **蓝牙→数码管**：手机发的字节以 16 进制滚动显示在数码管上（最新带小数点）+ 回发 + 串口 `RX=<字符>`（见 §4.9） |
| `sort` | `seg_sort.hex` + `seg_sort_mem.hex` + `seg_trace_{val,mrk,len}.hex` | 数码管排序动画 + 期望轨迹 |

> ⚠️ **重要**：`imem_boot_init.vh` / `dmem_boot_init.vh`（真正被综合进 bitstream 的程序与数据）
> 每次运行生成脚本都会被**当前模式覆盖**，所以"最后一次跑的必须是想要的那个模式"，然后再出 bitstream。


---

## 8. 复现命令清单（从零到验证）

```powershell
# 0) 环境：Vivado 2019.2；Python 3（生成脚本只用标准库）

# 1) 生成演示程序（hello|helloecho|echo|bt|lcd|sort 任选）
python gen_uart_demo.py sort

# 2) 仿真验证（数码管/LCD 单元 + 三个整机 + UART 回归，共 8 个 tb）
powershell -File scripts\run_sim.ps1
powershell -File scripts\run_sim.ps1 -Tb tb_EES338_sort     # 只跑某一个

# 3) 出 bitstream（主工程，顶层 EES338Top）
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source scripts/run_bitstream.tcl

# 4) 封装 IP 核（产物 ip_repo/EES338_Core/component.xml）
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source scripts/package_ip.tcl

# 5) 用封装好的 IP 搭 Block Design 并综合（独立工程 bd_demo/bd_demo.xpr）
& 'E:\Vivado2019.2\Vivado\2019.2\bin\vivado.bat' -mode batch -notrace -source scripts/build_bd_demo.tcl
```

---

## 9. 调试过程中抓到的问题（写报告可当亮点）

### 9.1 两类"外设状态可见性"竞态（同一类 bug，抓到两次）

**现象 A（LCD）**：SoC 级仿真里 LCD 只收到 42 条命令，少了 8 条"列地址低 4 位"命令，
屏幕上本该清掉的列没清。

**现象 B（定时器）**：数码管演示里 `1 3 5 7 1 9` 之类的中间状态**时有时无**，
延时短一下长一下（本该 0.4s 的停顿经常被跳过）。

**根因（同一类）**：`sw` 之后紧跟 `lw` 轮询时，**轮询的 MEM 级只比 `sw` 的 MEM 级晚 1 拍**，
而外设内部的 busy/计数寄存器要到第 2 拍才更新，于是那 1 拍读到的是"上一轮的值"：
* LCD：读到 `busy=0`（假空闲）→ 下一拍发的写请求被控制器丢掉；
* 定时器：读到 `0`（假"延时结束"）→ 轮询立刻退出，停顿被跳过。

**修复**（都是把"已受理但还没开始执行"的那一拍也报成忙，共 3 行）：

```verilog
// PeriphMMIO.v
wire        lcd_busy_cpu    = lcd_busy | lcd_wr_req | lcd_rst_req;
wire [31:0] timer_value_cpu = timer_start_p ? TIMER_DELAY : timer_value;
```

修复后：LCD 命令数恢复 50 条、帧缓存逐字节全对；数码管轨迹 21 个状态全对。
> 这两个 bug 在 UART 上不会暴露（UART 一帧 10 个 bit 时间＝上万拍，1~2 拍的偏差无所谓），
> 而是被"18 拍的 LCD 写时序"和"64 拍的短延时"这种**快外设**暴露出来的 —— 也正是
> "为什么值得给每个外设写一个精确的总线模型 tb"的答案。

### 9.2 LCD 初始化"不等电源稳定"（上板实测：屏全黑）

**现象**：串口正常打印 `LCD OK`（说明程序、CPU、LCD 写时序全都对），但**屏完全不亮**。

**根因**：第一版初始化序列 14 条命令在 5µs 内发完就立刻写像素；而 ST7565/ST7571 系列要求
**电源命令（0x2C/0x2E/0x2F）之后等电源稳定再开显示（0xAF）**，否则电荷泵还没建立，屏就是全黑。

**修复**：在初始化序列里插入"等待"标记（`lcd_demo.py` 的 `DELAY`），
用**硬件定时器**实现——上板每次 0.4s、仿真每次 64 拍，**同一份机器码**。
同时给 LCD 加了两个**运行时调试开关**（`LCD_CTRL.bit1` = RST 极性取反、`bit2` = WR#/RD# 互换输出）
和一个**自动试 8 种配置的自检程序**（`lcdtest`），把"硬件差异"这件事从"反复重新综合"变成"看串口报的配置号"。

### 9.3 其它

| 问题 | 现象 | 处理 |
|---|---|---|
| XDC 行尾注释 | `set_property PACKAGE_PIN V9 [get_ports lcd_wr_n]   # LCD_WR` → CRITICAL WARNING，约束失效 | xdc 不支持命令后跟 `#`；改用 `;#` 或注释单独成行 |
| IP 打包漏文件 | BD 里 OOC 综合报 `module 'UART_TX' not found` | 打包文件表要列全依赖（`UartChannel` 依赖 `UART_TX`/`UART_RX`） |
| `*_boot_init.vh` 没进 IP | 打包器看不到 ``ifdef SYNTHESIS`` 里的 include | 脚本显式把两个 .vh 加进合成/仿真文件组 |
| LCD 段选未受 en 控制 | `en=0` 时位选灭了但段选还在翻转（实测功耗/时序噪声） | `seg_grp <= en ? {...} : 8'h00`（由单元测试抓出） |
| tb 里 `$time` 单位 | 用 `%0d` 打印是 ns、用 `%0t` 打印会按 ps 显示 | 计时断言统一按 "20ns/周期" 换算，并用"量 10 个周期"消除 ±1 边界误差 |

---

## 10. 待上板确认项与风险（如实说明）

1. **蓝牙引脚方向**：手册 §11 标 `BT_RX=N2`/`BT_TX=L3`。本板 USB-UART 的实测经验是**手册方向与实测相反**
   （所以 UART 用了 `uart_txd→T4`、`uart_rxd→N5`），蓝牙也有可能是反的：不回显就把 `EES338.xdc`
   里 `bt_txd`/`bt_rxd` 两个引脚对调重出 bitstream。
2. **数码管左右顺序/分组**：手册只给了引脚名（DN0_K1..K4、DN1_K1..K4），未说明物理左右排布。
   若实测数字顺序不对，把顶层参数 `SEG_GROUP_SWAP` 与 `SEG_REVERSE_K` **一起**翻转（0↔1）即可，不用改逻辑。
3. **LCD 初始化序列**：按 ST7571/ST7565 兼容命令写。若花屏/对比度不对，按 `lcd_demo.py` 里
   `LCD_INIT` 的注释逐项调（0xA0/A1 段方向、0xC0/C8 行扫描、0xA2/A3 BIAS、0x24~0x26 电阻比、
   0x81 后的对比度字节），重新 `python gen_uart_demo.py lcd` 出 bitstream，**不用改 Verilog**。
4. **LCD 是否装配**：手册说板上带 128×128 LCD；若未装配则屏幕无显示，但串口仍会打印 `LCD OK`
   （说明程序流程完整跑完），不影响其他功能。
5. **IO 电平**：全部按 3.3V LVCMOS33 约束（与板级配置电压一致）；若实测不符改 `EES338.xdc`。
6. **BD 工程**：BD wrapper 里没有 `led0`（心跳灯在 `EES338Top` 里，不在 Core IP 内），
   复用 `EES338.xdc` 时会有 2 条 `led0` 的 CRITICAL WARNING，**不影响综合/实现**。
7. **生成物目录**：`bd_demo/`、`.workbuddy/` 可随时删除重建；`ip_repo/EES338_Core/` 重跑
   `package_ip.tcl` 即可再生成。

---

## 11. 溢出标志位迁移与 M 扩展乘除法（Lab1 进阶 ALU → 五级流水线 CPU）

> 本节对应需求："把 Lab1 里的溢出标志位和处理方法迁移到当前流水线 CPU 中；如果能把乘除法也加进来就加"。
> 结论：**标志位全部迁移完成**（含 Lab1 的 OF 判据与"标志位寄存"处理方式，并针对流水线做了必要增强），
> **乘除法也加进来了**（MUL/MULH/MULHU/MULHSU 单周期 + DIV/DIVU/REM/REMU 多周期），并**上板可演示**。

### 11.1 迁移对照表（Lab1 → 本项目）

| Lab1（进阶 ALU）里的做法 | 在本项目中的落地 | 涉及文件 |
|---|---|---|
| `alu.v`：ADD 同号相加、SUB 异号相减，结果符号翻转即 OF | **原样保留**（本来就有），并把"溢出上报"的门控从 ADD/SUB/ADDI 扩展到 MUL/DIV/REM | `ALU.v`、`ControlUnit.v` |
| `alu.v`：SF/CF/ZF/PF 与 OF **一起产生、一起寄存**，运算结束后可读 | 新增 `FlagReg.v`：每条**算术类**指令在 EX 级退役那一拍刷新；`flags_o`/`of_count_o` 引给 `PeriphMMIO` | `FlagReg.v`、`PipelineCPU.v`、`PeriphMMIO.v` |
| `mult_alu.v`：MUL 的 OF = "64 位积无法用低 32 位的符号扩展表示" | 新增 `MUL/MULH/MULHU/MULHSU`（单周期，综合成 DSP48），OF 用**同一判据** | `ALU.v` |
| `mult_alu.v`：加减交替法（非恢复余数）除法；DIV/REM 的 OF = 除零 或 INT_MIN÷(-1) | 拆成独立 `DivUnit.v`（多周期），新增 `DIV/DIVU/REM/REMU` + **EX 级多周期停顿** | `DivUnit.v`、`PipelineCPU.v` |
| `alu.v` 的 `OP=1111` **CLR** 指令清标志 | 新增自定义指令 `clrflags`（清标志与计数）与 `rdflags`（把标志读进 rd） | `ControlUnit.v`、`asm.py` |
| ——（Lab1 只有单次标志） | **增强**：新增 OF 粘滞位 `OF_STICKY` 与 `OF_COUNT` 溢出计数器（流水线里"事后查询"必需，见 §11.4） | `FlagReg.v` |

### 11.2 指令与译码编码

**ALU 控制码（`ALU.v`，4 位：原有 7 个 + 新增 8 个正好填满）**

| alu_ctrl | 运算 | alu_ctrl | 运算 |
|---|---|---|---|
| `0000` | ADD | `0111` | **MUL**（低 32 位） |
| `0001` | SUB | `1000` | **MULH**（有符号×有符号 高 32 位） |
| `0010` | OR | `1001` | **MULHU**（无符号×无符号 高 32 位） |
| `0011` | AND | `1010` | **MULHSU**（有符号×无符号 高 32 位） |
| `0100` | XOR | `1011` | **DIV**（多周期） |
| `0101` | SLT | `1100` | **DIVU**（多周期） |
| `0110` | SLL | `1101` | **REM**（多周期） |
| `1111` | 无效/空操作 | `1110` | **REMU**（多周期） |

**M 扩展指令编码**（RV32M 标准：`opcode=0110011`、`funct7=0000001`）

| funct3 | 指令 | funct3 | 指令 |
|---|---|---|---|
| `000` | `mul` | `100` | `div` |
| `001` | `mulh` | `101` | `divu` |
| `010` | `mulhsu` | `110` | `rem` |
| `011` | `mulhu` | `111` | `remu` |

**自定义标志指令**（`opcode=0001011` = custom-0，即 `macro.vh` 里的 `` `OP_CUSTOM0 ``）

| 编码 | 指令 | 语义 |
|---|---|---|
| `0x0000_000B` | `clrflags` | 清标志寄存器与溢出计数（对应 Lab1 的 CLR） |
| `(1<<12)\|(rd<<7)\|0x0B` | `rdflags rd` | 把标志字读到 rd（低 8 位有效） |

### 11.3 标志位规格（`FlagReg.v`）

`CPU_FLAGS`（`0x1000_0300`，也可用 `rdflags` 读回）：

| 位 | 名字 | 含义 |
|---|---|---|
| 0 | SF | 结果符号位 |
| 1 | ZF | 结果为零 |
| 2 | CF | ADD 的进位 / SUB 的**借位**（1 = 发生借位，即无符号 `src1 < src2`） |
| 3 | OF | **最近一次**算术运算是否溢出 |
| 4 | OF_STICKY | **粘滞溢出位**：一旦置 1 就保持，直到 `clrflags` |
| 5 | PF | 结果偶校验 `~^result`（与 Lab1 一致：32 位） |
| 6 | SEEN | 复位后是否执行过算术类指令 |
| 7 | — | 保留 0 |

`OF_COUNT`（`0x1000_0304`）：算术溢出**累计次数**（32 位，`clrflags` 清零）。

**逐运算的 OF 判据**（与 Lab1 一致）

| 运算 | OF 判据 |
|---|---|
| ADD / ADDI | 两操作数同号且结果符号与原操作数不同 |
| SUB | 两操作数异号且结果符号与被减数不同 |
| MUL | 64 位积 `(63:32) != {32{积[31]}}`（不能用低 32 位符号扩展表示） |
| MULH / MULHU / MULHSU | 恒 0（高 32 位本身精确，不存在"截断溢出"） |
| DIV / DIVU / REM / REMU | 除数 = 0，或 `INT_MIN ÷ (-1)`（仅 `DIV/REM`；`DIVU/REMU` 不算溢出） |
| AND / OR / XOR / SLT / SLL | 恒 0（逻辑/移位不可能溢出） |
| LW / SW / AUIPC 等地址计算 | **不参与判定**（`upd_flags` 门控，从源头避免误报） |

### 11.4 与 Lab1 的三处**有意差异**（报告里建议写明"为什么"）

1. **哪些指令刷新标志**
   Lab1 的 ALU 对**每条**指令都刷新 SF/ZF/PF（逻辑运算 OF/CF=0）。
   本项目把刷新限定为**算术类**（ADD/SUB/ADDI/MUL/DIV/REM），因为流水线里 `lw/sw/auipc/andi`
   被大量用于地址计算与轮询，如果它们也刷新，OF 会被"冲掉"（例如 `lw x12, 300(x10)`
   就会把刚产生的溢出标志覆盖掉），"事后查询溢出"就失去意义 —— 这正是课程要求里
   "不要把地址计算误报为溢出"的延伸。
2. **SUB 的 CF 语义**
   Lab1 里 `carry = ~add_result[32]`（即 **1 = 无借位**）；本项目按标准借位语义
   `CF = sub_res[32]`（**1 = 有借位**，即无符号 `src1 < src2`），更符合"标志位"的常规读法。
3. **除零 / `INT_MIN ÷ (-1)` 的商与余**
   Lab1 把两者都置 0；本项目按 **RISC-V 语义**给出：除零 → 商 = `-1`、余 = 被除数；
   `INT_MIN ÷ (-1)` → 商 = `INT_MIN`、余 = 0。两者的 **OF 都置 1**（与 Lab1 一致）。

另外新增了 Lab1 没有的**粘滞位 + 溢出计数**：流水线里"溢出"只发生在某一拍，若只有单次标志，
程序必须紧跟着把它读走；有了粘滞位/计数器，任意时刻都能查到"曾经溢出过几次"。

### 11.5 多周期除法怎么插进五级流水线（关键设计）

`DivUnit.v` 是一个 3 态机：`IDLE → CALC(32 拍) → FIN(1 拍)`，`done` 在收尾拍为高。
它放在 **EX 级**，除法指令一进入 EX 就启动，期间：

| 部件 | 停顿期间的处置 | 原因 |
|---|---|---|
| `PC` / `IF/ID` / `ID/EX` | **保持不动**（`pipe_stall = stall \|\| ex_stall`） | 除法指令自己的控制信息与操作数还要用 |
| `EX/MEM` | **注入气泡**（`valid=0`、`reg_we=0`、`mem_we=0`） | 否则除法会被当成"已经算完"，垃圾结果会写回 rd / 误写内存 |
| 溢出上报 | `overflow_ex_next` 增加 `!ex_stall` 条件 | 停顿期间 ALU 的无关组合结果不能算溢出 |
| 标志刷新 | 只在收尾拍（`done`）刷新**一次** | 避免一条除法把溢出计数加很多次 |

**收尾拍（FIN）**：`done=1` → 撤销停顿，`div_quot/div_rem/div_of` 当拍写进 `EX/MEM`，
于是**下一条指令进入 EX 时就能通过 EX/MEM 前递拿到除法结果**，不需要额外停顿
（`tb_muldiv.v` 里"除法 → 紧跟一条依赖它的加法"实测前递成功）。

**操作数锁存**：`DivUnit` 在 `start` 那一拍把被除数/除数锁存进 `dvd_r/dvs_r`。
因为停顿期间 `EX/MEM` 被注气泡，前递选择会变（`fwd_a` 可能从 EX/MEM 切到 MEM/WB），
若直接用组合输入，中途就会变值。

**代价**：一条除法占用 EX **34 拍**（1 拍装载 + 32 拍迭代 + 1 拍收尾），期间流水线停顿 33 拍。

### 11.6 时序影响与修复（实测数据，报告可直接引用）

* 加进 3 个 64 位乘法器（`mul_ss`/`mul_uu`/`mul_su`）之后第一次实现：
  **`Timing constraints are not met`，WNS = -0.009ns**。
  关键路径：`ex_mem_rd_r → 前递选择 → 乘法器(DSP48×2) → result → zero → 分支判定 → PC`。
  根因是**分支判定复用了 ALU 的 `zero` 输出**，把乘法器串进了"分支 → PC"这条本来就紧的路径。
* **修复**：分支判定不再复用 ALU 结果，改用一条独立的 32 位比较器
  （`br_eq = (fwd_a == fwd_b)`、`br_lt = $signed(fwd_a) < $signed(fwd_b)`），语义与原来完全一致
  （原来 ALU 对分支做的就是 SUB / SLT）。这样"分支 → PC"与"乘法器 → 写回/标志"变成两条互不干扰的路径。
* 修复后（xc7a35tcsg324-1，50 MHz）：

```
All user specified timing constraints are met.
Setup WNS = +0.335ns   TNS = 0   THS = 0
Slice LUTs 2722 (13.09%)   Slice Registers 1140 (2.74%)
```

> 余量比迁移前（+4.84ns）小，主要就是那 3 个 64 位乘法器带来的（DSP48 的输入/输出布线）。
> 若需要更大余量，最省事的做法是"给乘法器输出加一级流水寄存器"（MUL 变 2 拍），
> 或者只保留 `MUL/MULH` 两个乘法器（去掉 MULHSU）。

### 11.7 上板演示：`bitstream/EES338Top_flags.bit`

程序 `flags_demo.hex`（`python gen_uart_demo.py flags` 生成，串口打印 `FLAGS DEMO`），
把标志寄存器**逐位**显示在 8 位数码管上：`SF ZF CF OF STK PF SEEN CNT`
（`CNT` = 溢出次数奇偶；`STK` 那一位的小数点同时点亮 = 曾溢出过，非常醒目）。

| 场景 | 执行的运算 | 数码管（从左到右） | 说明 |
|---|---|---|---|
| ① | `0x80000000 + 0xFFFFFFFF` | `0 0 1 1 1̇ 0 1 1` | 负+负=正 → OF=1；进位 CF=1；粘滞位置 1（小数点也亮） |
| ② | `0x7FFFFFFF + 0` | `0 0 0 0 1̇ 0 1 1` | 不溢出（OF 归 0），但**粘滞位保持 1** |
| ③ | `0 - 5` | `1 0 1 0 1̇ 0 1 1` | SF=1、借位 CF=1 |
| ④ | `INT_MIN × INT_MIN` | `0 1 0 1 1̇ 1 1 0` | 低 32 位 = 0 → ZF=1、PF=1；OF=1；溢出次数变 2（偶数 → CNT=0） |
| ⑤ | `clrflags` | `0 0 0 0 0 0 0 0` | 全灭，演示"清标志 / 清计数" |

（表中 `1̇` 表示该位小数点同时点亮。）每步之间是 0.4s 硬件延时，循环播放，适合录视频。
实现上程序用 `rdflags` 读标志、用 `lw 772(x10)` 读 MMIO 的溢出计数，
"取第 i 位"用的是 `slli` 左移到位 31 + `slt` 与 0 比较（本 ISA 没有 `srl`）。

### 11.8 验证（全部实测通过）

| 新增测试平台 | 覆盖内容 | 结果 |
|---|---|---|
| `tb_alu_flags.v` | ALU 层：ADD/SUB/逻辑/移位/MUL 家族的 res + SF/ZF/CF/OF/PF 共 20 组逐项比对 | **ALL PASS** |
| `tb_divunit.v` | `DivUnit` 单元：13 组除/余（正负、整除、除零、INT_MIN÷-1、无符号大数）逐项比对 | **ALL PASS** |
| `tb_muldiv.v` | CPU 级跑 `inst_muldiv.hex`：24 个结果写回 DMEM 逐字比对 + `of_count=6` + 粘滞位；含"除法→紧跟依赖"前递与背靠背除法 | **ALL PASS** |
| `tb_flags.v` | SoC 级跑 `inst_flags.hex`：12 项（`rdflags` 与 MMIO 两条读通路一致性、粘滞位保持、逻辑指令不刷新、`clrflags` 清零、末态标志字 `0x72`） | **ALL PASS** |
| `tb_EES338_flags.v` | 整机跑 `flags_demo.hex`：从数码管 MMIO 写序列抓帧，5 个场景的显示模式逐位比对 | **ALL PASS** |

同时**回归**了迁移前的全部测试：`tb_ALU`、`tb_overflow`、`tb_forward`、`tb_hazard`、`tb_branch`、
`tb_inst_alu`、`tb_compare`、`tb_CPU`（五整数排序：单周期 CPI=1.000 / 流水线 CPI=1.463）、
`tb_lcd128128`、`tb_segdisplay`、`tb_EES338_lcd`、`tb_EES338_lcdtest`、`tb_EES338_bt`、
`tb_EES338_btcheck`、`tb_EES338_sort`、`tb_EES338_helloecho`、`tb_uart_tx`、`tb_uart_rx`。

> 注意：`tb_CPU.v` 等早期 testbench 的 hex 路径是**相对**的（`../../../../Lab2.file/...`），
> 所以 `run_sim.ps1` 的工作目录特意设在工程根目录下 **4 层**（与 Vivado GUI 的
> `Lab2.sim/sim_1/behav/xsim` 同深度）；否则 `$readmemh` 找不到文件，程序会变成全 NOP，
> 测试会以"所有寄存器都是 0"的假失败结束。

---

## 附：文档关系
* `UART集成说明.md` —— 早期只讲 UART 的文档（更细的串口逐项自检步骤），内容已并入本文第 2 节。
* `README.md` —— 仓库总览与命令入口。

