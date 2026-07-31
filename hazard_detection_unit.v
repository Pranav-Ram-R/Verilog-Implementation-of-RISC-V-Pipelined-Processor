`timescale 1ns / 1ps

// Detects the one hazard forwarding cannot fix: load-use.
//
// A load produces its result at the end of MEM, but the instruction directly
// behind it needs that value at the start of its EX - one cycle too early.
// Forwarding cannot move a value backward in time, so the pipeline stalls for
// one cycle instead.
//
// The condition: the instruction in ID/EX is a load, and its destination
// matches a source register of the instruction in IF/ID, which would enter EX
// next. On a stall the top level freezes the PC and IF/ID, and injects a
// bubble into ID/EX.

module hazard_detection_unit (
    input  wire        id_ex_mem_read,
    input  wire [4:0]  id_ex_rd_addr,
    input  wire [4:0]  if_id_rs1_addr,
    input  wire [4:0]  if_id_rs2_addr,

    output wire        stall
);
    assign stall = id_ex_mem_read &&
                   (id_ex_rd_addr != 5'd0) &&
                   ((id_ex_rd_addr == if_id_rs1_addr) ||
                    (id_ex_rd_addr == if_id_rs2_addr));
endmodule
