// XYZW-routed single-flit mesh router - the core building block of the
// NoC that replaces shared_bus.v (see [[project_noc_router]] for the
// full design rationale). Nine ports (N/E/S/W/Up/Down/Ana/Kata/Local),
// each a standard valid/flit/ready handshake in BOTH directions (in_*
// and out_*), with a 1-flit skid-buffer register per OUTPUT port - a
// flit takes exactly one clock edge to cross one hop, and every hop
// has real backpressure (an already-buffered-but-not-yet-accepted
// flit is never silently overwritten by a new arrival on the same
// input).
//
// `ana`/`kata` are the two directions along a 4th spatial axis, `W`
// (confirmed by design review before this was written) - NOT to be
// confused with the pre-existing West port (`w_in_valid`/`w_out_valid`,
// on the X axis) despite the shared letter; `MY_W`/`dest_w`/`src_w`
// always refer to the 4th axis, never lowercased into a bare `w` port
// name anywhere in this file. "ana" (increasing W, dest_w>MY_W) and
// "kata" (decreasing W, dest_w<MY_W) are Charles Howard Hinton's real
// 1880s terms for the two directions along a 4th spatial dimension -
// genuine historical terminology, same spirit as this project already
// using the real Dally-Seitz deadlock-freedom result rather than
// inventing its own name for it.
//
// The flit format is fully opaque to this module except its top
// 4*COORD_BITS bits, which MUST be {dest_x[COORD_BITS-1:0],
// dest_y[COORD_BITS-1:0], dest_z[COORD_BITS-1:0], dest_w[COORD_BITS-1:0]}
// - everything below that (address, data, control fields, whatever a
// specific network carries) is routed through unmodified. COORD_BITS
// is shared across all four axes even when they're different sizes -
// confirmed by design review to be numerically safe as long as EVERY
// axis's real coordinate range fits, not just the largest one; widen
// it for a bigger mesh, the same way earlier scale-ups did. This lets
// ONE module serve as both the request-network router and the
// response-network router (different FLIT_WIDTH, same logic) - a
// design-review recommendation specifically to make "these two
// networks share no state" a structural, build-time-checkable property
// instead of a code-review-only one (two independent module instances,
// never one wider one).
//
// Routing: move in X first (E if dest_x>MY_X, W if <), once dest_x==MY_X
// switch to Y (S if dest_y>MY_Y, N if <), once dest_y==MY_Y switch to Z
// (D if dest_z>MY_Z, U if <), once dest_z==MY_Z switch to W (Ana if
// dest_w>MY_W, Kata if <), deliver to Local once all four match -
// classic dimension-order (XYZW) routing, deadlock-free on a mesh (no
// virtual channels needed) by the same standard result (Dally & Seitz)
// this project already relied on for XY and XYZ routing without
// re-deriving it - the proof holds for any strictly-ordered dimension
// count, not just two or three, PROVIDED this stays a true mesh (no
// wraparound links - adding one would turn this into a torus, where
// dimension-order routing is NOT deadlock-free without extra virtual
// channels, a completely different result). The specific total order
// (X,Y,Z,W) is an arbitrary but FIXED choice - Dally-Seitz only
// requires *a* consistent order, not a particular one, and this order
// was picked to append W as a 4th tier without touching the existing
// X/Y/Z tiers at all. A flit never needs to exit the direction it just
// arrived from - movement within each axis is monotonic under
// dimension-order routing, independently per axis - so "every OTHER
// direction is a valid candidate for output O" is exact regardless of
// how many axes there are, not an approximation (confirmed during
// design review before the Z axis was added, re-confirmed for W).
// Edge/face/hyperface grid positions simply never have a real neighbor
// wired to some directions in soc_top.v (tied to 0) - no special-casing
// needed here, since a router whose MY_X/MY_Y/MY_Z/MY_W sits on a grid
// boundary can, by construction, never need to route further past that
// boundary (destinations are always in-range for this grid).
`timescale 1ns/1ps

module router #(
    parameter FLIT_WIDTH = 92, // always overridden per-instance (request vs response network width differ) - see noc_core_adapter.v/noc_mem_adapter.v for the real formulas
    parameter COORD_BITS = 3, // grid coords are 0..(2**COORD_BITS - 1) on EVERY axis; widen if any single axis needs more values
    parameter MY_X = 0,
    parameter MY_Y = 0,
    parameter MY_Z = 0,
    parameter MY_W = 0
) (
    input  wire clk,
    input  wire reset,

    input  wire                  n_in_valid,
    input  wire [FLIT_WIDTH-1:0] n_in_flit,
    output wire                  n_in_ready,
    output wire                  n_out_valid,
    output wire [FLIT_WIDTH-1:0] n_out_flit,
    input  wire                  n_out_ready,

    input  wire                  e_in_valid,
    input  wire [FLIT_WIDTH-1:0] e_in_flit,
    output wire                  e_in_ready,
    output wire                  e_out_valid,
    output wire [FLIT_WIDTH-1:0] e_out_flit,
    input  wire                  e_out_ready,

    input  wire                  s_in_valid,
    input  wire [FLIT_WIDTH-1:0] s_in_flit,
    output wire                  s_in_ready,
    output wire                  s_out_valid,
    output wire [FLIT_WIDTH-1:0] s_out_flit,
    input  wire                  s_out_ready,

    input  wire                  w_in_valid,
    input  wire [FLIT_WIDTH-1:0] w_in_flit,
    output wire                  w_in_ready,
    output wire                  w_out_valid,
    output wire [FLIT_WIDTH-1:0] w_out_flit,
    input  wire                  w_out_ready,

    input  wire                  u_in_valid,
    input  wire [FLIT_WIDTH-1:0] u_in_flit,
    output wire                  u_in_ready,
    output wire                  u_out_valid,
    output wire [FLIT_WIDTH-1:0] u_out_flit,
    input  wire                  u_out_ready,

    input  wire                  d_in_valid,
    input  wire [FLIT_WIDTH-1:0] d_in_flit,
    output wire                  d_in_ready,
    output wire                  d_out_valid,
    output wire [FLIT_WIDTH-1:0] d_out_flit,
    input  wire                  d_out_ready,

    // 4th axis (W) - see this file's own header comment for why these
    // are named ana/kata instead of following the compass/up-down
    // pattern, and why they are NOT related to the West port above.
    input  wire                  ana_in_valid,
    input  wire [FLIT_WIDTH-1:0] ana_in_flit,
    output wire                  ana_in_ready,
    output wire                  ana_out_valid,
    output wire [FLIT_WIDTH-1:0] ana_out_flit,
    input  wire                  ana_out_ready,

    input  wire                  kata_in_valid,
    input  wire [FLIT_WIDTH-1:0] kata_in_flit,
    output wire                  kata_in_ready,
    output wire                  kata_out_valid,
    output wire [FLIT_WIDTH-1:0] kata_out_flit,
    input  wire                  kata_out_ready,

    input  wire                  l_in_valid,
    input  wire [FLIT_WIDTH-1:0] l_in_flit,
    output wire                  l_in_ready,
    output wire                  l_out_valid,
    output wire [FLIT_WIDTH-1:0] l_out_flit,
    input  wire                  l_out_ready
);
    localparam NDIRS = 9;
    localparam DIR_N = 0, DIR_E = 1, DIR_S = 2, DIR_W = 3, DIR_U = 4, DIR_D = 5,
               DIR_ANA = 6, DIR_KATA = 7, DIR_L = 8;

    // Design-review finding: at NDIRS=7 every direction index (0-6)
    // happened to fit in 3 bits, so a hardcoded [2:0] width was
    // silently safe. NDIRS=9 needs DIR_L=8, which truncates to 0 in a
    // 3-bit register (aliasing Local delivery onto North's arbitration
    // state) - DIRBITS makes this correct by construction instead of
    // by coincidence, and survives a future 5th dimension too.
    localparam DIRBITS = $clog2(NDIRS);

    wire                  in_valid  [0:NDIRS-1];
    wire [FLIT_WIDTH-1:0] in_flit   [0:NDIRS-1];
    wire                  in_ready  [0:NDIRS-1];
    wire                  out_valid [0:NDIRS-1];
    wire [FLIT_WIDTH-1:0] out_flit  [0:NDIRS-1];
    wire                  out_ready [0:NDIRS-1];

    assign in_valid[DIR_N] = n_in_valid; assign in_flit[DIR_N] = n_in_flit; assign n_in_ready = in_ready[DIR_N];
    assign in_valid[DIR_E] = e_in_valid; assign in_flit[DIR_E] = e_in_flit; assign e_in_ready = in_ready[DIR_E];
    assign in_valid[DIR_S] = s_in_valid; assign in_flit[DIR_S] = s_in_flit; assign s_in_ready = in_ready[DIR_S];
    assign in_valid[DIR_W] = w_in_valid; assign in_flit[DIR_W] = w_in_flit; assign w_in_ready = in_ready[DIR_W];
    assign in_valid[DIR_U] = u_in_valid; assign in_flit[DIR_U] = u_in_flit; assign u_in_ready = in_ready[DIR_U];
    assign in_valid[DIR_D] = d_in_valid; assign in_flit[DIR_D] = d_in_flit; assign d_in_ready = in_ready[DIR_D];
    assign in_valid[DIR_ANA]  = ana_in_valid;  assign in_flit[DIR_ANA]  = ana_in_flit;  assign ana_in_ready  = in_ready[DIR_ANA];
    assign in_valid[DIR_KATA] = kata_in_valid; assign in_flit[DIR_KATA] = kata_in_flit; assign kata_in_ready = in_ready[DIR_KATA];
    assign in_valid[DIR_L] = l_in_valid; assign in_flit[DIR_L] = l_in_flit; assign l_in_ready = in_ready[DIR_L];

    assign n_out_valid = out_valid[DIR_N]; assign n_out_flit = out_flit[DIR_N]; assign out_ready[DIR_N] = n_out_ready;
    assign e_out_valid = out_valid[DIR_E]; assign e_out_flit = out_flit[DIR_E]; assign out_ready[DIR_E] = e_out_ready;
    assign s_out_valid = out_valid[DIR_S]; assign s_out_flit = out_flit[DIR_S]; assign out_ready[DIR_S] = s_out_ready;
    assign w_out_valid = out_valid[DIR_W]; assign w_out_flit = out_flit[DIR_W]; assign out_ready[DIR_W] = w_out_ready;
    assign u_out_valid = out_valid[DIR_U]; assign u_out_flit = out_flit[DIR_U]; assign out_ready[DIR_U] = u_out_ready;
    assign d_out_valid = out_valid[DIR_D]; assign d_out_flit = out_flit[DIR_D]; assign out_ready[DIR_D] = d_out_ready;
    assign ana_out_valid  = out_valid[DIR_ANA];  assign ana_out_flit  = out_flit[DIR_ANA];  assign out_ready[DIR_ANA]  = ana_out_ready;
    assign kata_out_valid = out_valid[DIR_KATA]; assign kata_out_flit = out_flit[DIR_KATA]; assign out_ready[DIR_KATA] = kata_out_ready;
    assign l_out_valid = out_valid[DIR_L]; assign l_out_flit = out_flit[DIR_L]; assign out_ready[DIR_L] = l_out_ready;

    // ---- Routing decision: which output direction does each input want? ----
    // Only meaningful where in_valid is actually set - an invalid input's
    // wanted_dir is never consulted by the arbitration below.
    wire [DIRBITS-1:0] wanted_dir [0:NDIRS-1];

    genvar gi;
    generate
        for (gi = 0; gi < NDIRS; gi = gi + 1) begin: route_calc
            wire [COORD_BITS-1:0] dest_x = in_flit[gi][FLIT_WIDTH-1 -: COORD_BITS];
            wire [COORD_BITS-1:0] dest_y = in_flit[gi][FLIT_WIDTH-1-COORD_BITS -: COORD_BITS];
            wire [COORD_BITS-1:0] dest_z = in_flit[gi][FLIT_WIDTH-1-2*COORD_BITS -: COORD_BITS];
            wire [COORD_BITS-1:0] dest_w = in_flit[gi][FLIT_WIDTH-1-3*COORD_BITS -: COORD_BITS];
            assign wanted_dir[gi] =
                (dest_x != MY_X) ? (dest_x > MY_X ? DIR_E : DIR_W) :
                (dest_y != MY_Y) ? (dest_y > MY_Y ? DIR_S : DIR_N) :
                (dest_z != MY_Z) ? (dest_z > MY_Z ? DIR_D : DIR_U) :
                (dest_w != MY_W) ? (dest_w > MY_W ? DIR_ANA : DIR_KATA) :
                DIR_L;
        end
    endgenerate

    // ---- Per-output round-robin arbitration + 1-flit skid buffer ----
    // Mirrors shared_bus.v's own last_granted/scan-and-wrap pattern
    // exactly, just applied per output DIRECTION instead of per whole
    // bus - confirmed by design review to carry over cleanly regardless
    // of NDIRS (at most NDIRS-1 of the directions can ever want the
    // same output, since a direction never wants itself - an invariant
    // proved per-axis by monotonicity, not a coincidence of any
    // specific NDIRS, so it holds independently and unchanged for both
    // the Z and W axes).
    wire winner_valid [0:NDIRS-1];
    wire [DIRBITS-1:0] winner_dir [0:NDIRS-1];

    genvar go;
    generate
        for (go = 0; go < NDIRS; go = go + 1) begin: outp
            reg [FLIT_WIDTH-1:0] flit_r;
            reg                  valid_r;
            reg [DIRBITS-1:0]    last_granted;
            reg [DIRBITS-1:0]    chosen;
            reg                  chosen_valid;
            integer              kk;
            reg [DIRBITS-1:0]    cand;

            wire can_accept = !valid_r || out_ready[go];

            always @(*) begin
                chosen_valid = 1'b0;
                chosen = {DIRBITS{1'b0}};
                if (can_accept) begin
                    for (kk = 0; kk < NDIRS; kk = kk + 1) begin
                        cand = (last_granted + 1 + kk) % NDIRS;
                        if (cand != go && !chosen_valid && in_valid[cand] && wanted_dir[cand] == go) begin
                            chosen = cand;
                            chosen_valid = 1'b1;
                        end
                    end
                end
            end

            assign winner_valid[go] = chosen_valid;
            assign winner_dir[go]   = chosen;
            assign out_valid[go]    = valid_r;
            assign out_flit[go]     = flit_r;

            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    valid_r      <= 1'b0;
                    flit_r       <= {FLIT_WIDTH{1'b0}};
                    last_granted <= NDIRS - 1;
                end else if (can_accept) begin
                    if (chosen_valid) begin
                        valid_r      <= 1'b1;
                        flit_r       <= in_flit[chosen];
                        last_granted <= chosen;
                    end else begin
                        valid_r <= 1'b0;
                    end
                end
                // !can_accept: hold everything - downstream isn't ready
                // yet, the already-buffered flit must stay exactly put.
            end
        end
    endgenerate

    // in_ready[d]: this input was the arbitration winner for whatever
    // output it wanted, AND that output's register actually captured it
    // this same cycle (winner_valid already folds in can_accept, so no
    // separate check needed here).
    generate
        for (gi = 0; gi < NDIRS; gi = gi + 1) begin: in_rdy
            assign in_ready[gi] = in_valid[gi] && winner_valid[wanted_dir[gi]] &&
                                   (winner_dir[wanted_dir[gi]] == gi);
        end
    endgenerate
endmodule
