`timescale 1ns/1ps

// Directed test for the load-use interlock in hazard_detection_unit.
//
//   addi x1, x0, 7
//   sw   x1, 0(x0)      # mem[0] = 7   (store data forwarded from EX/MEM)
//   addi x2, x0, 20
//   lw   x3, 0(x0)      # x3 = 7
//   add  x4, x3, x2     # consumes x3 one cycle early -> stall
//   sw   x4, 4(x0)      # mem[1] = 27
//
// The add sits directly behind the load and needs x3 at the start of its EX,
// one cycle before the load produces it in MEM. Forwarding cannot fix that, so
// the hazard detection unit must freeze the PC and IF/ID and bubble ID/EX for
// exactly one cycle.
//
// Without the stall the add would read a stale x3 = 0 and store 20, so
// mem[1] == 27 is what proves the interlock fired - and the stall counter
// confirms it fired exactly once rather than hanging.

module tb_loaduse;
    reg clk   = 0;
    reg rst_n = 0;

    riscv_top #(.PROGRAM ("program_loaduse.hex")) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // 10ns clock period (100 MHz)
    always #5 clk = ~clk;

    integer cycle;
    integer stall_count;

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (dut.stall) stall_count = stall_count + 1;
            $display("[cyc %0d] PC=0x%08h  instr=0x%08h  stall=%b  x3=%0d x4=%0d  mem[0]=%0d mem[1]=%0d",
                     cycle,
                     dut.pc_current,
                     dut.instruction,
                     dut.stall,
                     dut.regfile.registers[3],
                     dut.regfile.registers[4],
                     dut.dmem.mem[0],
                     dut.dmem.mem[1]);
        end
    end

    initial begin
        cycle       = 0;
        stall_count = 0;
        #20 rst_n = 1;

        #300;

        $display("");
        $display("==========================================");
        if (dut.dmem.mem[1] !== 32'd27)
            $display("FAIL: mem[1] = %0d (expected 27 = 7 + 20)", dut.dmem.mem[1]);
        else if (stall_count !== 1)
            $display("FAIL: mem[1] correct but stall asserted %0d cycles (expected 1)",
                     stall_count);
        else
            $display("PASS: mem[1] = %0d (expected 27), load-use stall asserted for %0d cycle",
                     dut.dmem.mem[1], stall_count);
        $display("==========================================");
        $finish;
    end
endmodule
