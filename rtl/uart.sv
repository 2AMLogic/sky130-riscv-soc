// UART, 8N1, TX and RX, programmable baud divisor, one level interrupt.
// One-byte TX holding register + TX shifter, one-byte RX holding register +
// RX shifter; no FIFO. OBI subordinate with the fabric's fixed timing: the
// request is accepted in the cycle it is made and rdata/err are registered,
// valid in the next cycle. Register map: spec/decision-records/
// 0005-uart-register-map.md.
module uart (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        req_i,
    input  logic        we_i,
    input  logic [3:0]  be_i,
    input  logic [11:0] addr_i,   // byte offset inside the 4 KB page
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        err_o,

    input  logic        rxd_i,
    output logic        txd_o,
    output logic        irq_uart_o
);
  localparam logic [9:0]  RegData = 10'd0, RegStatus = 10'd1, RegCtrl = 10'd2, RegDiv = 10'd3;
  // Bit period is DIV + 1 clocks; the reset value gives 434 clocks (50 MHz / 115200).
  localparam logic [15:0] DivReset = 16'd433;

  logic [15:0] div_q;
  logic        tx_ie_q, rx_ie_q;

  // TX
  logic [7:0] tx_hold_q;
  logic       tx_full_q;      // holding register occupied (STATUS.TX_BUSY)
  logic       tx_active_q;    // shifter running
  logic [9:0] tx_sh_q;        // {stop, data[7:0], start}; bit 0 is on the wire
  logic [3:0] tx_left_q;      // bit periods left in the frame, including the current one
  logic [15:0] tx_cnt_q;

  // RX
  logic [1:0] rxs_q;          // 2-flop input synchroniser, reset to idle (high)
  logic       rx_active_q, rx_started_q, rx_armed_q;
  logic [7:0] rx_sh_q, rx_data_q;
  logic [3:0] rx_left_q;      // data bits still to sample
  logic [15:0] rx_cnt_q;
  logic       rx_valid_q, ovr_q, fe_q;

  wire [9:0] idx  = addr_i[11:2];
  wire       wr   = req_i && we_i;
  wire       rd   = req_i && !we_i;
  wire       wr0  = wr && be_i[0];
  wire       rd_data = rd && idx == RegData;
  wire       rxd  = rxs_q[1];

  assign irq_uart_o = (tx_ie_q && !tx_full_q) || (rx_ie_q && rx_valid_q);

  wire tx_tick     = tx_active_q && tx_cnt_q == 16'h0;
  wire tx_frame_end = tx_tick && tx_left_q == 4'd1;
  wire tx_start    = tx_full_q && (!tx_active_q || tx_frame_end);

  // A byte write while the holding register is full is dropped.
  wire tx_wr = wr0 && idx == RegData && !tx_full_q;

  wire rx_tick = rx_active_q && rx_cnt_q == 16'h0;
  wire rx_done = rx_tick && rx_started_q && rx_left_q == 4'd0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      div_q        <= DivReset;
      tx_ie_q      <= 1'b0;
      rx_ie_q      <= 1'b0;
      tx_hold_q    <= 8'h0;
      tx_full_q    <= 1'b0;
      tx_active_q  <= 1'b0;
      tx_sh_q      <= 10'h3FF;
      tx_left_q    <= 4'd0;
      tx_cnt_q     <= 16'h0;
      txd_o        <= 1'b1;
      rxs_q        <= 2'b11;
      rx_active_q  <= 1'b0;
      rx_started_q <= 1'b0;
      rx_armed_q   <= 1'b1;
      rx_sh_q      <= 8'h0;
      rx_data_q    <= 8'h0;
      rx_left_q    <= 4'd0;
      rx_cnt_q     <= 16'h0;
      rx_valid_q   <= 1'b0;
      ovr_q        <= 1'b0;
      fe_q         <= 1'b0;
      rdata_o      <= 32'h0;
      err_o        <= 1'b0;
    end else begin
      // ---- register writes ----
      if (wr0) begin
        case (idx)
          RegStatus: begin
            if (wdata_i[2]) ovr_q <= 1'b0;
            if (wdata_i[3]) fe_q  <= 1'b0;
          end
          RegCtrl: begin
            tx_ie_q <= wdata_i[0];
            rx_ie_q <= wdata_i[1];
          end
          RegDiv: div_q[7:0] <= wdata_i[7:0];
          default: ;
        endcase
      end
      if (wr && be_i[1] && idx == RegDiv) div_q[15:8] <= wdata_i[15:8];

      // ---- TX ----
      if (tx_wr) begin
        tx_hold_q <= wdata_i[7:0];
        tx_full_q <= 1'b1;
      end
      if (tx_start) begin
        tx_sh_q     <= {1'b1, tx_wr ? wdata_i[7:0] : tx_hold_q, 1'b0};
        txd_o       <= 1'b0;
        tx_active_q <= 1'b1;
        tx_left_q   <= 4'd10;
        tx_cnt_q    <= div_q;
        // the holding register is free again unless a write refills it now
        tx_full_q   <= tx_wr;
      end else if (tx_tick) begin
        tx_cnt_q <= div_q;
        if (tx_frame_end) begin
          tx_active_q <= 1'b0;
        end else begin
          tx_sh_q   <= {1'b1, tx_sh_q[9:1]};
          txd_o     <= tx_sh_q[1];
          tx_left_q <= tx_left_q - 4'd1;
        end
      end else if (tx_active_q) begin
        tx_cnt_q <= tx_cnt_q - 16'd1;
      end

      // ---- RX ----
      rxs_q <= {rxs_q[0], rxd_i};
      if (rxd) rx_armed_q <= 1'b1;
      if (!rx_active_q) begin
        // a falling edge or a low line after the stop bit sampled high starts a frame
        if (!rxd && rx_armed_q) begin
          rx_active_q  <= 1'b1;
          rx_started_q <= 1'b0;
          rx_cnt_q     <= div_q >> 1;   // to the middle of the start bit
        end
      end else if (!rx_tick) begin
        rx_cnt_q <= rx_cnt_q - 16'd1;
      end else if (!rx_started_q) begin
        if (rxd) begin
          rx_active_q <= 1'b0;          // start-bit glitch
        end else begin
          rx_started_q <= 1'b1;
          rx_left_q    <= 4'd8;
          rx_cnt_q     <= div_q;
        end
      end else if (rx_left_q != 4'd0) begin
        rx_sh_q   <= {rxd, rx_sh_q[7:1]};   // LSB first
        rx_left_q <= rx_left_q - 4'd1;
        rx_cnt_q  <= div_q;
      end else begin
        // stop-bit sample point
        rx_active_q <= 1'b0;
        if (!rxd) begin
          fe_q       <= 1'b1;              // frame dropped; wait for the line to go high
          rx_armed_q <= 1'b0;
        end
      end

      // A byte lands in the holding register, or is dropped (overrun) if the
      // previous byte is still unread. A read in the same cycle frees it.
      if (rx_done && rxd) begin
        if (rx_valid_q && !rd_data) begin
          ovr_q <= 1'b1;
        end else begin
          rx_data_q  <= rx_sh_q;
          rx_valid_q <= 1'b1;
        end
      end else if (rd_data) begin
        rx_valid_q <= 1'b0;
      end

      // ---- read data ----
      rdata_o <= 32'h0;
      if (rd) begin
        case (idx)
          RegData:   rdata_o <= {24'h0, rx_data_q};
          RegStatus: rdata_o <= {27'h0, tx_active_q, fe_q, ovr_q, rx_valid_q, tx_full_q};
          RegCtrl:   rdata_o <= {30'h0, rx_ie_q, tx_ie_q};
          RegDiv:    rdata_o <= {16'h0, div_q};
          default:   ;
        endcase
      end
      err_o <= req_i && idx > RegDiv;
    end
  end
endmodule
