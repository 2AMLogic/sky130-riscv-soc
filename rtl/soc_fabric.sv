// Memory fabric: crossbar plus boot ROM, I-SRAM, D-SRAM and the peripheral
// window. The window decodes per_addr[15:12]: page 0 UART, page 1 GPIO,
// page 2 timer; every other page answers with an OBI error. The SoC top
// instantiates this with the core's OBI ports. Memories and peripherals
// respond with the fixed one-cycle latency obi_xbar relies on.
//
// Parameters (defaults give the ratified 8 KB 1rw1r I-SRAM / 8 KB D-SRAM):
//   ISRAM_AW, DSRAM_AW  word-address width of each SRAM (11 = 2048 words).
module soc_fabric #(
    parameter int ISRAM_AW  = 11,
    parameter int DSRAM_AW  = 11
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        i_req_i,
    output logic        i_gnt_o,
    input  logic [31:0] i_addr_i,
    input  logic        i_we_i,
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
    input  logic        uart_rxd_i,
    output logic        uart_txd_o,
    output logic        irq_uart_o,
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
  logic        per_req, per_err;
  logic [31:0] per_addr, per_wdata, per_rdata;
  logic        per_we;
  logic [3:0]  per_be;

  obi_xbar #(
      .ISRAM_AW(ISRAM_AW),
      .DSRAM_AW(DSRAM_AW)
  ) u_xbar (
      .clk_i, .rst_ni,
      .i_req_i, .i_gnt_o, .i_addr_i, .i_we_i,
      .i_rvalid_o, .i_rdata_o, .i_err_o,
      .d_req_i, .d_gnt_o, .d_addr_i, .d_we_i, .d_be_i, .d_wdata_i,
      .d_rvalid_o, .d_rdata_o, .d_err_o,
      .rom_req_o(rom_req), .rom_addr_o(rom_addr), .rom_rdata_i(rom_rdata),
      .isd_req_o(isd_req), .isd_addr_o(isd_addr), .isd_we_o(isd_we),
      .isd_be_o(isd_be), .isd_wdata_o(isd_wdata), .isd_rdata_i(isd_rdata),
      .isi_req_o(isi_req), .isi_addr_o(isi_addr), .isi_rdata_i(isi_rdata),
      .dsr_req_o(dsr_req), .dsr_addr_o(dsr_addr), .dsr_we_o(dsr_we),
      .dsr_be_o(dsr_be), .dsr_wdata_o(dsr_wdata), .dsr_rdata_i(dsr_rdata),
      .per_req_o(per_req), .per_addr_o(per_addr), .per_we_o(per_we), .per_be_o(per_be),
      .per_wdata_o(per_wdata), .per_rdata_i(per_rdata), .per_err_i(per_err)
  );

  boot_rom u_rom (
      .clk_i,
      .req_i  (rom_req),
      .addr_i (rom_addr[11:2]),
      .rdata_o(rom_rdata)
  );

  // The ratified I-SRAM organization (spec/soc.md § Interconnect, row 8a):
  // one 1rw1r wrapper, port 0 for the data manager, port 1 for the fetch; a
  // data-side write and a fetch proceed in the same cycle. The ISRAM_1RW=1
  // single-port option was removed (record 0006) -- it had no macro view, so
  // it could never leave behavioural simulation. The generate block name is
  // load-bearing: flow/soc/pnr_request.json pins the macro instance paths
  // under u_fabric/g_isram_1rw1r.u_isram.
  if (1) begin : g_isram_1rw1r
    soc_sram_i #(
        .AW(ISRAM_AW),
        .USE_PORT1(1'b1)
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

  // D-SRAM: the same wrapper, USE_PORT1=0. The data side is 1rw by the
  // ratified spec; 0004-sram-macro-organization.md item 5 notes no 1rw macro
  // view exists, so the macro build holds the 1rw1r macro here with its
  // port 1 unused.
  soc_sram_i #(
      .AW(DSRAM_AW),
      .USE_PORT1(1'b0)
  ) u_dsram (
      .clk0  (clk_i),
      .csb0  (!dsr_req),
      .web0  (!dsr_we),
      .wmask0(dsr_be),
      .addr0 (dsr_addr[DSRAM_AW+1:2]),
      .din0  (dsr_wdata),
      .dout0 (dsr_rdata),
      .clk1  (clk_i),
      .csb1  (1'b1),
      .addr1 ('0),
      .dout1 ()
  );

  // Peripheral window. Pages: 0 UART, 1 GPIO, 2 timer, the rest error.
  localparam logic [3:0] PageUart = 4'd0, PageGpio = 4'd1, PageTimer = 4'd2;
  wire        uart_sel = per_req && per_addr[15:12] == PageUart;
  wire        gpio_sel = per_req && per_addr[15:12] == PageGpio;
  wire        timer_sel = per_req && per_addr[15:12] == PageTimer;
  logic [31:0] uart_rdata, gpio_rdata, timer_rdata;
  logic        uart_err, gpio_err, timer_err, page_err_q;

  uart u_uart (
      .clk_i, .rst_ni,
      .req_i(uart_sel), .we_i(per_we), .be_i(per_be), .addr_i(per_addr[11:0]),
      .wdata_i(per_wdata), .rdata_o(uart_rdata), .err_o(uart_err),
      .rxd_i(uart_rxd_i), .txd_o(uart_txd_o), .irq_uart_o
  );

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

  // All peripherals register rdata (zero when not addressed) and err, so the
  // response is the OR of the pages plus the error for the unmapped pages.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) page_err_q <= 1'b0;
    else page_err_q <= per_req && !uart_sel && !gpio_sel && !timer_sel;
  end

  assign per_rdata = uart_rdata | gpio_rdata | timer_rdata;
  assign per_err   = page_err_q | uart_err | gpio_err | timer_err;
endmodule
