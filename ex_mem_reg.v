`timescale 1ns / 1ps

// EX/MEM pipeline register.
//
// Carries the ALU result (address for MEM, writeback value for WB), the store
// data, the link value, rd, and the MEM/WB control bits. stall and flush are
// tied off at the top level - an instruction that has reached EX/MEM is past
// the speculative window - but are kept for a uniform interface.

module ex_mem_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    // datapath
    input  wire [31:0] in_pc_plus_4,
    input  wire [31:0] in_alu_result,
    input  wire [31:0] in_rs2_data,
    input  wire [4:0]  in_rd_addr,
    // control
    input  wire        in_mem_read,
    input  wire        in_mem_write,
    input  wire        in_reg_write,
    input  wire [1:0]  in_wb_src,

    output reg  [31:0] out_pc_plus_4,
    output reg  [31:0] out_alu_result,
    output reg  [31:0] out_rs2_data,
    output reg  [4:0]  out_rd_addr,
    output reg         out_mem_read,
    output reg         out_mem_write,
    output reg         out_reg_write,
    output reg  [1:0]  out_wb_src
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pc_plus_4  <= 32'd0;
            out_alu_result <= 32'd0;
            out_rs2_data   <= 32'd0;
            out_rd_addr    <= 5'd0;
            out_mem_read   <= 1'b0;
            out_mem_write  <= 1'b0;
            out_reg_write  <= 1'b0;
            out_wb_src     <= 2'd0;
        end
        else if (flush) begin
            out_pc_plus_4  <= 32'd0;
            out_alu_result <= 32'd0;
            out_rs2_data   <= 32'd0;
            out_rd_addr    <= 5'd0;
            out_mem_read   <= 1'b0;
            out_mem_write  <= 1'b0;
            out_reg_write  <= 1'b0;
            out_wb_src     <= 2'd0;
        end
        else if (stall) begin
            // hold
        end
        else begin
            out_pc_plus_4  <= in_pc_plus_4;
            out_alu_result <= in_alu_result;
            out_rs2_data   <= in_rs2_data;
            out_rd_addr    <= in_rd_addr;
            out_mem_read   <= in_mem_read;
            out_mem_write  <= in_mem_write;
            out_reg_write  <= in_reg_write;
            out_wb_src     <= in_wb_src;
        end
    end
endmodule
