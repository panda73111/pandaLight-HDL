//////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2010 Xilinx, Inc.
// This design is confidential and proprietary of Xilinx, All Rights Reserved.
//////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /   Vendor:        Xilinx
// \   \   \/    Version:       1.0.0
//  \   \        Filename:      dvi_demo.v
//  /   /        Date Created:  Feb. 2010
// /___/   /\    Last Modified: Feb. 2010
// \   \  /  \
//  \___\/\___\
//
// Devices:   Spartan-6  FPGA
// Purpose:   DVI Pass Through Top Module Based On XLAB Atlys Board
// Contact:   
// Reference: None
//
// Revision History:
//   Rev 1.0.0 - (Bob Feng) First created Feb. 2010
//
//////////////////////////////////////////////////////////////////////////////
//
// LIMITED WARRANTY AND DISCLAIMER. These designs are provided to you "as is".
// Xilinx and its licensors make and you receive no warranties or conditions,
// express, implied, statutory or otherwise, and Xilinx specifically disclaims
// any implied warranties of merchantability, non-infringement, or fitness for
// a particular purpose. Xilinx does not warrant that the functions contained
// in these designs will meet your requirements, or that the operation of
// these designs will be uninterrupted or error free, or that defects in the
// designs will be corrected. Furthermore, Xilinx does not warrant or make any
// representations regarding use or the results of the use of the designs in
// terms of correctness, accuracy, reliability, or otherwise.
//
// LIMITATION OF LIABILITY. In no event will Xilinx or its licensors be liable
// for any loss of data, lost profits, cost or procurement of substitute goods
// or services, or for any special, incidental, consequential, or indirect
// damages arising from the use or operation of the designs or accompanying
// documentation, however caused and on any theory of liability. This
// limitation will apply even if Xilinx has been advised of the possibility
// of such damage. This limitation shall apply not-withstanding the failure
// of the essential purpose of any limited remedies herein.
//
//////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2010 Xilinx, Inc.
// This design is confidential and proprietary of Xilinx, All Rights Reserved.
//////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

//`define DIRECTPASS

