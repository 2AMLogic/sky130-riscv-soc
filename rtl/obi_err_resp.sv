// OBI error responder: grants every request in the cycle it is made and
// answers one cycle later with an error response (rvalid_o with err_o), so an
// access routed here completes in a fixed, bounded time and never hangs.
module obi_err_resp (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic req_i,
    output logic gnt_o,
    output logic rvalid_o,
    output logic err_o
);
  assign gnt_o = 1'b1;
  assign err_o = rvalid_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rvalid_o <= 1'b0;
    else rvalid_o <= req_i;
  end
endmodule
