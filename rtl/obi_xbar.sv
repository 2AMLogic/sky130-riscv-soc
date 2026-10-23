// OBI crossbar: 2 managers (instruction i_*, data d_*), subordinates boot ROM,
// instruction SRAM (two ports), data SRAM, peripheral window (spec/soc.md
// § Interconnect, § Memory map).
//
// Reachability: the instruction manager reads boot ROM and I-SRAM only; the
// data manager reaches all four. Everything else gets an OBI error response:
// unmapped addresses, instruction-manager writes or accesses to D-SRAM and the
// peripheral window, and data-manager writes to the boot ROM.
// Arbitration: I-SRAM has one port per manager and D-SRAM/peripherals have one
// manager, so only the boot ROM is shared; there the instruction manager has
// fixed priority and the data manager is not granted while it wants the ROM.
// Timing contract: every subordinate grants a request and responds exactly one
// cycle after the grant, so responses return in order with no id tracking.
// Subordinates raise no error except the peripheral window (periph_err_i).
module obi_xbar (
    input  logic        clk_i,
    input  logic        rst_ni,

    // instruction manager
    input  logic        i_req_i,
    output logic        i_gnt_o,
    input  logic [31:0] i_addr_i,
    input  logic        i_we_i,
    input  logic [3:0]  i_be_i,
    input  logic [31:0] i_wdata_i,
    output logic        i_rvalid_o,
    output logic [31:0] i_rdata_o,
    output logic        i_err_o,

    // data manager
    input  logic        d_req_i,
    output logic        d_gnt_o,
    input  logic [31:0] d_addr_i,
    input  logic        d_we_i,
    input  logic [3:0]  d_be_i,
    input  logic [31:0] d_wdata_i,
    output logic        d_rvalid_o,
    output logic [31:0] d_rdata_o,
    output logic        d_err_o,

    // boot ROM (read-only; shared)
    output logic        rom_req_o,
    input  logic        rom_gnt_i,
    output logic [31:0] rom_addr_o,
    input  logic [31:0] rom_rdata_i,

    // instruction SRAM port 0 (data manager: read/write)
    output logic        isd_req_o,
    input  logic        isd_gnt_i,
    output logic [31:0] isd_addr_o,
    output logic        isd_we_o,
    output logic [3:0]  isd_be_o,
    output logic [31:0] isd_wdata_o,
    input  logic [31:0] isd_rdata_i,

    // instruction SRAM port 1 (instruction manager: read)
    output logic        isi_req_o,
    input  logic        isi_gnt_i,
    output logic [31:0] isi_addr_o,
    input  logic [31:0] isi_rdata_i,

    // data SRAM (data manager)
    output logic        dsr_req_o,
    input  logic        dsr_gnt_i,
    output logic [31:0] dsr_addr_o,
    output logic        dsr_we_o,
    output logic [3:0]  dsr_be_o,
    output logic [31:0] dsr_wdata_o,
    input  logic [31:0] dsr_rdata_i,

    // peripheral window (data manager)
    output logic        per_req_o,
    input  logic        per_gnt_i,
    output logic [31:0] per_addr_o,
    output logic        per_we_o,
    output logic [3:0]  per_be_o,
    output logic [31:0] per_wdata_o,
    input  logic [31:0] per_rdata_i,
    input  logic        per_err_i
);
  localparam logic [2:0] T_ROM = 3'd0;
  localparam logic [2:0] T_ISR = 3'd1;
  localparam logic [2:0] T_DSR = 3'd2;
  localparam logic [2:0] T_PER = 3'd3;
  localparam logic [2:0] T_ERR = 3'd4;

  // Raw address decode per the memory map.
  function automatic logic [2:0] decode(input logic [31:0] a);
    if (a[31:12] == 20'h00000) return T_ROM;
    else if (a[31:13] == 19'h08000) return T_ISR;  // 0x1000_0000, 8 KB
    else if (a[31:13] == 19'h10000) return T_DSR;  // 0x2000_0000, 8 KB
    else if (a[31:16] == 16'h4000) return T_PER;  // 0x4000_0000-0x4000_FFFF
    else return T_ERR;
  endfunction

  // Per-manager reachability: forbidden targets go to the error responder.
  logic [2:0] i_tgt, d_tgt;
  always_comb begin
    i_tgt = decode(i_addr_i);
    if (i_we_i || i_tgt == T_DSR || i_tgt == T_PER) i_tgt = T_ERR;
    d_tgt = decode(d_addr_i);
    if (d_tgt == T_ROM && d_we_i) d_tgt = T_ERR;
  end

  logic i_to_rom, d_to_rom;
  assign i_to_rom = i_req_i && i_tgt == T_ROM;
  assign d_to_rom = d_req_i && d_tgt == T_ROM;

  // Boot ROM: instruction manager wins.
  assign rom_req_o  = i_to_rom || d_to_rom;
  assign rom_addr_o = i_to_rom ? i_addr_i : d_addr_i;

  // Instruction SRAM: port 1 for fetch, port 0 for the data manager.
  assign isi_req_o  = i_req_i && i_tgt == T_ISR;
  assign isi_addr_o = i_addr_i;
  assign isd_req_o   = d_req_i && d_tgt == T_ISR;
  assign isd_addr_o  = d_addr_i;
  assign isd_we_o    = d_we_i;
  assign isd_be_o    = d_be_i;
  assign isd_wdata_o = d_wdata_i;

  assign dsr_req_o   = d_req_i && d_tgt == T_DSR;
  assign dsr_addr_o  = d_addr_i;
  assign dsr_we_o    = d_we_i;
  assign dsr_be_o    = d_be_i;
  assign dsr_wdata_o = d_wdata_i;

  assign per_req_o   = d_req_i && d_tgt == T_PER;
  assign per_addr_o  = d_addr_i;
  assign per_we_o    = d_we_i;
  assign per_be_o    = d_be_i;
  assign per_wdata_o = d_wdata_i;

  // Error responders, one per manager.
  logic i_er_gnt, d_er_gnt, i_er_err, d_er_err;
  obi_err_resp u_i_err (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .req_i   (i_req_i && i_tgt == T_ERR),
      .gnt_o   (i_er_gnt),
      .rvalid_o(),
      .err_o   (i_er_err)
  );
  obi_err_resp u_d_err (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .req_i   (d_req_i && d_tgt == T_ERR),
      .gnt_o   (d_er_gnt),
      .rvalid_o(),
      .err_o   (d_er_err)
  );

  // Grants.
  always_comb begin
    case (i_tgt)
      T_ROM:   i_gnt_o = rom_gnt_i;
      T_ISR:   i_gnt_o = isi_gnt_i;
      default: i_gnt_o = i_er_gnt;
    endcase
    case (d_tgt)
      T_ROM:   d_gnt_o = rom_gnt_i && !i_to_rom;
      T_ISR:   d_gnt_o = isd_gnt_i;
      T_DSR:   d_gnt_o = dsr_gnt_i;
      T_PER:   d_gnt_o = per_gnt_i;
      default: d_gnt_o = d_er_gnt;
    endcase
  end

  // Response routing: remember the target of the access accepted last cycle.
  logic       i_pend_q, d_pend_q;
  logic [2:0] i_sel_q, d_sel_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      i_pend_q <= 1'b0;
      d_pend_q <= 1'b0;
      i_sel_q  <= T_ERR;
      d_sel_q  <= T_ERR;
    end else begin
      i_pend_q <= i_req_i && i_gnt_o;
      d_pend_q <= d_req_i && d_gnt_o;
      if (i_req_i && i_gnt_o) i_sel_q <= i_tgt;
      if (d_req_i && d_gnt_o) d_sel_q <= d_tgt;
    end
  end

  assign i_rvalid_o = i_pend_q;
  assign d_rvalid_o = d_pend_q;
  assign i_err_o    = i_pend_q && i_sel_q == T_ERR && i_er_err;
  assign d_err_o    = d_pend_q && ((d_sel_q == T_ERR && d_er_err) || (d_sel_q == T_PER && per_err_i));

  always_comb begin
    case (i_sel_q)
      T_ROM:   i_rdata_o = rom_rdata_i;
      T_ISR:   i_rdata_o = isi_rdata_i;
      default: i_rdata_o = 32'h0;
    endcase
    case (d_sel_q)
      T_ROM:   d_rdata_o = rom_rdata_i;
      T_ISR:   d_rdata_o = isd_rdata_i;
      T_DSR:   d_rdata_o = dsr_rdata_i;
      T_PER:   d_rdata_o = per_rdata_i;
      default: d_rdata_o = 32'h0;
    endcase
  end
endmodule
