`timescale 1ns / 1ps

// 32 general-purpose registers, combinational read, x0 hardwired to zero.
//
// The write port is clocked on the FALLING edge. In the 5-stage pipeline a
// producer in WB and a consumer in ID can occupy the same cycle (a distance-3
// dependency). If the write committed on the same rising edge that the
// consumer's ID/EX register latched the read result, the outcome would depend
// on delta-cycle ordering between the combinational read and the pipeline
// register latch, which different simulators resolve differently. Committing
// on the falling edge places the write half a cycle earlier, so the value is
// already in the array before the next rising edge samples it. This is the
// standard "write in the first half of the cycle, read in the second half"
// register file, and it removes the race entirely.
//
// This is the only sequential element in the design that is not posedge-
// triggered; everything else follows the rising-edge convention.

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

    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : registers[rs2_addr];

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (reg_write && (rd_addr != 5'd0)) begin
            registers[rd_addr] <= rd_data;
        end
    end
endmodule
