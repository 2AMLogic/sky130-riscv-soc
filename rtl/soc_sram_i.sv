// Instruction SRAM wrapper, 8 KB (2048 x 32), 1rw1r, 8-bit write granularity.
// Port interface follows the OpenRAM convention (active-low csb/web, one-cycle
// registered read); only this body changes when the macro instance (spec row
// 8a) replaces the behavioural model. Port 0 reads and writes; port 1 reads.
// A port-1 read of the word port 0 writes in the same cycle returns the old
// data (the macro leaves that case undefined; the fabric does not rely on it).
module soc_sram_i (
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic [3:0]  wmask0,
    input  logic [10:0] addr0,
    input  logic [31:0] din0,
    output logic [31:0] dout0,
    input  logic        clk1,
    input  logic        csb1,
    input  logic [10:0] addr1,
    output logic [31:0] dout1
);
  logic [31:0] mem[2048];

  always_ff @(posedge clk0) begin
    if (!csb0) begin
      if (!web0) begin
        for (int b = 0; b < 4; b++) if (wmask0[b]) mem[addr0][8*b+:8] <= din0[8*b+:8];
      end else begin
        dout0 <= mem[addr0];
      end
    end
  end

  always_ff @(posedge clk1) begin
    if (!csb1) dout1 <= mem[addr1];
  end
endmodule
