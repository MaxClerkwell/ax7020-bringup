// "Blank" design for the AX7020: only the PS7 block, no I/O, no logic.
// Loading it clears whatever ran in the PL before (all LEDs off) while
// keeping the PS-PL interface tied off safely.
module empty ();
    (* keep *) PS7 ps7_i();
endmodule
