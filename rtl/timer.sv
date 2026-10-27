// RISC-V machine-timer style 64-bit mtime/mtimecmp. mtime increments every
// clk_i; irq_o = mtime >= mtimecmp (unsigned). OBI subordinate with the
// fabric's fixed timing: accepted in the request cycle, rdata/err registered
// and valid in the next cycle. Register map and the hi/lo write-ordering rule:
// spec/decision-records/0004-peripheral-register-map.md.
module timer (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        req_i,
    input  logic        we_i,
    input  logic [3:0]  be_i,
    input  logic [11:0] addr_i,   // byte offset inside the 4 KB page
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        err_o,

    output logic        irq_o
);
  localparam logic [9:0] RegTimeLo = 10'd0, RegTimeHi = 10'd1,
                         RegCmpLo = 10'd2, RegCmpHi = 10'd3;

  logic [63:0] mtime_q, mtimecmp_q;
  logic [63:0] mtime_n;

  wire [9:0] idx = addr_i[11:2];
  wire       wr  = req_i && we_i;

  assign irq_o = mtime_q >= mtimecmp_q;

  function automatic logic [31:0] merge(input logic [31:0] base, input logic [3:0] be);
    logic [31:0] r;
    r = base;
    for (int b = 0; b < 4; b++) if (be[b]) r[8*b +: 8] = wdata_i[8*b +: 8];
    return r;
  endfunction

  // The increment applies in every cycle, including a write cycle: written
  // byte lanes take the write data, all other lanes take the incremented value.
  always_comb begin
    mtime_n = mtime_q + 64'd1;
    if (wr && idx == RegTimeLo) mtime_n[31:0]  = merge(mtime_n[31:0], be_i);
    if (wr && idx == RegTimeHi) mtime_n[63:32] = merge(mtime_n[63:32], be_i);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mtime_q    <= 64'h0;
      mtimecmp_q <= 64'hFFFF_FFFF_FFFF_FFFF;  // no interrupt out of reset
      rdata_o    <= 32'h0;
      err_o      <= 1'b0;
    end else begin
      mtime_q <= mtime_n;
      if (wr && idx == RegCmpLo) mtimecmp_q[31:0]  <= merge(mtimecmp_q[31:0], be_i);
      if (wr && idx == RegCmpHi) mtimecmp_q[63:32] <= merge(mtimecmp_q[63:32], be_i);

      rdata_o <= 32'h0;
      if (req_i && !we_i) begin
        case (idx)
          RegTimeLo: rdata_o <= mtime_q[31:0];
          RegTimeHi: rdata_o <= mtime_q[63:32];
          RegCmpLo:  rdata_o <= mtimecmp_q[31:0];
          RegCmpHi:  rdata_o <= mtimecmp_q[63:32];
          default:   ;
        endcase
      end
      err_o <= req_i && idx > RegCmpHi;
    end
  end
endmodule
