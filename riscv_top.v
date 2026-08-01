`timescale 1ns / 1ps

// Five-stage pipelined RV32I core.
//
// Stages: IF -> ID -> EX -> MEM -> WB, separated by four pipeline registers.
// Hazard handling:
//   - forwarding_unit       : RAW data hazards  -> bypass to the EX ALU inputs
//   - hazard_detection_unit : load-use          -> 1-cycle stall
//   - branch resolved in EX : taken branch/jump -> flush IF/ID and ID/EX
//
// Conventions: active-low async reset, rising-edge synchronous state,
// combinational memory and register reads, two-level ALU decode, x0 hardwired,
// 2-bit writeback mux, and PCSrc computed rather than emitted by control.

module riscv_top #(
    parameter PROGRAM = "program.hex"     // instruction image, selectable per testbench
)(
    input  wire clk,
    input  wire rst_n
);
    // ============================================================
    // Hazard control signals (drive stall/flush on pipeline regs)
    // ============================================================
    wire stall;            // load-use: freeze PC + IF/ID, bubble ID/EX
    wire take_branch;      // taken branch/jump resolved in EX
    wire if_id_flush = take_branch;
    wire id_ex_flush = take_branch | stall;

    // ============================================================
    // IF - Instruction Fetch
    // ============================================================
    wire [31:0] pc_current;
    wire [31:0] pc_plus_4_if = pc_current + 32'd4;
    wire [31:0] instruction;
    wire [31:0] ex_pc_target;         // branch/jump target computed in EX

    wire [31:0] pc_next = take_branch ? ex_pc_target :
                          stall       ? pc_current   :
                                        pc_plus_4_if;

    program_counter pc_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .pc_next    (pc_next),
        .pc_current (pc_current)
    );

    instruction_memory #(.PROGRAM (PROGRAM)) imem (
        .addr        (pc_current),
        .instruction (instruction)
    );

    // ---------- IF/ID ----------
    wire [31:0] id_pc, id_instruction;

    if_id_reg if_id (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (stall),
        .flush           (if_id_flush),
        .in_pc           (pc_current),
        .in_instruction  (instruction),
        .out_pc          (id_pc),
        .out_instruction (id_instruction)
    );

    // ============================================================
    // ID - Instruction Decode
    // ============================================================
    wire [4:0] id_rs1_addr = id_instruction[19:15];
    wire [4:0] id_rs2_addr = id_instruction[24:20];
    wire [4:0] id_rd_addr  = id_instruction[11:7];

    wire [31:0] id_rs1_data, id_rs2_data;
    wire [31:0] id_immediate;
    wire [3:0]  id_alu_ctrl;
    wire        id_branch, id_jump, id_reg_write, id_alu_src;
    wire [1:0]  id_alu_op;
    wire        id_mem_write, id_mem_read;
    wire [1:0]  id_wb_src;

    wire [31:0] id_pc_plus_4 = id_pc + 32'd4;   // link value for jal/jalr

    // WB-stage writeback signals (declared here; driven in WB section)
    wire        wb_reg_write;
    wire [4:0]  wb_rd_addr;
    wire [31:0] wb_write_data;

    register_file regfile (
        .clk       (clk),
        .rst_n     (rst_n),
        .reg_write (wb_reg_write),
        .rs1_addr  (id_rs1_addr),
        .rs2_addr  (id_rs2_addr),
        .rd_addr   (wb_rd_addr),
        .rd_data   (wb_write_data),
        .rs1_data  (id_rs1_data),
        .rs2_data  (id_rs2_data)
    );

    immediate_generator imm_gen (
        .instruction (id_instruction),
        .immediate   (id_immediate)
    );

    control_unit ctrl (
        .opcode    (id_instruction[6:0]),
        .branch    (id_branch),
        .jump      (id_jump),
        .reg_write (id_reg_write),
        .alu_src   (id_alu_src),
        .alu_op    (id_alu_op),
        .mem_write (id_mem_write),
        .mem_read  (id_mem_read),
        .wb_src    (id_wb_src)
    );

    alu_control alu_ctrl_inst (
        .alu_op   (id_alu_op),
        .funct3   (id_instruction[14:12]),
        .funct7   (id_instruction[31:25]),
        .alu_ctrl (id_alu_ctrl)
    );

    // ---------- ID/EX ----------
    wire [31:0] ex_pc, ex_pc_plus_4, ex_rs1_data, ex_rs2_data, ex_immediate;
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [3:0]  ex_alu_ctrl;
    wire        ex_alu_src, ex_branch, ex_jump, ex_mem_read, ex_mem_write, ex_reg_write;
    wire [1:0]  ex_wb_src;

    id_ex_reg id_ex (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (1'b0),          // ID/EX never stalls; tied off
        .flush        (id_ex_flush),

        .in_pc        (id_pc),
        .in_pc_plus_4 (id_pc_plus_4),
        .in_rs1_data  (id_rs1_data),
        .in_rs2_data  (id_rs2_data),
        .in_immediate (id_immediate),
        .in_rs1_addr  (id_rs1_addr),
        .in_rs2_addr  (id_rs2_addr),
        .in_rd_addr   (id_rd_addr),
        .in_alu_ctrl  (id_alu_ctrl),
        .in_alu_src   (id_alu_src),
        .in_branch    (id_branch),
        .in_jump      (id_jump),
        .in_mem_read  (id_mem_read),
        .in_mem_write (id_mem_write),
        .in_reg_write (id_reg_write),
        .in_wb_src    (id_wb_src),

        .out_pc        (ex_pc),
        .out_pc_plus_4 (ex_pc_plus_4),
        .out_rs1_data  (ex_rs1_data),
        .out_rs2_data  (ex_rs2_data),
        .out_immediate (ex_immediate),
        .out_rs1_addr  (ex_rs1_addr),
        .out_rs2_addr  (ex_rs2_addr),
        .out_rd_addr   (ex_rd_addr),
        .out_alu_ctrl  (ex_alu_ctrl),
        .out_alu_src   (ex_alu_src),
        .out_branch    (ex_branch),
        .out_jump      (ex_jump),
        .out_mem_read  (ex_mem_read),
        .out_mem_write (ex_mem_write),
        .out_reg_write (ex_reg_write),
        .out_wb_src    (ex_wb_src)
    );

    // ============================================================
    // EX - Execute  (ALU, forwarding, branch resolution)
    // ============================================================
    wire [1:0] forward_a, forward_b;

    // EX/MEM and MEM/WB outputs needed by forwarding (declared below; used here)
    wire [31:0] mem_alu_result;
    wire [4:0]  mem_rd_addr;
    wire        mem_reg_write;

    forwarding_unit fwd (
        .id_ex_rs1_addr   (ex_rs1_addr),
        .id_ex_rs2_addr   (ex_rs2_addr),
        .ex_mem_rd_addr   (mem_rd_addr),
        .ex_mem_reg_write (mem_reg_write),
        .mem_wb_rd_addr   (wb_rd_addr),
        .mem_wb_reg_write (wb_reg_write),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    // Forward muxes: 10 = from EX/MEM, 01 = from MEM/WB, 00 = register file
    wire [31:0] fwd_rs1 = (forward_a == 2'b10) ? mem_alu_result :
                          (forward_a == 2'b01) ? wb_write_data  :
                                                 ex_rs1_data;

    wire [31:0] fwd_rs2 = (forward_b == 2'b10) ? mem_alu_result :
                          (forward_b == 2'b01) ? wb_write_data  :
                                                 ex_rs2_data;

    wire [31:0] alu_operand_a = fwd_rs1;
    wire [31:0] alu_operand_b = ex_alu_src ? ex_immediate : fwd_rs2;

    wire [31:0] alu_result;
    wire        zero_flag;

    alu alu_inst (
        .operand_a  (alu_operand_a),
        .operand_b  (alu_operand_b),
        .alu_ctrl   (ex_alu_ctrl),
        .alu_result (alu_result),
        .zero_flag  (zero_flag)
    );

    // Branch / jump resolution
    wire [31:0] branch_target = ex_pc + ex_immediate;
    wire        pc_src_jalr   = ex_jump & ex_alu_src;       // jalr is the only jump with alu_src
    assign      ex_pc_target  = pc_src_jalr ? (alu_result & ~32'd1) : branch_target;
    assign      take_branch   = (ex_branch & zero_flag) | ex_jump;

    // ---------- EX/MEM ----------
    wire [31:0] mem_pc_plus_4, mem_rs2_data;
    wire        mem_mem_read, mem_mem_write;
    wire [1:0]  mem_wb_src;

    ex_mem_reg ex_mem (
        .clk           (clk),
        .rst_n         (rst_n),
        .stall         (1'b0),
        .flush         (1'b0),

        .in_pc_plus_4  (ex_pc_plus_4),
        .in_alu_result (alu_result),
        .in_rs2_data   (fwd_rs2),          // forwarded store data for sw
        .in_rd_addr    (ex_rd_addr),
        .in_mem_read   (ex_mem_read),
        .in_mem_write  (ex_mem_write),
        .in_reg_write  (ex_reg_write),
        .in_wb_src     (ex_wb_src),

        .out_pc_plus_4  (mem_pc_plus_4),
        .out_alu_result (mem_alu_result),
        .out_rs2_data   (mem_rs2_data),
        .out_rd_addr    (mem_rd_addr),
        .out_mem_read   (mem_mem_read),
        .out_mem_write  (mem_mem_write),
        .out_reg_write  (mem_reg_write),
        .out_wb_src     (mem_wb_src)
    );

    // ============================================================
    // MEM - Memory Access
    // ============================================================
    wire [31:0] mem_read_data;

    data_memory dmem (
        .clk        (clk),
        .rst_n      (rst_n),
        .mem_read   (mem_mem_read),
        .mem_write  (mem_mem_write),
        .addr       (mem_alu_result),
        .write_data (mem_rs2_data),
        .read_data  (mem_read_data)
    );

    // ---------- MEM/WB ----------
    wire [31:0] wb_alu_result, wb_mem_read_data, wb_pc_plus_4;
    wire [1:0]  wb_wb_src;

    mem_wb_reg mem_wb (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (1'b0),
        .flush            (1'b0),

        .in_alu_result    (mem_alu_result),
        .in_mem_read_data (mem_read_data),
        .in_pc_plus_4     (mem_pc_plus_4),
        .in_rd_addr       (mem_rd_addr),
        .in_reg_write     (mem_reg_write),
        .in_wb_src        (mem_wb_src),

        .out_alu_result    (wb_alu_result),
        .out_mem_read_data (wb_mem_read_data),
        .out_pc_plus_4     (wb_pc_plus_4),
        .out_rd_addr       (wb_rd_addr),
        .out_reg_write     (wb_reg_write),
        .out_wb_src        (wb_wb_src)
    );

    // ============================================================
    // WB - Write Back
    // ============================================================
    assign wb_write_data = (wb_wb_src == 2'b00) ? wb_alu_result    :
                           (wb_wb_src == 2'b01) ? wb_mem_read_data :
                           (wb_wb_src == 2'b10) ? wb_pc_plus_4     :
                                                  32'd0;

    // ============================================================
    // Hazard detection (load-use)  - reads ID/EX (load) + IF/ID (consumer)
    // ============================================================
    hazard_detection_unit hdu (
        .id_ex_mem_read (ex_mem_read),
        .id_ex_rd_addr  (ex_rd_addr),
        .if_id_rs1_addr (id_rs1_addr),
        .if_id_rs2_addr (id_rs2_addr),
        .stall          (stall)
    );
endmodule