`timescale 1ns / 1ps

module instruction_memory #(
    parameter PROGRAM   = "program.hex",  // image loaded at elaboration
    parameter MEM_DEPTH = 256             // number of 32-bit words
)(
    input  wire [31:0] addr,
    output wire [31:0] instruction
);

    reg [31:0] mem [0:MEM_DEPTH-1];

    // Word-aligned access: drop the lower 2 bits
    assign instruction = mem[addr[31:2]];

    // Preload program at elaboration
    initial begin
        $readmemh(PROGRAM, mem);
    end

endmodule
