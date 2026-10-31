// SoC top: CVE2 (converted by scripts/convert-cve2.sh, never edited) wired to
// the memory fabric, with the reset synchroniser. The peripheral window inside
// soc_fabric holds GPIO and the machine timer; the UART page still answers
// with an OBI error.
// Core configuration per spec/soc.md: RV32IMC, RV32MFast, debug tied off,
// boot_addr_i at the boot ROM base (the reset vector).
module soc_top #(
    parameter int ISRAM_AW  = 11,
    parameter int DSRAM_AW  = 11,
    parameter bit ISRAM_1RW = 1'b0
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic uart_rxd_i,
    output logic uart_txd_o,
    input  logic [7:0] gpio_i,
    output logic [7:0] gpio_o,
    output logic [7:0] gpio_oe_o,
    output logic core_sleep_o
);
  localparam logic [31:0] BootAddr = 32'h0000_0000;

  logic        rst_n;
  logic        irq_timer, irq_gpio, irq_uart;

  logic        instr_req, instr_gnt, instr_rvalid, instr_err;
  logic [31:0] instr_addr, instr_rdata;

  logic        data_req, data_gnt, data_rvalid, data_we, data_err;
  logic [3:0]  data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;

  rst_sync u_rst_sync (
      .clk_i,
      .rst_ni,
      .rst_no(rst_n)
  );

  cve2_top #(
      .MHPMCounterNum  (10),
      .MHPMCounterWidth(40),
      .RV32E           (1'b0),
      .RV32M           (2),  // RV32MFast
      .XInterface      (1'b0)
  ) u_core (
      .clk_i,
      .rst_ni             (rst_n),
      .test_en_i          (1'b0),
      .ram_cfg_i          (10'h0),
      .hart_id_i          (32'h0),
      .boot_addr_i        (BootAddr),
      .instr_req_o        (instr_req),
      .instr_gnt_i        (instr_gnt),
      .instr_rvalid_i     (instr_rvalid),
      .instr_addr_o       (instr_addr),
      .instr_rdata_i      (instr_rdata),
      .instr_err_i        (instr_err),
      .data_req_o         (data_req),
      .data_gnt_i         (data_gnt),
      .data_rvalid_i      (data_rvalid),
      .data_we_o          (data_we),
      .data_be_o          (data_be),
      .data_addr_o        (data_addr),
      .data_wdata_o       (data_wdata),
      .data_rdata_i       (data_rdata),
      .data_err_i         (data_err),
      .x_issue_valid_o    (),
      .x_issue_ready_i    (1'b0),
      .x_issue_req_o      (),
      .x_issue_resp_i     ('0),
      .x_register_o       (),
      .x_commit_valid_o   (),
      .x_commit_o         (),
      .x_result_valid_i   (1'b0),
      .x_result_ready_o   (),
      .x_result_i         ('0),
      .irq_software_i     (1'b0),
      .irq_timer_i        (irq_timer),
      .irq_external_i     (1'b0),
      .irq_fast_i         ({14'h0, irq_gpio, irq_uart}),  // [0] UART, [1] GPIO
      .irq_nm_i           (1'b0),
      .debug_req_i        (1'b0),
      .debug_halted_o     (),
      .dm_halt_addr_i     (32'h0),
      .dm_exception_addr_i(32'h0),
      .crash_dump_o       (),
      .fetch_enable_i     (1'b1),
      .core_sleep_o
  );

  soc_fabric #(
      .ISRAM_AW (ISRAM_AW),
      .DSRAM_AW (DSRAM_AW),
      .ISRAM_1RW(ISRAM_1RW)
  ) u_fabric (
      .clk_i,
      .rst_ni    (rst_n),
      .i_req_i   (instr_req),
      .i_gnt_o   (instr_gnt),
      .i_addr_i  (instr_addr),
      .i_we_i    (1'b0),
      .i_be_i    (4'hF),
      .i_wdata_i (32'h0),
      .i_rvalid_o(instr_rvalid),
      .i_rdata_o (instr_rdata),
      .i_err_o   (instr_err),
      .d_req_i   (data_req),
      .d_gnt_o   (data_gnt),
      .d_addr_i  (data_addr),
      .d_we_i    (data_we),
      .d_be_i    (data_be),
      .d_wdata_i (data_wdata),
      .d_rvalid_o(data_rvalid),
      .d_rdata_o (data_rdata),
      .d_err_o   (data_err),
      .gpio_i,
      .gpio_o,
      .gpio_oe_o,
      .uart_rxd_i,
      .uart_txd_o,
      .irq_uart_o (irq_uart),
      .irq_gpio_o (irq_gpio),
      .irq_timer_o(irq_timer)
  );
endmodule
