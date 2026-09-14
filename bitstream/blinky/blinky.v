// Minimal blinky for the Alinx AX7020 (XC7Z020-2CLG400).
// 50 MHz PL oscillator on U18; four PL LEDs, active high.
module blinky (
    input  wire       sys_clk,
    output wire [3:0] led
);
    reg [26:0] cnt = 27'd0;

    always @(posedge sys_clk)
        cnt <= cnt + 27'd1;

    // 50 MHz / 2^26 ≈ 0.75 Hz on led[0], halved on each further LED
    assign led = cnt[26:23];

    // The PS7 block must be part of the design even if nothing uses it:
    // nextpnr ties its unused PL->PS inputs (incl. IRQF2P, the direct nFIQ/
    // nIRQ lines to both Cortex-A9 cores) to ground. Without it the PL drives
    // those lines once Linux enables the PL->PS level shifters, and both
    // cores drown in FIQs (see docs/walkthrough-stage4-first-load.md).
    (* keep *) PS7 ps7_i();
endmodule
