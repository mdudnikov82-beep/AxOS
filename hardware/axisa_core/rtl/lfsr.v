// 32-bit maximal-length Fibonacci XOR-LFSR - AxISA's first hardware
// random-number source, used by cpu_core.v's QMEASURE sequencer to
// draw a measurement outcome. Taps [32,22,2,1] are a real, standard
// maximal-length polynomial (Xilinx XAPP052's own reference table),
// not an invented choice.
//
// Deliberately free-running off clk/reset ALONE - not gated by
// cpu_stall or halted_r. This is a genuine entropy tap: the LFSR's
// value at the exact cycle QMEASURE samples it depends on how many
// cycles have elapsed since reset across the WHOLE program's prior
// execution (branches taken, stalls hit, etc.), not on anything
// QMEASURE itself controls - gating it on CPU state would make its
// value at sample-time far more predictable/reproducible from the
// program text alone, which is the opposite of the point.
//
// Nonzero seed at reset is a hard defensive requirement, not a style
// choice: an XOR-LFSR's all-zero state is a fixed point (feedback of
// an all-zero register is always 0, so it never leaves that state).
// The recurrence below is a bijection on the other 2^32-1 states, so
// starting nonzero guarantees the all-zero state is never reached.
//
// Explicitly NOT a cryptographically secure PRNG: fully deterministic
// given the seed, period exactly 2^32-1, and successive draws are
// linearly correlated (recoverable via Berlekamp-Massey from a
// handful of outputs). This is honest and sufficient for a CLASSICAL
// quantum-circuit simulator's measurement-outcome flavor (this
// project's own "explicitly not real quantum hardware" framing
// already applies, see docs/ISA.md's QHAD/QCNOT/QMEASURE section) -
// never to be described as statistically or cryptographically
// rigorous.
`timescale 1ns/1ps

module lfsr32 (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] q
);
    reg [31:0] state;

    wire feedback = state[31] ^ state[21] ^ state[1] ^ state[0]; // taps 32,22,2,1

    always @(posedge clk or posedge reset) begin
        if (reset) state <= 32'hACE1_1234; // any fixed nonzero seed
        else       state <= {state[30:0], feedback};
    end

    assign q = state;
endmodule
