// Synthesis-only stand-in for rtl/instr_mem.v - NOT used for
// simulation, only for getting an honest FPGA area estimate.
//
// rtl/instr_mem.v is a pure ROM (no write port anywhere) that's only
// ever $readmemh-loaded if INSTR_INIT_FILE is non-empty. Synthesized
// with no program loaded, its content is never written anywhere in
// the whole design - Yosys resolves this to a constant during
// optimization (unlike simulation, where it reads as X), and since
// that constant `instr` feeds control_unit's entire opcode decode,
// ABC can then prove almost the whole datapath (all 4 register
// banks, the ALU, most of control_unit) is "unreachable" for that one
// fixed instruction and deletes it. First attempt at a real
// synth_ecp5 run on cpu_core.v hit exactly this: 52 total cells,
// obviously wrong for a whole CPU.
//
// A real loaded test program fixes the collapse but still
// UNDERSTATES the true worst case - it only exercises whatever
// opcodes that one program happens to use, not every opcode AxISA
// actually supports. `(* keep *)` on the memory array/output wire
// does NOT fix this (tried and confirmed - the constant-resolution
// happens in passes that run before `(* keep *)` has any effect on
// downstream logic).
//
// The fix that actually works: blackbox this module entirely. A
// blackboxed module's output is treated as genuinely arbitrary by the
// rest of the design - exactly the honest question a real,
// programmable chip needs answered ("how big does the decoder need to
// be to handle ANY possible instruction"), not "how big is it once
// frozen to one specific program." instr_mem's own real area (fixed
// by MEM_WORDS, independent of content - roughly 2 real ECP5 DP16KD
// block RAMs for the default 1024x32) is NOT part of this run's cell
// count and must be accounted separately.
//
// Port list matches rtl/instr_mem.v's current (post registered-fetch
// redesign, see [[project_axisa_synthesis_check]]) signature exactly -
// `clk`/`stall`/`SYNC_READ` are all real ports on the actual module
// now, so cpu_core.v's own instr_mem instantiation would fail
// elaboration against a stale port list even though this stand-in's
// own internals are blackboxed and don't care about SYNC_READ's
// value.
//
// Usage: read_verilog this file INSTEAD OF rtl/instr_mem.v (not both -
// same module name), then synth_ecp5 -top cpu_core_fpga_top.
`timescale 1ns/1ps

(* blackbox *)
module instr_mem #(
    parameter MEM_WORDS = 1024,
    parameter INIT_FILE = "",
    parameter SYNC_READ = 0
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire        stall,
    output wire [31:0] instr
);
endmodule
