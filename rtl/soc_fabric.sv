// Memory fabric: crossbar plus boot ROM, I-SRAM, D-SRAM and the peripheral
// window. The window decodes per_addr[15:12]: page 1 GPIO, page 2 timer; the
// UART page (0) and every other page answer with an OBI error (until the UART
// lands, page 0 stays on the error responder). The SoC top instantiates this
// with the core's OBI ports. Memories and peripherals respond with the fixed
// one-cycle latency obi_xbar relies on.
//
// Parameters (defaults give the ratified 8 KB 1rw1r I-SRAM / 8 KB D-SRAM):
//   ISRAM_AW, DSRAM_AW  word-address width of each SRAM (11 = 2048 words).
//   ISRAM_1RW           0: two-port I-SRAM (soc_sram_i), data-side write and
//                          fetch proceed in the same cycle, both grants 1.
//                       1: single-port I-SRAM (soc_sram_i_1rw). isd and isi
//                          share the port with fixed priority: the data side
//                          wins and the fetch's grant is held low for as long
//                          as a data-side access targets the I-SRAM; it
//                          retries. The loser is never accepted, so the
//                          response stays one cycle after the grant. Data wins
//                          because a data access is one per instruction and
//                          cannot be starved, while fetch-priority could starve
//                          a loader store behind a streaming prefetcher (the
//                          boot ROM, unlike this, gives the fetch priority).
module soc_fabric #(
    parameter int ISRAM_AW  = 11,
    parameter int DSRAM_AW  = 11,
    parameter bit ISRAM_1RW = 1'b0
) (
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
    output logic        d_err_o,

    input  logic [7:0]  gpio_i,
    output logic [7:0]  gpio_o,
    output logic [7:0]  gpio_oe_o,
    output logic        irq_gpio_o,
    output logic        irq_timer_o
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
  logic [31:0] per_addr, per_wdata, per_rdata;
  logic        per_we;
  logic [3:0]  per_be;
  logic        isd_gnt, isi_gnt;

  obi_xbar #(
      .ISRAM_AW(ISRAM_AW),
      .DSRAM_AW(DSRAM_AW)
  ) u_xbar (
      .clk_i, .rst_ni,
      .i_req_i, .i_gnt_o, .i_addr_i, .i_we_i, .i_be_i, .i_wdata_i,
      .i_rvalid_o, .i_rdata_o, .i_err_o,
      .d_req_i, .d_gnt_o, .d_addr_i, .d_we_i, .d_be_i, .d_wdata_i,
      .d_rvalid_o, .d_rdata_o, .d_err_o,
      .rom_req_o(rom_req), .rom_gnt_i(1'b1), .rom_addr_o(rom_addr), .rom_rdata_i(rom_rdata),
      .isd_req_o(isd_req), .isd_gnt_i(isd_gnt), .isd_addr_o(isd_addr), .isd_we_o(isd_we),
      .isd_be_o(isd_be), .isd_wdata_o(isd_wdata), .isd_rdata_i(isd_rdata),
      .isi_req_o(isi_req), .isi_gnt_i(isi_gnt), .isi_addr_o(isi_addr), .isi_rdata_i(isi_rdata),
      .dsr_req_o(dsr_req), .dsr_gnt_i(1'b1), .dsr_addr_o(dsr_addr), .dsr_we_o(dsr_we),
      .dsr_be_o(dsr_be), .dsr_wdata_o(dsr_wdata), .dsr_rdata_i(dsr_rdata),
      .per_req_o(per_req), .per_gnt_i(per_gnt), .per_addr_o(per_addr), .per_we_o(per_we), .per_be_o(per_be),
      .per_wdata_o(per_wdata), .per_rdata_i(per_rdata), .per_err_i(per_err)
  );

  boot_rom u_rom (
      .clk_i,
      .req_i  (rom_req),
      .addr_i (rom_addr[11:2]),
      .rdata_o(rom_rdata)
  );

`ifdef SOC_SRAM_MACRO
  if (ISRAM_1RW) begin : g_no_1rw_macro
    $error("ISRAM_1RW=1 has no macro view (record 0004); the macro build is 1rw1r");
  end
`endif

  if (ISRAM_1RW) begin : g_isram_1rw
    // One port: the data side (isd) wins, the fetch (isi) waits.
    logic        port_req;
    logic [31:0] port_addr, port_dout;
    assign port_req = isd_req || isi_req;
    assign port_addr = isd_req ? isd_addr : isi_addr;
    assign isd_gnt  = 1'b1;
    assign isi_gnt  = !isd_req;
    assign isd_rdata = port_dout;
    assign isi_rdata = port_dout;

    soc_sram_i_1rw #(
        .AW(ISRAM_AW)
    ) u_isram (
        .clk0  (clk_i),
        .csb0  (!port_req),
        .web0  (isd_req ? !isd_we : 1'b1),
        .wmask0(isd_be),
        .addr0 (port_addr[ISRAM_AW+1:2]),
        .din0  (isd_wdata),
        .dout0 (port_dout)
    );
  end else begin : g_isram_1rw1r
    assign isd_gnt = 1'b1;
    assign isi_gnt = 1'b1;

    soc_sram_i #(
        .AW(ISRAM_AW)
    ) u_isram (
        .clk0  (clk_i),
        .csb0  (!isd_req),
        .web0  (!isd_we),
        .wmask0(isd_be),
        .addr0 (isd_addr[ISRAM_AW+1:2]),
        .din0  (isd_wdata),
        .dout0 (isd_rdata),
        .clk1  (clk_i),
        .csb1  (!isi_req),
        .addr1 (isi_addr[ISRAM_AW+1:2]),
        .dout1 (isi_rdata)
    );
  end

  soc_sram_d #(
      .AW(DSRAM_AW)
  ) u_dsram (
      .clk0  (clk_i),
      .csb0  (!dsr_req),
      .web0  (!dsr_we),
      .wmask0(dsr_be),
      .addr0 (dsr_addr[DSRAM_AW+1:2]),
      .din0  (dsr_wdata),
      .dout0 (dsr_rdata)
  );

  // Peripheral window. Pages: 0 UART (not yet present: error), 1 GPIO, 2 timer.
  localparam logic [3:0] PageGpio = 4'd1, PageTimer = 4'd2;
  wire        gpio_sel = per_req && per_addr[15:12] == PageGpio;
  wire        timer_sel = per_req && per_addr[15:12] == PageTimer;
  logic [31:0] gpio_rdata, timer_rdata;
  logic        gpio_err, timer_err, page_err_q;

  assign per_gnt = 1'b1;

  gpio u_gpio (
      .clk_i, .rst_ni,
      .req_i(gpio_sel), .we_i(per_we), .be_i(per_be), .addr_i(per_addr[11:0]),
      .wdata_i(per_wdata), .rdata_o(gpio_rdata), .err_o(gpio_err),
      .gpio_i, .gpio_o, .gpio_oe_o, .irq_o(irq_gpio_o)
  );

  timer u_timer (
      .clk_i, .rst_ni,
      .req_i(timer_sel), .we_i(per_we), .be_i(per_be), .addr_i(per_addr[11:0]),
      .wdata_i(per_wdata), .rdata_o(timer_rdata), .err_o(timer_err),
      .irq_o(irq_timer_o)
  );

  // Both peripherals register rdata (zero when not addressed) and err, so the
  // response is the OR of the pages plus the error for the unmapped pages.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) page_err_q <= 1'b0;
    else page_err_q <= per_req && !gpio_sel && !timer_sel;
  end

  assign per_rdata = gpio_rdata | timer_rdata;
  assign per_err   = page_err_q | gpio_err | timer_err;
endmodule
