# 排序程序波形分析：stall / flush 激活点与正确性证明

## 一、波形信号说明

| 信号 | 含义 |
|---|---|
| `pc[31:0]` / `npc[31:0]` | 当前取指 PC / 下一拍 PC |
| `stall` | `load_use` 数据冒险停顿，高电平有效 |
| `flush` (= `branch_taken_ex`) | 分支/跳转冲刷，高电平有效 |
| `branch_taken_ex` | EX 级判定分支/跳转被采纳 |
| `rdst_1:0` / `dat_1:0` | WB 级写回目标寄存器号与写回数据 |
| `mem...` | DMEM 写数据（可观察 swap 是否真写入） |

时钟周期：`#5 clk = ~clk` ⇒ 周期 10 ns。波形上每 10 ns 为一个时钟。

---

## 二、这段汇编在做什么

截图对应的是**内层循环体**（冒泡排序比较-交换部分）：

```
0x00400028  lw  x28, 0(x7)      # t3 = arr[j]
0x0040002c  lw  x29, 4(x7)      # t4 = arr[j+1]
0x00400030  slt x30, x29, x28   # t5 = (arr[j+1] < arr[j])
0x00400034  beq x30, x0, no_swap# if t5==0, 跳到 0x40（不交换）
0x00400038  sw  x29, 0(x7)      # swap: arr[j]   = arr[j+1]
0x0040003c  sw  x28, 4(x7)     #        arr[j+1] = arr[j]
0x00400040  addi x5, x5, 1      # j++
0x00400044  jal x0, inner       # 无条件跳回 0x1c，继续内层比较
0x00400048  addi x18,x18,-1     # outer--（outer_next，被 jal 冲刷）
```

> `0x00400034` 的 `beq` 目标：`PC+12 = 0x40`；  
> `0x00400044` 的 `jal` 目标：`PC-40 = 0x1c`。

---

## 三、stall 激活点分析

**时间范围**：约 786 ns ~ 795 ns（一个周期的高脉冲）

**对应指令**：
- `0x2c  lw x29, 4(x7)`  处于 EX 级
- `0x30  slt x30, x29, x28` 处于 ID 级

**为什么必须 stall？**

`slt` 的源寄存器 `x29` 正是前一条 `lw` 的目的寄存器。`lw` 的数据要到 **MEM 级末尾** 才从 DMEM 读出，而 `slt` 在 **EX 级** 就需要该数据。仅靠前递也无法解决：当 `lw` 还在 EX/MEM 时，`slt` 已经到达 EX，数据尚未产生。因此必须插入一拍 bubble，让 `lw` 进入 MEM/WB 后再把数据前递给 `slt`。

> 这正是 `PipelineCPU.v` 中 `load_use` 检测逻辑的功能：
> ```verilog
> wire load_use = id_ex_valid && id_ex_mem_to_reg && (id_ex_rd != 5'd0) &&
>                 ((id_ex_rd == rs1_id && rs1_used) ||
>                  (id_ex_rd == rs2_id && rs2_used));
> assign stall = load_use;
> ```

**stall 期间流水线状态**：
- IF/ID 保持不动，PC 不增加；
- ID/EX 被注入 NOP bubble（控制信号清零）；
- 下一拍 `lw` 进入 MEM/WB，`slt` 进入 EX，可通过 MEM/WB → EX 前递拿到 `x29`。

---

## 四、flush 激活点分析

截图中可见 **两次 flush 高脉冲**，说明 EX 级两次判定分支/跳转被采纳。

### Flush ①：约 800 ns ~ 815 ns

**对应指令**：`0x34  beq x30, x0, no_swap`

**场景**：本次比较 `arr[j+1] >= arr[j]`，`slt` 得到 `x30 = 0`，分支条件成立（beq 判 zero）。

**冲刷了什么？**
- 分支目标：`0x34 + 12 = 0x40`（`addi x5, x5, 1`）；
- 在 beq 进入 EX 时，流水线已按顺序取到后面的 `0x38 sw` 和 `0x3c sw`；
- `flush` 把 IF/ID 和 ID/EX 中的两条 `sw` 清成 NOP，避免错误地写入交换数据。

### Flush ②：约 840 ns ~ 855 ns

**对应指令**：`0x44  jal x0, inner`

**场景**：内层循环结束，`jal` 无条件跳回 `0x1c`（`bge x5, x18, outer_next`）。

**冲刷了什么？**
- `jal` 在 EX 时，IF/ID 中已顺序取到 `0x48 addi x18, x18, -1`；
- `flush` 把它清掉，下一拍从 `0x1c` 重新开始取指。

> `PipelineCPU.v` 中 `flush = branch_taken_ex`，而 `branch_taken_ex` 对 `is_jal` 也置位，因此 jal 同样会触发冲刷。

---

## 五、如何证明流水线功能正确

### 1. 冒险处理位置与代码一一对应

| 波形事件 | 激活原因 | 对应代码 |
|---|---|---|
| stall 脉冲 | load-use：`lw` 后紧跟使用其结果的 `slt` | `0x2c` → `0x30` |
| flush ① | beq 成立，清除两条错误取指的 sw | `0x34` |
| flush ② | jal 无条件跳转，清除顺序取指的 addi | `0x44` |

这说明 **load-use 检测、分支在 EX 级判定、flush 优先级** 均按设计工作。

### 2. 功能结果正确

`tb_CPU.v` 在程序结束后自检：

```verilog
if (uut.dm_inst.mem[0] == 1 && uut.dm_inst.mem[1] == 3 &&
    uut.dm_inst.mem[2] == 5 && uut.dm_inst.mem[3] == 7 &&
    uut.dm_inst.mem[4] == 9 && uut.dm_inst.mem[5] == 5)
    $display("RESULT: PASS - array sorted correctly");
```

程序最终输出 `mem[0..4] = 1, 3, 5, 7, 9`，`mem[5] = 5` 保持不变 ⇒ **功能正确**。

### 3. 性能统计自洽

仿真报告的性能计数器：

```
cycles  = 199
retired = 136
stalls  = 11
flushes = 24
CPI     = 1.463
```

可按气泡模型验证：

```
总周期 =  retired  +  load-use停顿  +  分支冲刷气泡  +  流水线填充
      =  136      +  11           +  24 × 2        +  4
      =  199
```

与波形中观察到的 stall / flush 脉冲完全吻合：每多一次分支/跳转，就多两个气泡。

### 4. 波形微观证据

- **rdst/dat 写回**：可观察到 WB 级正确写回 `x5`（j 计数器）等寄存器；
- **mem 写入**：当交换路径执行时，`mem` 信号出现两次写脉冲（`sw x29, 0(x7)` 和 `sw x28, 4(x7)`），说明数据确实被交换；
- **npc 跳变**：flush 期间 `npc` 从顺序 `PC+4` 切换到分支/跳转目标（`0x40` 或 `0x1c`），符合预期。

---

## 六、一句话结论

该波形直观展示了五级流水线在真实排序程序中同时处理 **load-use 数据冒险** 与 **分支/跳转控制冒险** 的过程：stall 和 flush 激活的位置与汇编代码的冒险点精确对应，且程序最终通过 `RESULT: PASS` 自检，证明流水线在保持功能正确的前提下实现了指令级并行。
