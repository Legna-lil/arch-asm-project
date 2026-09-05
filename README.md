# arch-asm-project
北理工大四计组与汇编课程设计
## 计组部分
基于大三下计组 单周期流水线CPU 搭建，实现 五级流水线 + 硬布线 + 溢出检测
### 调整
- 五级流水线： [./Lab2.srcs/sources_1/new/PipelineCPU.v](./Lab2.srcs/sources_1/new/PipelineCPU.v)
- 模块：ALU, ControlUnit（微指令控制信号）, DataMemory（数据内存）, InstructionMemory（指令内存）, RegisterFile, PC, ImmediateGenerator
- 测试用例： [./Lab2.srcs/sim_1/new/tb_CPU.v](./Lab2.srcs/sim_1/new/tb_CPU.v) —— 执行一个冒泡排序程序；预计 CPI=1.4；其余为具体模块的单元测试

## 汇编部分
实现 UART 接口，能够通过串口双向交换信息

顶层模块：[./Lab2.srcs/sources_1/new/EES338Top.v](./Lab2.srcs/sources_1/new/EES338Top.v)

详见 [./UART集成说明.md](./UART集成说明.md)

