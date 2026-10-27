// Instruction SRAM wrapper, 2**AW x 32 (default AW=11: 8 KB), 1rw1r, 8-bit write
// granularity.
// Port interface follows the OpenRAM convention (active-low csb/web, one-cycle
// registered read). Port 0 reads and writes; port 1 reads.
// AW is the word-address width; the macro build supports AW=11 only.
// Default build: behavioural model. With -DSOC_SRAM_MACRO: four
// sky130_sram_2kbyte_1rw1r_32x512_8 macros, bank = addr[10:9] (decision record
// 0004). Under the macro build a bank's dout is only valid for the cycle after
// a read of that bank (the macro model drives X otherwise), so the registered
// bank select is what the output mux uses.
// A port-1 read of the word port 0 writes in the same cycle returns the old
// data (the macro leaves that case undefined; the fabric does not rely on it).
module soc_sram_i #(
    parameter int AW = 11
) (
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic [3:0]  wmask0,
    input  logic [AW-1:0] addr0,
    input  logic [31:0] din0,
    output logic [31:0] dout0,
    input  logic        clk1,
    input  logic        csb1,
    input  logic [AW-1:0] addr1,
    output logic [31:0] dout1
);
`ifdef SOC_SRAM_MACRO
  if (AW != 11) begin : g_aw_check
    $error("SOC_SRAM_MACRO build is 4 x 512 words: AW must be 11");
  end

  logic [31:0] bank_dout0[4], bank_dout1[4];
  logic [1:0] bsel0, bsel1;

  for (genvar k = 0; k < 4; k++) begin : g_bank
    sky130_sram_2kbyte_1rw1r_32x512_8 u_macro (
        .clk0  (clk0),
        .csb0  (csb0 || addr0[10:9] != 2'(k)),
        .web0  (web0),
        .wmask0(wmask0),
        .addr0 (addr0[8:0]),
        .din0  (din0),
        .dout0 (bank_dout0[k]),
        .clk1  (clk1),
        .csb1  (csb1 || addr1[10:9] != 2'(k)),
        .addr1 (addr1[8:0]),
        .dout1 (bank_dout1[k])
    );
  end

  always_ff @(posedge clk0) if (!csb0 && web0) bsel0 <= addr0[10:9];
  always_ff @(posedge clk1) if (!csb1) bsel1 <= addr1[10:9];

  assign dout0 = bank_dout0[bsel0];
  assign dout1 = bank_dout1[bsel1];
`else
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

  always_ff @(posedge clk1) begin
    if (!csb1) dout1 <= mem[addr1];
  end
`endif
endmodule
