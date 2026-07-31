`timescale 1ns / 1ps

module alu_control (
    input  wire [1:0] alu_op,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg  [3:0] alu_ctrl
);

    // Match the encodings from the ALU module
    localparam ALU_ADD = 4'b0000;
    localparam ALU_SUB = 4'b0001;
    localparam ALU_AND = 4'b0010;
    localparam ALU_OR  = 4'b0011;
    localparam ALU_SLT = 4'b0100;
    localparam ALU_SRL = 4'b0101;

    always @(*) begin
        case (alu_op)
            2'b00: alu_ctrl = ALU_ADD;   // lw, sw, jalr - always add
            2'b01: alu_ctrl = ALU_SUB;   // beq - subtract for comparison
            2'b10: begin                 // R-type - funct7 selects add vs sub
                case (funct3)
                    3'b000: alu_ctrl = (funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD;
                    3'b111: alu_ctrl = ALU_AND;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b101: alu_ctrl = ALU_SRL;
                    default: alu_ctrl = 4'bXXXX;  // unsupported funct3 - fail loudly
                endcase
            end
            2'b11: begin                 // I-type ALU - instruction[31:25] is
                case (funct3)            // immediate data, NOT a funct7 field
                    3'b000: alu_ctrl = ALU_ADD;   // addi (no "subi" exists)
                    3'b111: alu_ctrl = ALU_AND;   // andi
                    3'b110: alu_ctrl = ALU_OR;    // ori
                    default: alu_ctrl = 4'bXXXX;  // unsupported funct3 - fail loudly
                endcase
            end
            default: alu_ctrl = 4'bXXXX;
        endcase
    end

endmodule
