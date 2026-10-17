// TOOLCHAIN EVIDENCE, NOT DESIGN EVIDENCE.
// This module exists only to prove the pinned PDK and toolchain run end to
// end (see docs/environment.md). It is not part of the SoC, and its results
// must never be cited for a T1 item or any design claim.
module counter (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) count <= 8'd0;
        else        count <= count + 8'd1;
    end
endmodule
