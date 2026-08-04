`timescale 1ns / 1ps

// 32 general-purpose registers, combinational read, x0 hardwired to zero.


module register_file (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reg_write,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    reg [31:0] registers [0:31];
    integer i;

    // Write-port bypass: WB commits this cycle, ID must observe it this cycle.
    wire rs1_bypass = reg_write && (rd_addr != 5'd0) && (rd_addr == rs1_addr);
    wire rs2_bypass = reg_write && (rd_addr != 5'd0) && (rd_addr == rs2_addr);

    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0   :
                      rs1_bypass         ? rd_data :
                                           registers[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0   :
                      rs2_bypass         ? rd_data :
                                           registers[rs2_addr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (reg_write && (rd_addr != 5'd0)) begin
            registers[rd_addr] <= rd_data;
        end
    end
endmodule
