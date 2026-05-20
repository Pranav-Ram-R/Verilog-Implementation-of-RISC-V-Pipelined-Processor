module data_memory #(
    parameter MEM_DEPTH = 256
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output wire [31:0] read_data
);
    reg [31:0] mem [0:MEM_DEPTH-1];
    integer i;

    assign read_data = mem_read ? mem[addr[31:2]] : 32'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1)
                mem[i] <= 32'd0;
        end else if (mem_write) begin
            mem[addr[31:2]] <= write_data;
        end
    end
endmodule
