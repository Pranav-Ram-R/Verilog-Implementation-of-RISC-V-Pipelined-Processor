`timescale 1ns / 1ps

// Sign-extends the I / S / B / J-type immediate fields to 32 bits.

module immediate_generator (
    input  wire [31:0] instruction,
    output reg  [31:0] immediate
);
    wire [6:0] opcode = instruction[6:0];

    localparam OP_ITYPE_ALU = 7'b0010011;
    localparam OP_LOAD      = 7'b0000011;
    localparam OP_JALR      = 7'b1100111;
    localparam OP_STORE     = 7'b0100011;
    localparam OP_BRANCH    = 7'b1100011;
    localparam OP_JAL       = 7'b1101111;

    always @(*) begin
        case (opcode)
            OP_ITYPE_ALU,
            OP_LOAD,
            OP_JALR: begin
                immediate = {{20{instruction[31]}}, instruction[31:20]};
            end
            OP_STORE: begin
                immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end
            OP_BRANCH: begin
                immediate = {{19{instruction[31]}},
                             instruction[31],
                             instruction[7],
                             instruction[30:25],
                             instruction[11:8],
                             1'b0};
            end
            OP_JAL: begin
                immediate = {{11{instruction[31]}},
                             instruction[31],
                             instruction[19:12],
                             instruction[20],
                             instruction[30:21],
                             1'b0};
            end
            default: immediate = 32'd0;
        endcase
    end
endmodule