module dvi_demo (
  input wire        rstbtn_n,    //The pink reset button
  input wire        clk100,      //100 MHz osicallator
  input wire [3:0]  RX0_TMDS,
  input wire [3:0]  RX0_TMDSB,
  input wire [3:0]  RX1_TMDS,
  input wire [3:0]  RX1_TMDSB,

  output wire [3:0] TX0_TMDS,
  output wire [3:0] TX0_TMDSB,
  output wire [3:0] TX1_TMDS,
  output wire [3:0] TX1_TMDSB,

  input  wire SW,

  output wire [7:0] LED
);

  ////////////////////////////////////////////////////
  // 25 MHz and switch debouncers
  ////////////////////////////////////////////////////
  wire clk25, clk25m;

  BUFIO2 #(.DIVIDE_BYPASS("FALSE"), .DIVIDE(5))
  sysclk_div (.DIVCLK(clk25m), .IOCLK(), .SERDESSTROBE(), .I(clk100));

  BUFG clk25_buf (.I(clk25m), .O(clk25));

  wire sws;

  synchro #(.INITIALIZE("LOGIC0"))
  synchro_sws_0 (.async(SW),.sync(sws),.clk(clk25));

  wire select = sws;

  reg select_q = 2'b00;
  reg switch = 2'b00;
  always @ (posedge clk25) begin
    select_q <= select;

    switch = select ^ select_q;
  end
  
  wire rx_pllclk1, rx_pllclk2;
  //
  // Pixel Rate clock buffer
  //
  BUFG pclkbufg (.I(rx_pllclk1), .O(rx_pclk));

  //////////////////////////////////////////////////////////////////
  // 2x pclk is going to be used to drive IOSERDES2 DIVCLK
  //////////////////////////////////////////////////////////////////
  BUFG pclkx2bufg (.I(rx_pllclk2), .O(rx_pclkx2));
  
  //
  // Send TMDS clock to a differential buffer and then a BUFIO2
  // This is a required path in Spartan-6 feed a PLL CLKIN
  //
  IBUFDS  #(.IOSTANDARD("TMDS_33"), .DIFF_TERM("FALSE")
  ) ibuf_rx0_clk (.I(RX0_TMDS[3]), .IB(RX0_TMDSB[3]), .O(rx0_clkint));
  
  IBUFDS  #(.IOSTANDARD("TMDS_33"), .DIFF_TERM("FALSE")
  ) ibuf_rx1_clk (.I(RX1_TMDS[3]), .IB(RX1_TMDSB[3]), .O(rx1_clkint));
 
  wire rx0_clk, rx1_clk;

  BUFIO2 #(.DIVIDE_BYPASS("TRUE"), .DIVIDE(1))
  bufio_rx0_tmdsclk (.DIVCLK(rx0_clk), .IOCLK(), .SERDESSTROBE(), .I(rx0_clkint));
 
  BUFIO2 #(.DIVIDE_BYPASS("TRUE"), .DIVIDE(1))
  bufio_rx1_tmdsclk (.DIVCLK(rx1_clk), .IOCLK(), .SERDESSTROBE(), .I(rx1_clkint));
  
  BUFGMUX rx_bufg_clk (.S(select), .I1(rx1_clk), .I0(rx0_clk), .O(rx_clk));
  
    //////////////////////////////////////////////////////////////////
  // 10x pclk is used to drive IOCLK network so a bit rate reference
  // can be used by IOSERDES2
  //////////////////////////////////////////////////////////////////

  //
  // PLL is used to generate three clocks:
  // 1. pclk:    same rate as TMDS clock
  // 2. pclkx2:  double rate of pclk used for 5:10 soft gear box and ISERDES DIVCLK
  // 3. pclkx10: 10x rate of pclk used as IO clock
  //
  wire rx_clkfbout;
  wire rx_pllclk0;
  wire rx_pll_lckd;
  wire pllclk0;        // send pllclk0 out so it can be fed into a different BUFPLL
  PLL_BASE # (
    .CLKIN_PERIOD(10),
    .CLKFBOUT_MULT(10), //set VCO to 10x of CLKIN
    .CLKOUT0_DIVIDE(1),
    .CLKOUT1_DIVIDE(10),
    .CLKOUT2_DIVIDE(5),
    .COMPENSATION("INTERNAL")
  ) PLL_ISERDES (
    .CLKFBOUT(rx_clkfbout),
    .CLKOUT0(rx_pllclk0),
    .CLKOUT1(rx_pllclk1),
    .CLKOUT2(rx_pllclk2),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .LOCKED(rx_pll_lckd),
    .CLKFBIN(rx_clkfbout),
    .CLKIN(rx_clk),
    .RST(~rstbtn_n)
  );
  
  wire bufpll_lock;
  BUFPLL #(.DIVIDE(5)) ioclk_buf (.PLLIN(rx_pllclk0), .GCLK(rx_pclkx2), .LOCKED(rx_pll_lckd),
           .IOCLK(rx_pclkx10), .SERDESSTROBE(rx_serdesstrobe), .LOCK(rx_bufpll_lock));
  
  /////////////////////////
  //
  // Input Port 0
  //
  /////////////////////////
  wire rx0_reset =  ~rx_bufpll_lock;
  wire rx0_plllckd;
  wire rx0_serdesstrobe;
  wire rx0_hsync;          // hsync data
  wire rx0_vsync;          // vsync data
  wire rx0_de;             // data enable
  wire rx0_psalgnerr;      // channel phase alignment error
  wire [7:0] rx0_red;      // pixel data out
  wire [7:0] rx0_green;    // pixel data out
  wire [7:0] rx0_blue;     // pixel data out
  wire [29:0] rx0_sdata;
  wire rx0_blue_vld;
  wire rx0_green_vld;
  wire rx0_red_vld;
  wire rx0_blue_rdy;
  wire rx0_green_rdy;
  wire rx0_red_rdy;

  dvi_decoder dvi_rx0 (
    //These are input ports
    .blue_p      (RX0_TMDS[0]),
    .green_p     (RX0_TMDS[1]),
    .red_p       (RX0_TMDS[2]),
    .blue_n      (RX0_TMDSB[0]),
    .green_n     (RX0_TMDSB[1]),
    .red_n       (RX0_TMDSB[2]),

    //These are output ports
    .reset       (rx0_reset),
    .pclk        (rx_pclk),
    .pclkx2      (rx_pclkx2),
    .pclkx10     (rx_pclkx10),
    .serdesstrobe(rx_serdesstrobe),
    .hsync       (rx0_hsync),
    .vsync       (rx0_vsync),
    .de          (rx0_de),

    .blue_vld    (rx0_blue_vld),
    .green_vld   (rx0_green_vld),
    .red_vld     (rx0_red_vld),
    .blue_rdy    (rx0_blue_rdy),
    .green_rdy   (rx0_green_rdy),
    .red_rdy     (rx0_red_rdy),

    .psalgnerr   (rx0_psalgnerr),

    .sdout       (rx0_sdata),
    .red         (rx0_red),
    .green       (rx0_green),
    .blue        (rx0_blue)); 

  /////////////////////////
  //
  // Input Port 1
  //
  /////////////////////////
  wire rx1_reset =  ~rx_bufpll_lock;
  wire rx1_plllckd;
  wire rx1_serdesstrobe;
  wire rx1_hsync;          // hsync data
  wire rx1_vsync;          // vsync data
  wire rx1_de;             // data enable
  wire rx1_psalgnerr;      // channel phase alignment error
  wire [7:0] rx1_red;      // pixel data out
  wire [7:0] rx1_green;    // pixel data out
  wire [7:0] rx1_blue;     // pixel data out
  wire [29:0] rx1_sdata;
  wire rx1_blue_vld;
  wire rx1_green_vld;
  wire rx1_red_vld;
  wire rx1_blue_rdy;
  wire rx1_green_rdy;
  wire rx1_red_rdy;

  dvi_decoder dvi_rx1 (
    //These are input ports
    .blue_p      (RX1_TMDS[0]),
    .green_p     (RX1_TMDS[1]),
    .red_p       (RX1_TMDS[2]),
    .blue_n      (RX1_TMDSB[0]),
    .green_n     (RX1_TMDSB[1]),
    .red_n       (RX1_TMDSB[2]),

    //These are output ports
    .reset       (rx1_reset),
    .pclk        (rx_pclk),
    .pclkx2      (rx_pclkx2),
    .pclkx10     (rx_pclkx10),
    .serdesstrobe(rx_serdesstrobe),
    .hsync       (rx1_hsync),
    .vsync       (rx1_vsync),
    .de          (rx1_de),

    .blue_vld    (rx1_blue_vld),
    .green_vld   (rx1_green_vld),
    .red_vld     (rx1_red_vld),
    .blue_rdy    (rx1_blue_rdy),
    .green_rdy   (rx1_green_rdy),
    .red_rdy     (rx1_red_rdy),

    .psalgnerr   (rx1_psalgnerr),

    .sdout       (rx1_sdata),
    .red         (rx1_red),
    .green       (rx1_green),
    .blue        (rx1_blue)); 

  // TMDS output
  
  /////////////////
  //
  // Output Port 0
  //
  /////////////////
  wire         tx0_de;
  wire         tx0_pclk;
  wire         tx0_pclkx2;
  wire         tx0_pclkx10;
  wire         tx0_serdesstrobe;
  wire         tx0_reset;
  wire [7:0]   tx0_blue;
  wire [7:0]   tx0_green;
  wire [7:0]   tx0_red;
  wire         tx0_hsync;
  wire         tx0_vsync;
  wire         tx0_pll_reset;

  assign tx0_de           = (select) ? rx1_de    : rx0_de;
  assign tx0_blue         = (select) ? rx1_blue  : rx0_blue;
  assign tx0_green        = (select) ? rx1_green : rx0_green;
  assign tx0_red          = (select) ? rx1_red   : rx0_red;
  assign tx0_hsync        = (select) ? rx1_hsync : rx0_hsync;
  assign tx0_vsync        = (select) ? rx1_vsync : rx0_vsync;
  assign tx0_pll_reset    = switch | (~rx_bufpll_lock);

  //////////////////////////////////////////////////////////////////
  // Instantiate a dedicate PLL for output port
  //////////////////////////////////////////////////////////////////
  wire tx0_clkfbout, tx0_clkfbin, tx0_plllckd;
  wire tx0_pllclk0, tx0_pllclk2;

  PLL_BASE # (
    .CLKIN_PERIOD(10),
    .CLKFBOUT_MULT(10), //set VCO to 10x of CLKIN
    .CLKOUT0_DIVIDE(1),
    .CLKOUT1_DIVIDE(10),
    .CLKOUT2_DIVIDE(5),
    .COMPENSATION("SOURCE_SYNCHRONOUS")
  ) PLL_OSERDES_0 (
    .CLKFBOUT(tx0_clkfbout),
    .CLKOUT0(tx0_pllclk0),
    .CLKOUT1(),
    .CLKOUT2(tx0_pllclk2),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .LOCKED(tx0_plllckd),
    .CLKFBIN(tx0_clkfbin),
    .CLKIN(rx_pllclk1),
    .RST(tx0_pll_reset)
  );

  //
  // This BUFG is needed in order to deskew between PLL clkin and clkout
  // So the tx0 pclkx2 and pclkx10 will have the same phase as the pclk input
  //
  BUFG tx0_clkfb_buf (.I(tx0_clkfbout), .O(tx0_clkfbin));

  //
  // regenerate pclkx2 for TX
  //
  BUFG tx0_pclkx2_buf (.I(tx0_pllclk2), .O(tx0_pclkx2));

  //
  // regenerate pclkx10 for TX
  //
  wire tx0_bufpll_lock;
  BUFPLL #(.DIVIDE(5)) tx0_ioclk_buf (.PLLIN(tx0_pllclk0), .GCLK(tx0_pclkx2), .LOCKED(tx0_plllckd),
           .IOCLK(tx0_pclkx10), .SERDESSTROBE(tx0_serdesstrobe), .LOCK(tx0_bufpll_lock));

  assign tx0_reset = ~tx0_bufpll_lock;

  dvi_encoder_top dvi_tx0 (
    .pclk        (rx_pllclk1),
    .pclkx2      (tx0_pclkx2),
    .pclkx10     (tx0_pclkx10),
    .serdesstrobe(tx0_serdesstrobe),
    .rstin       (tx0_reset),
    .blue_din    (tx0_blue),
    .green_din   (tx0_green),
    .red_din     (tx0_red),
    .hsync       (tx0_hsync),
    .vsync       (tx0_vsync),
    .de          (tx0_de),
    .TMDS        (TX0_TMDS),
    .TMDSB       (TX0_TMDSB));

  //////////////////////////////////////
  // Status LED
  //////////////////////////////////////
  assign LED = {rx0_red_rdy, rx0_green_rdy, rx0_blue_rdy, rx1_red_rdy, rx1_green_rdy, rx1_blue_rdy,
                rx0_de, rx1_de};

endmodule
