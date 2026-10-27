// Instruction SRAM wrapper, single port (1rw), 2**AW x 32 (default AW=11:
// 8 KB), 8-bit write granularity. Selected by soc_fabric ISRAM_1RW=1 in place
// of soc_sram_i (1rw1r). Same OpenRAM-style port as soc_sram_d (active-low
// csb/web, one-cycle registered read); the fabric arbitrates the data-side
// write against the fetch onto this one port.
// Behavioural model only: no macro view exists for this organization (record
// 0004); soc_fabric rejects ISRAM_1RW=1 in the -DSOC_SRAM_MACRO build.
module soc_sram_i_1rw #(
    parameter int AW = 11
) (
    input  logic          clk0,
    input  logic          csb0,
    input  logic          web0,
    input  logic [3:0]    wmask0,
    input  logic [AW-1:0] addr0,
    input  logic [31:0]   din0,
    output logic [31:0]   dout0
);
  logic [31:0] mem[2**AW];

  always_ff @(posedge clk0) begin
    if (!csb0) begin
      if (!web0) begin
        for (int b = 0; b < 4; b++) if (wmask0[b]) mem[addr0][8*b+:8] <= din0[8*b+:8];
      end else begin
        dout0 <= mem[addr0];
      end
    end
  end
endmodule
