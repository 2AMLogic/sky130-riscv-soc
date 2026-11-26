// Testbench top for the ACT4 architecture tests (issue #49): rtl/soc_top.sv
// as it ships, plus the two things that suite needs and cannot give the DUT
// from outside otherwise. It adds no logic: every port is wired straight
// through, and the bench (test_archtest.py) drives the soc_top instance
// `u_soc` through the same handles every other soc_top bench uses.
//
//   ISRAM_AW  fv_request.json passes 17: the instruction SRAM elaborates 512 KB
//             deep, a flat RAM behind the fabric that only this testbench has.
//   INIT_FILE the boot ROM's image. The suite's image jumps to the tests' entry
//             point (scripts/build-archtest.sh). The Makefile targets pass a
//             boot ROM image as +rom_hex; klt 0.9.2 (PIN_KLT in
//             scripts/setup-env.sh) cannot pass a plusarg to a cocotb run, and
//             INIT_FILE belongs to the boot_rom instance two levels below the
//             top, which a top-level parameter override does not reach, so it
//             is set here with a hierarchical defparam.
//
// The image path is relative to the simulator's working directory, which klt
// sets to its output directory: verification/sim_build/archtest for
// `make -C verification archtest`, so the path climbs to the repository root.
// The path is a string parameter of boot_rom (rtl/boot_rom.sv), read with
// $readmemh in simulation.
module soc_top_archtest #(
    parameter int ISRAM_AW = 11
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
  soc_top #(
      .ISRAM_AW(ISRAM_AW)
  ) u_soc (
      .clk_i,
      .rst_ni,
      .uart_rxd_i,
      .uart_txd_o,
      .gpio_i,
      .gpio_o,
      .gpio_oe_o,
      .core_sleep_o
  );

  defparam u_soc.u_fabric.u_rom.INIT_FILE = "../../../build/archtest/rom/rom.hex";
endmodule
