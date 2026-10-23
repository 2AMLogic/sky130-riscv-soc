// Boot ROM, 4 KB (1024 x 32), one-cycle synchronous read.
// The image is a checked-in hex source (INIT_FILE, one 32-bit word per line,
// $readmemh format); a +rom_hex=<path> plusarg overrides it in simulation.
// A synthesis flow replaces this behavioural array with the generated
// standard-cell ROM (spec/soc.md § Memory map).
module boot_rom #(
    parameter string INIT_FILE = "boot_rom.hex"
) (
    input  logic        clk_i,
    input  logic        req_i,
    input  logic [11:2] addr_i,
    output logic [31:0] rdata_o
);
  logic [31:0] mem[1024];
  string       path;

  initial begin
    for (int i = 0; i < 1024; i++) mem[i] = 32'h0;
    if (!$value$plusargs("rom_hex=%s", path)) path = INIT_FILE;
    $readmemh(path, mem);
  end

  always_ff @(posedge clk_i) begin
    if (req_i) rdata_o <= mem[addr_i];
  end
endmodule
