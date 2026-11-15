// SRAM wrapper, 2**AW x 32 (default AW=11: 8 KB), 1rw1r, 8-bit write
// granularity. Used for every SRAM in soc_fabric: the two-port I-SRAM uses
// both ports (USE_PORT1=1), and the D-SRAM (and the ISRAM_1RW=1 single-port
// I-SRAM) elaborate USE_PORT1=0 -- no port-1 bank select or output mux is
// built, dout1 is driven to a constant, and under -DSOC_SRAM_MACRO every
// macro's csb1 is held high with addr1 zero, which is what holds the port-1
// read off (0004-sram-macro-organization.md item 5).
// Port interface follows the OpenRAM convention (active-low csb/web, one-cycle
// registered read). Port 0 reads and writes; port 1 reads.
// AW is the word-address width; the macro build supports AW=11 only.
// Default build: behavioural model. With -DSOC_SRAM_MACRO: four
// sky130_sram_2kbyte_1rw1r_32x512_8 macros, bank = addr[10:9]
// (0004-sram-macro-organization.md). Under the macro build a bank's dout is
// only valid for the cycle after
// a read of that bank (the macro model drives X otherwise), so the registered
// bank select is what the output mux uses.
// A port-1 read of the word port 0 writes in the same cycle returns the old
// data (the macro leaves that case undefined; the fabric does not rely on it).
module soc_sram_i #(
    parameter int AW = 11,
    parameter bit USE_PORT1 = 1'b1
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
        .clk1  (clk1),
        .csb1  (USE_PORT1 ? (csb1 || addr1[10:9] != 2'(k)) : 1'b1),
        .addr1 (USE_PORT1 ? addr1[8:0] : '0),
        .dout1 (bank_dout1[k])
    );
  end

  always_ff @(posedge clk0) if (!csb0 && web0) bsel0 <= addr0[10:9];
  assign dout0 = bank_dout0[bsel0];

  if (USE_PORT1) begin : g_port1
    logic [1:0] bsel1;

    always_ff @(posedge clk1) if (!csb1) bsel1 <= addr1[10:9];
    assign dout1 = bank_dout1[bsel1];
  end else begin : g_no_port1
    assign dout1 = '0;
  end
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

  if (USE_PORT1) begin : g_port1
    always_ff @(posedge clk1) begin
      if (!csb1) dout1 <= mem[addr1];
    end
  end else begin : g_no_port1
    assign dout1 = '0;
  end
`endif
endmodule
