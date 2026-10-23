// Memory fabric: crossbar plus boot ROM, I-SRAM, D-SRAM and the peripheral
// window stub (answers every access with an OBI error until peripherals
// land). The SoC top (issue #19) instantiates this with the core's OBI ports.
// Memories respond with the fixed one-cycle latency obi_xbar relies on.
module soc_fabric (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        i_req_i,
    output logic        i_gnt_o,
    input  logic [31:0] i_addr_i,
    input  logic        i_we_i,
    input  logic [3:0]  i_be_i,
    input  logic [31:0] i_wdata_i,
    output logic        i_rvalid_o,
    output logic [31:0] i_rdata_o,
    output logic        i_err_o,

    input  logic        d_req_i,
    output logic        d_gnt_o,
    input  logic [31:0] d_addr_i,
    input  logic        d_we_i,
    input  logic [3:0]  d_be_i,
    input  logic [31:0] d_wdata_i,
    output logic        d_rvalid_o,
    output logic [31:0] d_rdata_o,
    output logic        d_err_o
);
  logic        rom_req;
  logic [31:0] rom_addr, rom_rdata;
  logic        isd_req, isd_we, isi_req;
  logic [3:0]  isd_be;
  logic [31:0] isd_addr, isd_wdata, isd_rdata, isi_addr, isi_rdata;
  logic        dsr_req, dsr_we;
  logic [3:0]  dsr_be;
  logic [31:0] dsr_addr, dsr_wdata, dsr_rdata;
  logic        per_req, per_gnt, per_err;

  obi_xbar u_xbar (
      .clk_i, .rst_ni,
      .i_req_i, .i_gnt_o, .i_addr_i, .i_we_i, .i_be_i, .i_wdata_i,
      .i_rvalid_o, .i_rdata_o, .i_err_o,
      .d_req_i, .d_gnt_o, .d_addr_i, .d_we_i, .d_be_i, .d_wdata_i,
      .d_rvalid_o, .d_rdata_o, .d_err_o,
      .rom_req_o(rom_req), .rom_gnt_i(1'b1), .rom_addr_o(rom_addr), .rom_rdata_i(rom_rdata),
      .isd_req_o(isd_req), .isd_gnt_i(1'b1), .isd_addr_o(isd_addr), .isd_we_o(isd_we),
      .isd_be_o(isd_be), .isd_wdata_o(isd_wdata), .isd_rdata_i(isd_rdata),
      .isi_req_o(isi_req), .isi_gnt_i(1'b1), .isi_addr_o(isi_addr), .isi_rdata_i(isi_rdata),
      .dsr_req_o(dsr_req), .dsr_gnt_i(1'b1), .dsr_addr_o(dsr_addr), .dsr_we_o(dsr_we),
      .dsr_be_o(dsr_be), .dsr_wdata_o(dsr_wdata), .dsr_rdata_i(dsr_rdata),
      .per_req_o(per_req), .per_gnt_i(per_gnt), .per_addr_o(), .per_we_o(), .per_be_o(),
      .per_wdata_o(), .per_rdata_i(32'h0), .per_err_i(per_err)
  );

  boot_rom u_rom (
      .clk_i,
      .req_i  (rom_req),
      .addr_i (rom_addr[11:2]),
      .rdata_o(rom_rdata)
  );

  soc_sram_i u_isram (
      .clk0  (clk_i),
      .csb0  (!isd_req),
      .web0  (!isd_we),
      .wmask0(isd_be),
      .addr0 (isd_addr[12:2]),
      .din0  (isd_wdata),
      .dout0 (isd_rdata),
      .clk1  (clk_i),
      .csb1  (!isi_req),
      .addr1 (isi_addr[12:2]),
      .dout1 (isi_rdata)
  );

  soc_sram_d u_dsram (
      .clk0  (clk_i),
      .csb0  (!dsr_req),
      .web0  (!dsr_we),
      .wmask0(dsr_be),
      .addr0 (dsr_addr[12:2]),
      .din0  (dsr_wdata),
      .dout0 (dsr_rdata)
  );

  obi_err_resp u_per_stub (
      .clk_i,
      .rst_ni,
      .req_i   (per_req),
      .gnt_o   (per_gnt),
      .rvalid_o(),
      .err_o   (per_err)
  );
endmodule
