// 8-bit GPIO: per-pin direction, 2-flop input synchronisers, one interrupt.
// OBI subordinate with the fabric's fixed timing: the request is accepted in
// the cycle it is made (the fabric grants it at once) and rdata/err are
// registered, valid in the next cycle. Register map: spec/decision-records/
// 0004-peripheral-register-map.md.
module gpio (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        req_i,
    input  logic        we_i,
    input  logic [3:0]  be_i,
    input  logic [11:0] addr_i,   // byte offset inside the 4 KB page
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        err_o,

    input  logic [7:0]  gpio_i,
    output logic [7:0]  gpio_o,
    output logic [7:0]  gpio_oe_o,
    output logic        irq_o
);
  localparam logic [9:0] RegOut = 10'd0, RegDir = 10'd1, RegIn = 10'd2,
                         RegIrqEn = 10'd3, RegIrqPend = 10'd4;

  logic [7:0] out_q, dir_q, irq_en_q, irq_pend_q;
  logic [7:0] sync1_q, sync2_q, prev_q;

  wire [9:0] idx = addr_i[11:2];
  // Byte lane 0 carries the 8-bit registers; other lanes are ignored.
  wire       wr  = req_i && we_i && be_i[0];
  wire [7:0] w   = wdata_i[7:0];
  wire [7:0] rise = sync2_q & ~prev_q;

  assign gpio_o    = out_q;
  assign gpio_oe_o = dir_q;
  assign irq_o     = |(irq_pend_q & irq_en_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      out_q      <= 8'h0;
      dir_q      <= 8'h0;
      irq_en_q   <= 8'h0;
      irq_pend_q <= 8'h0;
      sync1_q    <= 8'h0;
      sync2_q    <= 8'h0;
      prev_q     <= 8'h0;
      rdata_o    <= 32'h0;
      err_o      <= 1'b0;
    end else begin
      sync1_q <= gpio_i;
      sync2_q <= sync1_q;
      prev_q  <= sync2_q;
      // A new edge wins over a same-cycle write-1-to-clear.
      irq_pend_q <= (wr && idx == RegIrqPend ? irq_pend_q & ~w : irq_pend_q) | rise;
      if (wr) begin
        case (idx)
          RegOut:   out_q    <= w;
          RegDir:   dir_q    <= w;
          RegIrqEn: irq_en_q <= w;
          default:  ;
        endcase
      end

      rdata_o <= 32'h0;
      if (req_i && !we_i) begin
        case (idx)
          RegOut:     rdata_o <= {24'h0, out_q};
          RegDir:     rdata_o <= {24'h0, dir_q};
          RegIn:      rdata_o <= {24'h0, sync2_q};
          RegIrqEn:   rdata_o <= {24'h0, irq_en_q};
          RegIrqPend: rdata_o <= {24'h0, irq_pend_q};
          default:    ;
        endcase
      end
      err_o <= req_i && idx > RegIrqPend;
    end
  end
endmodule
