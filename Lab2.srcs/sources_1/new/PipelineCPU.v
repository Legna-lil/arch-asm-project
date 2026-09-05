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
    output wire [31:0] memio_wdata   // SW 写数据（已前递）
    );

    localparam NOP = 32'h00000013; // addi x0, x0, 0

    // ===================== IF =====================
    wire [31:0] pc_curr;
    wire [31:0] instr_if;

    wire        stall;
    wire        flush;
    wire        branch_taken_ex;
    wire [31:0] branch_target_ex;

    // 分支发生时下一条 PC 为分支目标，否则 PC+4；stall 时保持
    wire [31:0] pc_next = branch_taken_ex ? branch_target_ex : (pc_curr + 32'd4);

    PC pc_inst (
        .clk(clk),
        .rst(rst),
        .en(!stall || flush), // stall 时 PC 保持；但分支跳转(flush)优先级更高
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
        else if (!stall) begin         // 正常推进；stall 时保持
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
        .is_arith(is_arith_id)
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

    // load-use 冒险：ID/EX 中是有效 lw，且 ID 级指令需要其结果
    wire load_use = id_ex_valid && id_ex_mem_to_reg && (id_ex_rd != 5'd0) &&
                    ( (id_ex_rd == rs1_id && rs1_used) ||
                      (id_ex_rd == rs2_id && rs2_used) );

    assign stall = load_use;

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
    wire        alu_zero;
    wire        alu_overflow;
    ALU alu_inst (
        .src1(alu_src1),
        .src2(alu_src2),
        .alu_ctrl(id_ex_alu_ctrl),
        .result(alu_result),
        .zero(alu_zero),
        .overflow(alu_overflow)
    );

    // 分支目标地址 = 指令自身 PC + 立即数（在 EX 级计算）
    assign branch_target_ex = id_ex_pc + id_ex_imm;

    // 分支判定在 EX 级：分支比较复用 ALU 的 SLT/SUB 结果
    // beq(f3=000): zero ; bne(f3=001): !zero ; blt(f3=100): !zero ; bge(f3=101): zero
    wire branch_cond = (id_ex_funct3 == 3'b000 && alu_zero) ||
                       (id_ex_funct3 == 3'b001 && !alu_zero) ||
                       (id_ex_funct3 == 3'b100 && !alu_zero) ||
                       (id_ex_funct3 == 3'b101 && alu_zero);
    assign branch_taken_ex = id_ex_valid && (id_ex_is_jal || (id_ex_is_branch && branch_cond));
    assign flush = branch_taken_ex;

    // 溢出检测：仅对有效算术指令(ADD/SUB/ADDI)生效，并寄存器化到 EX/MEM 便于观察
    wire overflow_ex_next = id_ex_valid && id_ex_is_arith && alu_overflow;

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
        else begin
            ex_mem_valid       <= id_ex_valid;
            ex_mem_alu_result_r <= alu_result;
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
