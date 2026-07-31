`timescale 1ns / 1ps

// Resolves RAW data hazards by routing an in-flight result directly to the
// EX-stage ALU inputs, bypassing the register file.
//
//   2'b10 - forward from EX/MEM (most recent producer)
//   2'b01 - forward from MEM/WB (older producer)
//   2'b00 - no forward, use the register file value
//
// EX/MEM wins when both stages hold a write to the same register, since it
// carries the newer value. Each source is gated by reg_write && rd != 0, so a
// bubble (reg_write = 0) can never act as a forwarding source.

module forwarding_unit (
    input  wire [4:0] id_ex_rs1_addr,
    input  wire [4:0] id_ex_rs2_addr,

    input  wire [4:0] ex_mem_rd_addr,
    input  wire       ex_mem_reg_write,

    input  wire [4:0] mem_wb_rd_addr,
    input  wire       mem_wb_reg_write,

    output reg  [1:0] forward_a,   // for ALU operand A (rs1)
    output reg  [1:0] forward_b    // for ALU operand B (rs2)
);
    always @(*) begin
        // ----- operand A (rs1) -----
        if (ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) &&
            (ex_mem_rd_addr == id_ex_rs1_addr))
            forward_a = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) &&
                 (mem_wb_rd_addr == id_ex_rs1_addr))
            forward_a = 2'b01;
        else
            forward_a = 2'b00;

        // ----- operand B (rs2) -----
        if (ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) &&
            (ex_mem_rd_addr == id_ex_rs2_addr))
            forward_b = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) &&
                 (mem_wb_rd_addr == id_ex_rs2_addr))
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end
endmodule
