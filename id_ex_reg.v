`timescale 1ns / 1ps

// ID/EX pipeline register.
//
// Latches everything the ID stage produces that any later stage consumes.
// Priority: reset > flush > stall > advance. Reset and flush both clear to a
// bubble; stall holds. The stall port is tied off at the top level, but is
// kept for a uniform interface across the four pipeline registers.

module id_ex_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    // ----- datapath inputs (from ID stage) -----
    input  wire [31:0] in_pc,
    input  wire [31:0] in_pc_plus_4,
    input  wire [31:0] in_rs1_data,
    input  wire [31:0] in_rs2_data,
    input  wire [31:0] in_immediate,
    input  wire [4:0]  in_rs1_addr,
    input  wire [4:0]  in_rs2_addr,
    input  wire [4:0]  in_rd_addr,
    input  wire [3:0]  in_alu_ctrl,

    // ----- control inputs (from control_unit) -----
    input  wire        in_alu_src,
    input  wire        in_branch,
    input  wire        in_jump,
    input  wire        in_mem_read,
    input  wire        in_mem_write,
    input  wire        in_reg_write,
    input  wire [1:0]  in_wb_src,

    // ----- datapath outputs (to EX stage) -----
    output reg  [31:0] out_pc,
    output reg  [31:0] out_pc_plus_4,
    output reg  [31:0] out_rs1_data,
    output reg  [31:0] out_rs2_data,
    output reg  [31:0] out_immediate,
    output reg  [4:0]  out_rs1_addr,
    output reg  [4:0]  out_rs2_addr,
    output reg  [4:0]  out_rd_addr,
    output reg  [3:0]  out_alu_ctrl,

    // ----- control outputs (to EX/MEM/WB) -----
    output reg         out_alu_src,
    output reg         out_branch,
    output reg         out_jump,
    output reg         out_mem_read,
    output reg         out_mem_write,
    output reg         out_reg_write,
    output reg  [1:0]  out_wb_src
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pc         <= 32'd0;
            out_pc_plus_4  <= 32'd0;
            out_rs1_data   <= 32'd0;
            out_rs2_data   <= 32'd0;
            out_immediate  <= 32'd0;
            out_rs1_addr   <= 5'd0;
            out_rs2_addr   <= 5'd0;
            out_rd_addr    <= 5'd0;
            out_alu_ctrl   <= 4'd0;

            out_alu_src    <= 1'b0;
            out_branch     <= 1'b0;
            out_jump       <= 1'b0;
            out_mem_read   <= 1'b0;
            out_mem_write  <= 1'b0;
            out_reg_write  <= 1'b0;
            out_wb_src     <= 2'd0;
        end
        else if (flush) begin
            // Only the control bits strictly need clearing to make a bubble;
            // the datapath fields are cleared too for readable waveforms.
            out_pc         <= 32'd0;
            out_pc_plus_4  <= 32'd0;
            out_rs1_data   <= 32'd0;
            out_rs2_data   <= 32'd0;
            out_immediate  <= 32'd0;
            out_rs1_addr   <= 5'd0;
            out_rs2_addr   <= 5'd0;
            out_rd_addr    <= 5'd0;
            out_alu_ctrl   <= 4'd0;

            out_alu_src    <= 1'b0;
            out_branch     <= 1'b0;
            out_jump       <= 1'b0;
            out_mem_read   <= 1'b0;
            out_mem_write  <= 1'b0;
            out_reg_write  <= 1'b0;
            out_wb_src     <= 2'd0;
        end
        else if (stall) begin
            // Hold - omitted assignments in a clocked block retain their value.
        end
        else begin
            out_pc         <= in_pc;
            out_pc_plus_4  <= in_pc_plus_4;
            out_rs1_data   <= in_rs1_data;
            out_rs2_data   <= in_rs2_data;
            out_immediate  <= in_immediate;
            out_rs1_addr   <= in_rs1_addr;
            out_rs2_addr   <= in_rs2_addr;
            out_rd_addr    <= in_rd_addr;
            out_alu_ctrl   <= in_alu_ctrl;

            out_alu_src    <= in_alu_src;
            out_branch     <= in_branch;
            out_jump       <= in_jump;
            out_mem_read   <= in_mem_read;
            out_mem_write  <= in_mem_write;
            out_reg_write  <= in_reg_write;
            out_wb_src     <= in_wb_src;
        end
    end
endmodule
