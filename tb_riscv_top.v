`timescale 1ns/1ps

module tb_riscv_top;
    reg clk;
    reg rst_n;

    riscv_top dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // 10ns clock period (100 MHz)
    always #5 clk = ~clk;

    // Per-cycle trace
    integer cycle;
    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            $display("[cyc %0d] PC=0x%08h  instr=0x%08h  x1=%0d x2=%0d x3=%0d x5=%0d  mem[0]=%0d",
                     cycle,
                     dut.pc_current,
                     dut.instruction,
                     dut.regfile.registers[1],
                     dut.regfile.registers[2],
                     dut.regfile.registers[3],
                     dut.regfile.registers[5],
                     dut.dmem.mem[0]);
        end
    end

    initial begin
        clk = 0;
        rst_n = 0;
        cycle = 0;
        #20 rst_n = 1;

        // Run for plenty of cycles
        #500;

        // Check the result
        $display("");
        $display("==========================================");
        if (dut.dmem.mem[0] == 32'd5) begin
            $display("PASS: mem[0] = %0d (expected 5 = fib(5))", dut.dmem.mem[0]);
        end else begin
            $display("FAIL: mem[0] = %0d (expected 5)", dut.dmem.mem[0]);
        end
        $display("==========================================");
        $finish;
    end
endmodule
