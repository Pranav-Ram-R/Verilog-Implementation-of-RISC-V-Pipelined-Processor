`timescale 1ns / 1ps

// 32 general-purpose registers, combinational read, x0 hardwired to zero.
//
// The read ports bypass the write port internally. In the 5-stage pipeline a
// producer in WB and a consumer in ID occupy the same cycle for a distance-3
// dependency, and there is no forwarding path back into ID, so the register
// file itself must deliver the value being written right now. When the write
// port targets a register being read, the incoming write data is returned
// instead of the stored value.
//
// The bypass is what makes a rising-edge write safe. Without it, the array
// update and the ID/EX register latching the read result land on the same
// clock edge, and the winner depends on delta-cycle ordering between a
// nonblocking array write and a combinational read - which Icarus and Vivado
// xsim resolve differently, giving different results from identical RTL. The
// bypassed value is combinationally valid for the whole cycle, so the edge is
// unambiguous.
//
// x0 outranks the bypass: writes to x0 are discarded, so a read of x0 must
// still return zero even while the write port is aimed at it.

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
