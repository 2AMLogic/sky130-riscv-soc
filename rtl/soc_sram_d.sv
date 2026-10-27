// Data SRAM wrapper, 8 KB (2048 x 32), 1rw, 8-bit write granularity.
// OpenRAM-style port (active-low csb/web, one-cycle registered read).
// Default build: behavioural model. With -DSOC_SRAM_MACRO: four
// sky130_sram_2kbyte_1rw1r_32x512_8 macros, bank = addr[10:9], port 1 of each
// tied off (csb1 high, unused; decision record 0004: no 1rw view exists).
module soc_sram_d (
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic [3:0]  wmask0,
    input  logic [10:0] addr0,
    input  logic [31:0] din0,
    output logic [31:0] dout0
);
`ifdef SOC_SRAM_MACRO
  logic [31:0] bank_dout0[4];
  logic [1:0] bsel0;

  for (genvar k = 0; k < 4; k++) begin : g_bank
    sky130_sram_2kbyte_1rw1r_32x512_8 u_macro (
        .clk0  (clk0),
        .csb0  (csb0 || addr0[10:9] != 2'(k)),
        .web0  (web0),
        .wmask0(wmask0),
        .addr0 (addr0[8:0]),
        .din0  (din0),
        .dout0 (bank_dout0[k]),
        .clk1  (clk0),
        .csb1  (1'b1),
        .addr1 (9'b0),
        .dout1 ()
    );
  end

  always_ff @(posedge clk0) if (!csb0 && web0) bsel0 <= addr0[10:9];

  assign dout0 = bank_dout0[bsel0];
`else
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
`endif
endmodule
