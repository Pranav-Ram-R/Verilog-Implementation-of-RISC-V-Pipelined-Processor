`timescale 1ns / 1ps

// IF/ID pipeline register.
//
// The only pipeline register where both control inputs are driven by real
// signals: stall holds the dependent instruction during a load-use hazard,
// flush kills the speculative fetch behind a taken branch.
//
// Priority: reset > flush > stall > advance.

module if_id_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire [31:0] in_pc,
    input  wire [31:0] in_instruction,

    output reg  [31:0] out_pc,
    output reg  [31:0] out_instruction
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pc          <= 32'd0;
            out_instruction <= 32'd0;
        end
        else if (flush) begin
            out_pc          <= 32'd0;
            out_instruction <= 32'd0;   // opcode 0 decodes to all controls off
        end
        else if (stall) begin
            // Hold - re-present the same instruction next cycle.
        end
        else begin
            out_pc          <= in_pc;
            out_instruction <= in_instruction;
        end
    end
endmodule
