// Reset synchroniser: asynchronous assert, synchronous deassert, two flops
// (spec/soc.md § Clock and reset). Instantiated once in the SoC top.
module rst_sync (
    input  logic clk_i,
    input  logic rst_ni,
    output logic rst_no
);
  logic q1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      q1     <= 1'b0;
      rst_no <= 1'b0;
    end else begin
      q1     <= 1'b1;
      rst_no <= q1;
    end
  end
endmodule
