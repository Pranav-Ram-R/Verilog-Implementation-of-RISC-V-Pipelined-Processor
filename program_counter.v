module program_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc_current
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_current <= 32'h0000_0000;
        else
            pc_current <= pc_next;
    end
endmodule
