module riscv_top (
    input  wire clk,
    input  wire rst_n
);
    wire [31:0] pc_current, pc_next, pc_plus_4;
    wire [31:0] instruction;
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] reg_write_data;
    wire [31:0] immediate;
    wire [31:0] alu_operand_b;
    wire [31:0] alu_result;
    wire        zero_flag;
    wire [3:0]  alu_ctrl;
    wire [31:0] mem_read_data;
    wire        branch, jump;
    wire        reg_write, alu_src;
    wire [1:0]  alu_op;
    wire        mem_write, mem_read;
    wire [1:0]  wb_src;
    wire [31:0] pc_plus_imm;
    wire        pc_src_branch;
    wire        pc_src_jump;
    wire        pc_src_jalr;

    assign pc_plus_4   = pc_current + 32'd4;
    assign pc_plus_imm = pc_current + immediate;

    assign pc_src_branch = branch & zero_flag;
    assign pc_src_jump   = jump;
    assign pc_src_jalr   = jump & alu_src;

    assign pc_next = pc_src_jalr                  ? (alu_result & ~32'd1) :
                     (pc_src_jump | pc_src_branch) ? pc_plus_imm :
                                                    pc_plus_4;

    program_counter pc_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .pc_next    (pc_next),
        .pc_current (pc_current)
    );

    instruction_memory imem (
        .addr        (pc_current),
        .instruction (instruction)
    );

    register_file regfile (
        .clk       (clk),
        .rst_n     (rst_n),
        .reg_write (reg_write),
        .rs1_addr  (instruction[19:15]),
        .rs2_addr  (instruction[24:20]),
        .rd_addr   (instruction[11:7]),
        .rd_data   (reg_write_data),
        .rs1_data  (rs1_data),
        .rs2_data  (rs2_data)
    );

    immediate_generator imm_gen (
        .instruction (instruction),
        .immediate   (immediate)
    );

    control_unit ctrl (
        .opcode    (instruction[6:0]),
        .branch    (branch),
        .jump      (jump),
        .reg_write (reg_write),
        .alu_src   (alu_src),
        .alu_op    (alu_op),
        .mem_write (mem_write),
        .mem_read  (mem_read),
        .wb_src    (wb_src)
    );

    alu_control alu_ctrl_inst (
        .alu_op   (alu_op),
        .funct3   (instruction[14:12]),
        .funct7   (instruction[31:25]),
        .alu_ctrl (alu_ctrl)
    );

    assign alu_operand_b = alu_src ? immediate : rs2_data;

    alu alu_inst (
        .operand_a  (rs1_data),
        .operand_b  (alu_operand_b),
        .alu_ctrl   (alu_ctrl),
        .alu_result (alu_result),
        .zero_flag  (zero_flag)
    );

    data_memory dmem (
        .clk        (clk),
        .rst_n      (rst_n),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .addr       (alu_result),
        .write_data (rs2_data),
        .read_data  (mem_read_data)
    );

    assign reg_write_data = (wb_src == 2'b00) ? alu_result    :
                            (wb_src == 2'b01) ? mem_read_data :
                            (wb_src == 2'b10) ? pc_plus_4     :
                                                32'd0;
endmodule
