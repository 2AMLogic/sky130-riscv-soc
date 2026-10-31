// Boot ROM, 4 KB (1024 x 32), one-cycle synchronous read.
// The image is a hex file (one 32-bit word per line, $readmemh format) given by
// the INIT_FILE parameter or, in simulation, a +rom_hex=<path> plusarg that
// overrides it. There is no default image: with neither, simulation stops.
// A synthesis flow replaces this behavioural array with the generated
// standard-cell ROM (spec/soc.md § Memory map).
module boot_rom #(
    parameter string INIT_FILE = ""
) (
    input  logic        clk_i,
    input  logic        req_i,
    input  logic [11:2] addr_i,
    output logic [31:0] rdata_o
);
  logic [31:0] mem[1024];
`ifdef SYNTHESIS
  // Synthesis flow: the image path is the SOC_ROM_HEX define (a bare path; a
  // parameter override cannot reach this module, Yosys reads it before chparam),
  // and Yosys turns the $readmemh into the ROM contents. No plusarg, no $fatal
  // (neither synthesizes).
`define SOC_STR(x) `"x`"
  initial $readmemh(`SOC_STR(`SOC_ROM_HEX), mem);
`else
  string       path;

  initial begin
    for (int i = 0; i < 1024; i++) mem[i] = 32'h0;
    if (!$value$plusargs("rom_hex=%s", path)) path = INIT_FILE;
    if (path == "") $fatal(1, "boot_rom: no image (set INIT_FILE or pass +rom_hex=<path>)");
    $readmemh(path, mem);
  end
`endif

  always_ff @(posedge clk_i) begin
    if (req_i) rdata_o <= mem[addr_i];
  end
endmodule
