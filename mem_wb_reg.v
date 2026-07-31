`timescale 1ns / 1ps

// MEM/WB pipeline register.
//
// Holds the three writeback-mux candidates (alu_result, mem_read_data,
// pc_plus_4), the destination register, and the WB control bits. stall and
// flush are tied off at the top level; kept for a uniform interface.

module mem_wb_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire [31:0] in_alu_result,
    input  wire [31:0] in_mem_read_data,
    input  wire [31:0] in_pc_plus_4,
    input  wire [4:0]  in_rd_addr,
    input  wire        in_reg_write,
    input  wire [1:0]  in_wb_src,

    output reg  [31:0] out_alu_result,
    output reg  [31:0] out_mem_read_data,
    output reg  [31:0] out_pc_plus_4,
    output reg  [4:0]  out_rd_addr,
    output reg         out_reg_write,
    output reg  [1:0]  out_wb_src
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_alu_result    <= 32'd0;
            out_mem_read_data <= 32'd0;
            out_pc_plus_4     <= 32'd0;
            out_rd_addr       <= 5'd0;
            out_reg_write     <= 1'b0;
            out_wb_src        <= 2'd0;
        end
        else if (flush) begin
            out_alu_result    <= 32'd0;
            out_mem_read_data <= 32'd0;
            out_pc_plus_4     <= 32'd0;
            out_rd_addr       <= 5'd0;
            out_reg_write     <= 1'b0;
            out_wb_src        <= 2'd0;
        end
        else if (stall) begin
            // hold
        end
        else begin
            out_alu_result    <= in_alu_result;
            out_mem_read_data <= in_mem_read_data;
            out_pc_plus_4     <= in_pc_plus_4;
            out_rd_addr       <= in_rd_addr;
            out_reg_write     <= in_reg_write;
            out_wb_src        <= in_wb_src;
        end
    end
endmodule
