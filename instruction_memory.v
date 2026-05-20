module instruction_memory #(
    parameter MEM_DEPTH = 256
)(
    input  wire [31:0] addr,
    output wire [31:0] instruction
);
    reg [31:0] mem [0:MEM_DEPTH-1];

    assign instruction = mem[addr[31:2]];

    initial begin
        $readmemh("program.hex", mem);
    end
endmodule
