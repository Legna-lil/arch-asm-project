`timescale 1ns / 1ps

// RISC-V 五级流水线 CPU (IF -> ID -> EX -> MEM -> WB)
// 硬布线控制器 / EX 级 Forwarding / load-use Stall / 分支 Flush
module PipelineCPU #(
    parameter HEX_FILE  = "../../../../Lab2.file/inst_code_clean.hex",
    parameter DATA_FILE = "../../../../Lab2.file/mem_clean.hex"
)(
    input clk,
    input rst,
    // ===== 存储器映射外设(MMIO)总线：MEM 级访存译码结果 =====
    // 纯 CPU 仿真时可全部悬空/不连接，不影响原有功能；
    // 板上 SoC 通过本组信号把 UART 等外设挂到 0x1000_0000 ~ 0x1000_FFFF。
    input  wire [31:0] memio_rdata,  // 外设窗口读回数据（LW 命中窗口时代替 RAM 数据）
    output wire        memio_read,   // 本拍 MEM 级在读外设窗口
    output wire        memio_write,  // 本拍 MEM 级在写外设窗口
    output wire [31:0] memio_addr,   // MEM 级访存地址（ALU 结果）
    output wire [31:0] memio_wdata,  // SW 写数据（已前递）
    // ===== 状态标志寄存器输出（Lab1 溢出标志位迁移；供 PeriphMMIO / 波形观察）=====
    output wire [7:0]  flags_o,      // [0]SF [1]ZF [2]CF [3]OF [4]OF_STICKY [5]PF [6]SEEN [7]0
    output wire [31:0] of_count_o    // 溢出累计次数（clrflags 指令清零）
    );

    localparam NOP = 32'h00000013; // addi x0, x0, 0

    // ===================== IF =====================
    wire [31:0] pc_curr;
    wire [31:0] instr_if;

    wire        stall;              // load-use 停顿（原有）
    wire        flush;
    // ---- 多周期除法（Lab1 加减交替除法迁移）：EX 级停顿 ----
    wire        ex_stall;                                            // 除法进行中：暂停 PC/IF-ID/ID-EX，EX/MEM 注气泡
    wire        div_start, div_busy, div_done_w, div_of;
    wire [31:0] div_quot, div_rem;
    wire        pipe_stall = stall || ex_stall;                      // 流水线整体暂停
    wire        branch_taken_ex;
    wire [31:0] branch_target_ex;

    // 分支发生时下一条 PC 为分支目标，否则 PC+4；stall 时保持
    wire [31:0] pc_next = branch_taken_ex ? branch_target_ex : (pc_curr + 32'd4);

    PC pc_inst (
        .clk(clk),
        .rst(rst),
        .en(!pipe_stall || flush), // 停顿（load-use 或除法）时 PC 保持；分支跳转(flush)优先级更高
        .npc(pc_next),
        .pc(pc_curr)
    );

    InstructionMemory #(.HEX_FILE(HEX_FILE)) im_inst (
        .addr(pc_curr),
        .instr(instr_if)
    );
    // ---------- IF/ID 流水线寄存器 ----------
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;
    reg        if_id_valid;       // 该级是否含有效指令（flush/stall 控制）

    always @(posedge clk) begin
        if (rst || flush) begin        // 分支 flush：清空错误路径指令
            if_id_pc    <= 32'b0;
            if_id_instr <= NOP;
            if_id_valid <= 1'b0;
        end
        else if (!pipe_stall) begin     // 正常推进；停顿（load-use / 除法）时保持
            if_id_pc    <= pc_curr;
            if_id_instr <= instr_if;
            if_id_valid <= 1'b1;
        end
    end

    // ===================== ID =====================
    wire [4:0]  rs1_id = if_id_instr[19:15];
    wire [4:0]  rs2_id = if_id_instr[24:20];
    wire [4:0]  rd_id  = if_id_instr[11:7];
    wire [6:0]  opcode = if_id_instr[6:0];
    wire [2:0]  funct3 = if_id_instr[14:12];
    wire [6:0]  funct7 = if_id_instr[31:25];

    wire        reg_we_id;
    wire        mem_we_id;
    wire        mem_to_reg_id;
    wire [3:0]  alu_ctrl_id;
    wire        alu_src_sel_id;   // 0: rdata2, 1: imm
    wire        alu_src1_sel_id;  // 0: rdata1, 1: pc
    wire [2:0]  imm_type_id;
    wire        is_jal_id;
    wire        is_branch_id;
    wire        is_arith_id;      // ADD/SUB/ADDI，用于溢出检测
    // ---- 溢出标志位迁移新增的译码结果（M 扩展 + 标志指令）----
    wire        is_mul_id;        // M 扩展乘法（单周期）
    wire        is_div_id;        // M 扩展除法/取余（多周期）
    wire        is_div_signed_id; // 1=DIV/REM（有符号）
    wire        is_div_rem_id;    // 1=REM/REMU（取余）
    wire        is_rdflags_id;    // rdflags：读标志寄存器
    wire        is_clrflags_id;   // clrflags：清标志寄存器
    wire        upd_flags_id;     // 会刷新标志寄存器的指令（算术类）

    ControlUnit ctrl_inst (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .reg_we(reg_we_id),
        .mem_we(mem_we_id),
        .mem_to_reg(mem_to_reg_id),
        .alu_ctrl(alu_ctrl_id),
        .alu_src_sel(alu_src_sel_id),
        .alu_src1_sel(alu_src1_sel_id),
        .imm_type(imm_type_id),
        .is_jal(is_jal_id),
        .is_branch(is_branch_id),
        .is_arith(is_arith_id),
        .is_mul(is_mul_id),
        .is_div(is_div_id),
        .is_div_signed(is_div_signed_id),
        .is_div_rem(is_div_rem_id),
        .is_rdflags(is_rdflags_id),
        .is_clrflags(is_clrflags_id),
        .upd_flags(upd_flags_id)
    );

    wire [31:0] imm_out;
    ImmediateGenerator imm_gen_inst (
        .instr(if_id_instr),
        .imm_type(imm_type_id),
        .imm(imm_out)
    );

    // 寄存器堆读（写优先旁路在 RegisterFile 内部实现）
    wire [31:0] rdata1, rdata2;
    wire [4:0]  wb_rd;
    wire        wb_reg_we;
    wire [31:0] wb_data;

    RegisterFile rf_inst (
        .clk(clk),
        .reg_we(wb_reg_we),
        .raddr1(rs1_id),
        .raddr2(rs2_id),
        .waddr(wb_rd),
        .wdata(wb_data),
        .rdata1(rdata1),
        .rdata2(rdata2)
    );

    // ID 级源操作数使用情况（用于 load-use 检测）
    // rs1 被使用：alu_src1_sel==0（JAL/AUIPC 用 PC，不用 rs1）
    // rs2 被使用：ALU 用 rdata2（非立即数类）、SW 的存储数据、分支比较
    // JAL 不用 rs1/rs2（rs1/rs2 字段属于 J 型立即数），避免误判产生多余 stall
    wire rs1_used = !alu_src1_sel_id && !is_jal_id;
    wire rs2_used = (!alu_src_sel_id || mem_we_id || is_branch_id) && !is_jal_id;

    // ===================== ID/EX 流水线寄存器 =====================
    // 注意：mem_to_reg 同时充当 mem_read 用于冒险检测
    reg        id_ex_valid;         // 有效指令标志（气泡为 0）
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_pc4;
    reg [31:0] id_ex_rdata1;
    reg [31:0] id_ex_rdata2;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [3:0]  id_ex_alu_ctrl;
    reg        id_ex_alu_src_sel;
    reg        id_ex_alu_src1_sel;
    reg        id_ex_mem_we;
    reg        id_ex_mem_to_reg;
    reg        id_ex_reg_we;
    reg        id_ex_is_branch;
    reg        id_ex_is_jal;
    reg        id_ex_is_arith;      // ADD/SUB/ADDI，用于溢出检测
    // ---- 溢出标志位迁移新增（M 扩展 + 标志寄存器指令）----
    reg        id_ex_is_mul;        // MUL 类（单周期）
    reg        id_ex_is_div;        // DIV/REM 类（多周期，走 DivUnit）
    reg        id_ex_div_signed;    // 除法是否有符号
    reg        id_ex_div_rem;       // 1=取余（REM/REMU），0=取商
    reg        id_ex_upd_flags;     // 本指令是否会刷新标志寄存器
    reg        id_ex_is_rdflags;    // rdflags（把标志寄存器写进 rd）
    reg        id_ex_is_clrflags;   // clrflags（清标志）

    // load-use 冒险：ID/EX 中是有效 lw，且 ID 级指令需要其结果
    wire load_use = id_ex_valid && id_ex_mem_to_reg && (id_ex_rd != 5'd0) &&
                    ( (id_ex_rd == rs1_id && rs1_used) ||
                      (id_ex_rd == rs2_id && rs2_used) );

    assign stall = load_use;

    // ---- 多周期除法（迁移 Lab1 的加减交替除法单元）：EX 级停顿 ----
    // 除法指令进入 EX 后 DivUnit 需要 BITS+2 拍，期间必须：
    //   * 保持 PC / IF-ID / ID-EX —— 除法指令自己的控制信息与操作数还要用
    //   * 给 EX/MEM 注入气泡 —— 否则除法会被当成"已经算完"，把垃圾结果写回 rd
    // 收尾拍 done=1 时撤销停顿：结果当拍写入 EX/MEM，下一条指令进入 EX 时即可前递
    assign div_start = id_ex_valid && id_ex_is_div && !div_busy;
    assign ex_stall  = id_ex_valid && id_ex_is_div && !div_done_w;

    always @(posedge clk) begin
        if (rst || flush) begin
            // rst 复位 或 分支/跳转(flush)：ID/EX 注入气泡，丢弃错误路径的指令
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'b0;
            id_ex_pc4        <= 32'b0;
            id_ex_rdata1     <= 32'b0;
            id_ex_rdata2     <= 32'b0;
            id_ex_imm        <= 32'b0;
            id_ex_rs1        <= 5'd0;
            id_ex_rs2        <= 5'd0;
            id_ex_rd         <= 5'd0;
            id_ex_funct3     <= 3'b0;
            id_ex_alu_ctrl   <= 4'b0;
            id_ex_alu_src_sel  <= 1'b0;
            id_ex_alu_src1_sel <= 1'b0;
            id_ex_mem_we     <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_reg_we     <= 1'b0;
            id_ex_is_branch  <= 1'b0;
            id_ex_is_jal     <= 1'b0;
            id_ex_is_arith   <= 1'b0;
            id_ex_is_mul     <= 1'b0;
            id_ex_is_div     <= 1'b0;
            id_ex_div_signed <= 1'b0;
            id_ex_div_rem    <= 1'b0;
            id_ex_upd_flags  <= 1'b0;
            id_ex_is_rdflags <= 1'b0;
            id_ex_is_clrflags<= 1'b0;
        end
        else if (ex_stall) begin
            // 多周期除法进行中：ID/EX 保持不动（除法指令的控制信息/操作数必须留着）
        end
        else if (load_use) begin
            // stall：ID/EX 注入气泡，控制信号全部清零
            id_ex_valid      <= 1'b0;
            id_ex_mem_we     <= 1'b0;
            id_ex_reg_we     <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_is_branch  <= 1'b0;
            id_ex_is_jal     <= 1'b0;
            id_ex_is_arith   <= 1'b0;
            id_ex_is_mul     <= 1'b0;
            id_ex_is_div     <= 1'b0;
            id_ex_upd_flags  <= 1'b0;
            id_ex_is_rdflags <= 1'b0;
            id_ex_is_clrflags<= 1'b0;
        end
        else begin
            id_ex_valid      <= if_id_valid;
            id_ex_pc         <= if_id_pc;
            id_ex_pc4        <= if_id_pc + 32'd4;
            id_ex_rdata1     <= rdata1;
            id_ex_rdata2     <= rdata2;
            id_ex_imm        <= imm_out;
            id_ex_rs1        <= rs1_id;
            id_ex_rs2        <= rs2_id;
            id_ex_rd         <= rd_id;
            id_ex_funct3     <= funct3;
            id_ex_alu_ctrl   <= alu_ctrl_id;
            id_ex_alu_src_sel  <= alu_src_sel_id;
            id_ex_alu_src1_sel <= alu_src1_sel_id;
            id_ex_mem_we     <= mem_we_id;
            id_ex_mem_to_reg <= mem_to_reg_id;
            id_ex_reg_we     <= reg_we_id;
            id_ex_is_branch  <= is_branch_id;
            id_ex_is_jal     <= is_jal_id;
            id_ex_is_arith   <= is_arith_id;
            id_ex_is_mul     <= is_mul_id;
            id_ex_is_div     <= is_div_id;
            id_ex_div_signed <= is_div_signed_id;
            id_ex_div_rem    <= is_div_rem_id;
            id_ex_upd_flags  <= upd_flags_id;
            id_ex_is_rdflags <= is_rdflags_id;
            id_ex_is_clrflags<= is_clrflags_id;
        end
    end


    // ===================== EX =====================
    // ---------- EX/MEM（用于前递判断）----------
    reg        ex_mem_valid;        // EX/MEM 有效指令标志（在 EX/MEM 寄存器段赋值）
    wire [31:0] ex_mem_alu_result;
    wire [4:0]  ex_mem_rd;
    wire        ex_mem_reg_we;

    // ---------- MEM/WB（用于前递判断）----------
    reg        mem_wb_valid;        // MEM/WB 有效指令标志（在 MEM/WB 寄存器段赋值）
    wire [31:0] mem_wb_wdata;
    wire [4:0]  mem_wb_rd;
    wire        mem_wb_reg_we;

    // Forwarding Unit：EX/MEM 优先，其次 MEM/WB
    reg [1:0] fwd_a_sel; // 0: id_ex_rdata1, 1: EX/MEM, 2: MEM/WB
    reg [1:0] fwd_b_sel; // 0: id_ex_rdata2, 1: EX/MEM, 2: MEM/WB

    always @(*) begin
        if (ex_mem_valid && ex_mem_reg_we && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1))
            fwd_a_sel = 2'd1;
        else if (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1))
            fwd_a_sel = 2'd2;
        else
            fwd_a_sel = 2'd0;
    end

    always @(*) begin
        if (ex_mem_valid && ex_mem_reg_we && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            fwd_b_sel = 2'd1;
        else if (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2))
            fwd_b_sel = 2'd2;
        else
            fwd_b_sel = 2'd0;
    end

    wire [31:0] fwd_a = (fwd_a_sel == 2'd1) ? ex_mem_alu_result :
                        (fwd_a_sel == 2'd2) ? mem_wb_wdata : id_ex_rdata1;
    wire [31:0] fwd_b = (fwd_b_sel == 2'd1) ? ex_mem_alu_result :
                        (fwd_b_sel == 2'd2) ? mem_wb_wdata : id_ex_rdata2;

    // ALU 源操作数选择
    wire [31:0] alu_src1 = id_ex_alu_src1_sel ? id_ex_pc : fwd_a;
    wire [31:0] alu_src2 = id_ex_alu_src_sel ? id_ex_imm : fwd_b;

    wire [31:0] alu_result;
    wire        alu_zero, alu_sign, alu_carry, alu_parity, alu_overflow;
    ALU alu_inst (
        .src1(alu_src1),
        .src2(alu_src2),
        .alu_ctrl(id_ex_alu_ctrl),
        .result(alu_result),
        .zero(alu_zero),
        .sign(alu_sign),
        .carry(alu_carry),
        .parity(alu_parity),
        .overflow(alu_overflow)
    );

    // ---------- 多周期除法/取余单元（DivUnit，算法迁移自 Lab1 mult_alu.v）----------
    // 操作数直接用前递后的 src1/src2；DivUnit 在 start 那一拍把它们锁存下来，
    // 所以后续停顿期间前递选择变化（EX/MEM 被注气泡）也不会影响计算。
    DivUnit u_div (
        .clk       (clk),
        .rst       (rst),
        .start     (div_start),
        .is_signed (id_ex_div_signed),
        .dividend  (alu_src1),      // 被除数 = fwd_a
        .divisor   (alu_src2),      // 除数   = fwd_b
        .busy      (div_busy),
        .done      (div_done_w),
        .div_of    (div_of),
        .quot      (div_quot),
        .rem       (div_rem)
    );

    // ---------- 状态标志寄存器（迁移 Lab1 的"标志位寄存"处理方式）----------
    wire [7:0]  flags_reg;
    wire [31:0] of_count_reg;

    // ---------- EX 级结果 / 标志选择 ----------
    // 除法结果、rdflags 读出的标志字都要走 EX/MEM 写回通路
    wire [31:0] div_result  = id_ex_div_rem ? div_rem : div_quot;
    wire [31:0] flags_rdata = {24'd0, flags_reg};
    wire [31:0] ex_result   = id_ex_is_div     ? div_result  :
                              id_ex_is_rdflags ? flags_rdata :
                                                 alu_result;
    // 标志位：非除法指令取 ALU 输出；除法/取余用商或余数重算 SF/ZF/PF，OF 取 DivUnit
    wire        ex_sign   = id_ex_is_div ? div_result[31]        : alu_sign;
    wire        ex_zero   = id_ex_is_div ? (div_result == 32'd0) : alu_zero;
    wire        ex_carry  = id_ex_is_div ? 1'b0                  : alu_carry;
    wire        ex_parity = id_ex_is_div ? ~^div_result          : alu_parity;
    wire        ex_of     = id_ex_is_div ? div_of                : alu_overflow;

    // en ：本拍有一条算术类指令在 EX 级正常退役（多周期除法只在收尾拍 done 时算一次）
    // clr：clrflags 指令
    wire ex_flags_en  = id_ex_valid && !ex_stall && id_ex_upd_flags;
    wire ex_flags_clr = id_ex_valid && !ex_stall && id_ex_is_clrflags;

    FlagReg flag_reg_inst (
        .clk (clk),
        .rst (rst),
        .en  (ex_flags_en),
        .clr (ex_flags_clr),
        .sf  (ex_sign),
        .zf  (ex_zero),
        .cf  (ex_carry),
        .ovf (ex_of),
        .pf  (ex_parity),
        .flags    (flags_reg),
        .of_count (of_count_reg)
    );

    assign flags_o    = flags_reg;
    assign of_count_o = of_count_reg;

    // 分支目标地址 = 指令自身 PC + 立即数（在 EX 级计算）
    assign branch_target_ex = id_ex_pc + id_ex_imm;

    // 分支判定在 EX 级。
    // ★ 注意：这里**不再复用 ALU 的 zero 输出**。ALU 里新增了 64 位乘法器之后，
    //   "前递 → 乘法器 → result → zero → 分支 → PC" 会串成一条超长组合路径
    //   （实测 WNS = -0.009ns，见 scripts/impl_timing.rpt）。
    //   改用一条独立的比较器：beq/bne 比相等，blt/bge 比有符号大小，
    //   语义与原来完全一致（原来 ALU 对分支做的就是 SUB / SLT）。
    wire br_eq = (fwd_a == fwd_b);
    wire br_lt = ($signed(fwd_a) < $signed(fwd_b));
    wire branch_cond = (id_ex_funct3 == 3'b000 &&  br_eq) ||
                       (id_ex_funct3 == 3'b001 && !br_eq) ||
                       (id_ex_funct3 == 3'b100 &&  br_lt) ||
                       (id_ex_funct3 == 3'b101 && !br_lt);
    assign branch_taken_ex = id_ex_valid && (id_ex_is_jal || (id_ex_is_branch && branch_cond));
    assign flush = branch_taken_ex;

    // 溢出检测：对有效算术类指令(ADD/SUB/ADDI/MUL/DIV/REM)生效，并寄存器化到 EX/MEM 便于观察
    // 注意：!ex_stall —— 多周期除法停顿期间 ALU 的无关组合结果不能当作溢出
    wire overflow_ex_next = id_ex_valid && !ex_stall && id_ex_upd_flags && ex_of;

    // ---------- EX/MEM 流水线寄存器 ----------
    reg [31:0] ex_mem_alu_result_r;
    reg [31:0] ex_mem_wdata;      // SW 的存储数据（已前递）
    reg [31:0] ex_mem_pc4;
    reg [4:0]  ex_mem_rd_r;
    reg        ex_mem_mem_we;
    reg        ex_mem_mem_to_reg;
    reg        ex_mem_reg_we_r;
    reg        ex_mem_is_jal;
    reg        ex_mem_overflow;   // 溢出状态（保持到 EX/MEM 供波形观察）

    always @(posedge clk) begin
        if (rst) begin
            ex_mem_valid       <= 1'b0;
            ex_mem_alu_result_r <= 32'b0;
            ex_mem_wdata       <= 32'b0;
            ex_mem_pc4         <= 32'b0;
            ex_mem_rd_r        <= 5'd0;
            ex_mem_mem_we      <= 1'b0;
            ex_mem_mem_to_reg  <= 1'b0;
            ex_mem_reg_we_r    <= 1'b0;
            ex_mem_is_jal      <= 1'b0;
            ex_mem_overflow    <= 1'b0;
        end
        else if (ex_stall) begin
            // 多周期除法进行中：EX/MEM 注入气泡（除法指令还没算完，不能进 MEM/WB）
            ex_mem_valid       <= 1'b0;
            ex_mem_mem_we      <= 1'b0;
            ex_mem_mem_to_reg  <= 1'b0;
            ex_mem_reg_we_r    <= 1'b0;
            ex_mem_is_jal      <= 1'b0;
            ex_mem_overflow    <= 1'b0;
        end
        else begin
            ex_mem_valid       <= id_ex_valid;
            ex_mem_alu_result_r <= ex_result;   // 含除法结果 / rdflags 标志字
            ex_mem_wdata       <= fwd_b;          // 存储数据走前递
            ex_mem_pc4         <= id_ex_pc4;
            ex_mem_rd_r        <= id_ex_rd;
            ex_mem_mem_we      <= id_ex_mem_we;
            ex_mem_mem_to_reg  <= id_ex_mem_to_reg;
            ex_mem_reg_we_r    <= id_ex_reg_we;
            ex_mem_is_jal      <= id_ex_is_jal;
            ex_mem_overflow    <= overflow_ex_next;
        end
    end

    assign ex_mem_alu_result = ex_mem_alu_result_r;
    assign ex_mem_rd         = ex_mem_rd_r;
    assign ex_mem_reg_we     = ex_mem_reg_we_r;

    // ===================== MEM =====================
    // MMIO 窗口：0x1000_0000 ~ 0x1000_FFFF（低于 DMEM 基址 0x1001_0000，与 RAM 不冲突）
    wire memio_hit = (ex_mem_alu_result_r[31:16] == 16'h1000);

    wire [31:0] ram_rdata;
    wire [31:0] mem_rdata;
    DataMemory #(.DATA_FILE(DATA_FILE)) dm_inst (
        .clk(clk),
        .mem_we(ex_mem_mem_we),
        .addr(ex_mem_alu_result_r),
        .wdata(ex_mem_wdata),
        .rdata(ram_rdata)
    );

    // LW/SW 命中外设窗口时读写全部交给外设：
    // DataMemory 的 DATA_BASE=0x10010000，对窗口地址自动判为越界，不会误写 RAM。
    assign mem_rdata   = memio_hit ? memio_rdata : ram_rdata;
    assign memio_read  = ex_mem_mem_to_reg && memio_hit;
    assign memio_write = ex_mem_mem_we    && memio_hit;
    assign memio_addr  = ex_mem_alu_result_r;
    assign memio_wdata = ex_mem_wdata;

    // ---------- MEM/WB 流水线寄存器 ----------
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_mem_rdata;
    reg [31:0] mem_wb_pc4;
    reg [4:0]  mem_wb_rd_r;
    reg        mem_wb_mem_to_reg;
    reg        mem_wb_reg_we_r;
    reg        mem_wb_is_jal;

    always @(posedge clk) begin
        if (rst) begin
            mem_wb_valid     <= 1'b0;
            mem_wb_alu_result <= 32'b0;
            mem_wb_mem_rdata <= 32'b0;
            mem_wb_pc4       <= 32'b0;
            mem_wb_rd_r      <= 5'd0;
            mem_wb_mem_to_reg <= 1'b0;
            mem_wb_reg_we_r  <= 1'b0;
            mem_wb_is_jal    <= 1'b0;
        end
        else begin
            mem_wb_valid     <= ex_mem_valid;
            mem_wb_alu_result <= ex_mem_alu_result_r;
            mem_wb_mem_rdata <= mem_rdata;
            mem_wb_pc4       <= ex_mem_pc4;
            mem_wb_rd_r      <= ex_mem_rd_r;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_reg_we_r  <= ex_mem_reg_we_r;
            mem_wb_is_jal    <= ex_mem_is_jal;
        end
    end

    // ===================== WB =====================
    assign mem_wb_reg_we = mem_wb_reg_we_r;
    assign mem_wb_rd     = mem_wb_rd_r;
    assign mem_wb_wdata  = mem_wb_is_jal   ? mem_wb_pc4 :
                           mem_wb_mem_to_reg ? mem_wb_mem_rdata :
                                               mem_wb_alu_result;

    assign wb_reg_we = mem_wb_reg_we;
    assign wb_rd     = mem_wb_rd;
    assign wb_data   = mem_wb_wdata;

    // 供测试平台 / 波形观察的信号
    assign wb_valid    = mem_wb_valid;   // WB 级是否有有效指令（retired 计数用）
    assign overflow_ex = ex_mem_overflow;// 算术溢出状态（EX/MEM 级）

endmodule
