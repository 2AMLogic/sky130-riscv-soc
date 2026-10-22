// Placeholder DUT for the harness smoke test: an 8-bit register with
// synchronous reset. Replaced by the SoC top when the RTL lands; the harness
// (verification/Makefile) takes TOPLEVEL/MODULE/VERILOG_SOURCES as variables.
module dut (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] d,
    output reg  [7:0] q
);
    always @(posedge clk) begin
        if (!rst_n) q <= 8'h00;
        else        q <= d;
    end
endmodule
