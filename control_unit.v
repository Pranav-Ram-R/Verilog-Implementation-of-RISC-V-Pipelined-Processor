module control_unit (
    input  wire [6:0] opcode,
    output reg        branch,
    output reg        jump,
    output reg        reg_write,
    output reg        alu_src,
    output reg [1:0]  alu_op,
    output reg        mem_write,
    output reg        mem_read,
    output reg [1:0]  wb_src
);
    localparam OP_RTYPE  = 7'b0110011;
    localparam OP_ITYPE  = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;

    always @(*) begin
        branch    = 1'b0;
        jump      = 1'b0;
        reg_write = 1'b0;
        alu_src   = 1'b0;
        alu_op    = 2'b00;
        mem_write = 1'b0;
        mem_read  = 1'b0;
        wb_src    = 2'b00;

        case (opcode)
            OP_RTYPE: begin
                reg_write = 1'b1;
                alu_op    = 2'b10;
            end
            OP_ITYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b10;
            end
            OP_LOAD: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b00;
                mem_read  = 1'b1;
                wb_src    = 2'b01;
            end
            OP_STORE: begin
                alu_src   = 1'b1;
                alu_op    = 2'b00;
                mem_write = 1'b1;
            end
            OP_BRANCH: begin
                branch    = 1'b1;
                alu_op    = 2'b01;
            end
            OP_JAL: begin
                jump      = 1'b1;
                reg_write = 1'b1;
                wb_src    = 2'b10;
            end
            OP_JALR: begin
                jump      = 1'b1;
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b00;
                wb_src    = 2'b10;
            end
            default: ;
        endcase
    end
endmodule
