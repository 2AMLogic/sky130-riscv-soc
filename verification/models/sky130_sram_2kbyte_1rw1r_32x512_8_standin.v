// Icarus-simulable stand-in for the sky130_sram_2kbyte_1rw1r_32x512_8 macro, used
// ONLY by the post-synthesis (gate-level) regression, `make -C verification
// soc-gate`. The pinned macro model (efabless/sky130_sram_macros, reuse.lock.json)
// does not elaborate in Icarus 13.0: its $display lines index `mem` before the
// declaration. This file reproduces that model's behaviour (posedge capture of the
// control inputs, write at the following negedge, read at negedge with DELAY,
// output X T_HOLD after the next posedge). It is a model of the macro, not the
// macro: that substitution is disclosed in the record.
//
// `verification/tools/check_sram_standin.py` fetches the pinned model, verifies its
// sha256 against reuse.lock.json, and fails unless this file differs from it only
// in the ways listed below -- each one an entry in that script's ALLOWED_EDITS, with
// the tag quoted here. The list is exhaustive: any other difference, in either file,
// fails the check. Comment and whitespace differences are normalised away.
//
//  1. dropped `$display`: the three VERBOSE-gated Reading/Writing traces, each with
//     its `if (...)` guard, because the guard is not valid without its body. These
//     are the lines that index `mem` before its declaration, so they are the reason
//     this file exists. Traces drive no signal, so dropping them changes no
//     behaviour -- only what the transcript says.
//  2. dropped the collision `WARNING`: the un-gated
//     "Writing and reading addr0 and addr1 simultaneously!" $display in the
//     `posedge clk1` block, with its guard, for the same reason. This one is a
//     diagnostic the gate run therefore does NOT get: a same-address port-0
//     write against a port-1 read goes unreported here. It drives no signal, so
//     the simulated behaviour is unchanged; the lost coverage is the warning
//     itself. The RTL regression exercises the same fabric with the real
//     rtl/soc_sram_*.sv.
//  3. removed `VERBOSE`: `parameter VERBOSE = 1 ;`, whose only uses were the guards
//     dropped in 1. Checked on netlist/soc_top_synth.v @ 4d18ba5: the macro
//     instances use named port connections only, with no parameter override and no
//     defparam, so nothing in the netlist reads it.
//  4. removed `USE_POWER_PINS` blocks: the `vccd1, vssd1,` port-list entries and the
//     `inout vccd1; inout vssd1;` declarations. soc-gate compiles with
//     `-DFUNCTIONAL -DUNIT_DELAY=#0` and never defines USE_POWER_PINS, and the
//     netlist's macro instances connect neither pin, so the pinned model would not
//     have these ports in this run either. Power connectivity is a layout and LVS
//     concern, not a simulation one.
//  5. added `timescale`: `1ns/1ps`, matching the PDK sky130_fd_sc_hd cell models
//     (`timescale 1ns / 1ps`), so DELAY and T_HOLD mean the same thing here as in
//     the cells. The pinned model has no directive and would otherwise inherit
//     whichever timescale precedes it in compile order.
//  6. `mem` declared first: the declaration moves from after the `posedge clk1`
//     block to before the first `always`. This is what Icarus 13.0 requires.
//  7. `integer i;` and the zeroing `initial`: contents start at 0, where the macro's
//     are undefined, because firmware does not rely on uninitialised SRAM and the
//     RTL regression zeroes it the same way.
`timescale 1ns/1ps
module sky130_sram_2kbyte_1rw1r_32x512_8(
    clk0,csb0,web0,wmask0,addr0,din0,dout0,
    clk1,csb1,addr1,dout1
  );

  parameter NUM_WMASKS = 4 ;
  parameter DATA_WIDTH = 32 ;
  parameter ADDR_WIDTH = 9 ;
  parameter RAM_DEPTH = 1 << ADDR_WIDTH;
  parameter DELAY = 3 ;
  parameter T_HOLD = 1 ;

  input  clk0;
  input  csb0;
  input  web0;
  input [NUM_WMASKS-1:0]  wmask0;
  input [ADDR_WIDTH-1:0]  addr0;
  input [DATA_WIDTH-1:0]  din0;
  output [DATA_WIDTH-1:0] dout0;
  input  clk1;
  input  csb1;
  input [ADDR_WIDTH-1:0]  addr1;
  output [DATA_WIDTH-1:0] dout1;

  reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];
  integer i;
  initial for (i = 0; i < RAM_DEPTH; i = i + 1) mem[i] = {DATA_WIDTH{1'b0}};

  reg  csb0_reg;
  reg  web0_reg;
  reg [NUM_WMASKS-1:0]  wmask0_reg;
  reg [ADDR_WIDTH-1:0]  addr0_reg;
  reg [DATA_WIDTH-1:0]  din0_reg;
  reg [DATA_WIDTH-1:0]  dout0;

  always @(posedge clk0)
  begin
    csb0_reg = csb0;
    web0_reg = web0;
    wmask0_reg = wmask0;
    addr0_reg = addr0;
    din0_reg = din0;
    #(T_HOLD) dout0 = 32'bx;
  end

  reg  csb1_reg;
  reg [ADDR_WIDTH-1:0]  addr1_reg;
  reg [DATA_WIDTH-1:0]  dout1;

  always @(posedge clk1)
  begin
    csb1_reg = csb1;
    addr1_reg = addr1;
    #(T_HOLD) dout1 = 32'bx;
  end

  always @ (negedge clk0)
  begin : MEM_WRITE0
    if ( !csb0_reg && !web0_reg ) begin
        if (wmask0_reg[0])
                mem[addr0_reg][7:0] = din0_reg[7:0];
        if (wmask0_reg[1])
                mem[addr0_reg][15:8] = din0_reg[15:8];
        if (wmask0_reg[2])
                mem[addr0_reg][23:16] = din0_reg[23:16];
        if (wmask0_reg[3])
                mem[addr0_reg][31:24] = din0_reg[31:24];
    end
  end

  always @ (negedge clk0)
  begin : MEM_READ0
    if (!csb0_reg && web0_reg)
       dout0 <= #(DELAY) mem[addr0_reg];
  end

  always @ (negedge clk1)
  begin : MEM_READ1
    if (!csb1_reg)
       dout1 <= #(DELAY) mem[addr1_reg];
  end

endmodule
