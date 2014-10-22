----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    21:49:35 07/28/2014 
-- Module Name:    PANDA_LIGHT - rtl 
-- Project Name:   PANDA_LIGHT
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity PANDA_LIGHT is
    generic (
        RX_SEL              : natural := 0;
        MAX_LED_COUNT       : natural := 100;
        MAX_LED_BUFFER_SIZE : natural := 1024
    );
    port (
        CLK20   : in std_ulogic;
        
        -- HDMI
        RX_CHANNELS_IN_P    : in std_ulogic_vector(7 downto 0);
        RX_CHANNELS_IN_N    : in std_ulogic_vector(7 downto 0);
        RX_SDA              : inout std_ulogic_vector(1 downto 0) := "ZZ";
        RX_SCL              : inout std_ulogic_vector(1 downto 0) := "ZZ";
        RX_CEC              : inout std_ulogic_vector(1 downto 0) := "ZZ";
        RX_DET              : in std_ulogic_vector(1 downto 0);
        RX_EN               : out std_ulogic_vector(1 downto 0) := "00";
        
        TX_CHANNELS_OUT_P   : out std_ulogic_vector(3 downto 0) := "0000";
        TX_CHANNELS_OUT_N   : out std_ulogic_vector(3 downto 0) := "0000";
        TX_SDA              : inout std_ulogic := 'Z';
        TX_SCL              : inout std_ulogic := 'Z';
        TX_CEC              : inout std_ulogic := 'Z';
        TX_DET              : in std_ulogic := '0';
        TX_EN               : out std_ulogic := '0';
        
        -- USB UART
        USB_RXD     : in std_ulogic;
        USB_TXD     : out std_ulogic := '0';
        USB_CTSN    : in std_ulogic;
        USB_RTSN    : out std_ulogic := '0';
        USB_DSRN    : in std_ulogic;
        USB_DTRN    : out std_ulogic := '0';
        USB_DCDN    : out std_ulogic := '0';
        USB_RIN     : out std_ulogic := '0';
        
        -- Blutooth UART
        BT_TXD  : out std_ulogic := '0';
        BT_RXD  : in std_ulogic;
        BT_RTS  : out std_ulogic := '0';
        BT_CTS  : in std_ulogic;
        
        -- LED strip
        LEDS_CLK    : out std_ulogic_vector(1 downto 0) := "00";
        LEDS_DATA   : out std_ulogic_vector(1 downto 0) := "00";
        
        -- PMOD
        PMOD0   : inout std_ulogic_vector(3 downto 0) := "0000";
        PMOD1   : inout std_ulogic_vector(3 downto 0) := "0000";
        PMOD2   : inout std_ulogic_vector(3 downto 0) := "0000";
        PMOD3   : inout std_ulogic_vector(3 downto 0) := "0000"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep : string;
    
    -- 50 MHz in nano seconds
    constant G_CLK_PERIOD   : real := 20.0;
    
    -- 1 MHz, 100 LEDs: 2.9 ms latency, ~344 fps
    constant WS2801_CLK_PERIOD  : real := 1000.0;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_stopped    : std_ulogic := '0';
    
    signal uart_select  : std_ulogic := '0';
    
    
    ----------------------------
    --- HDMI related signals ---
    ----------------------------
    
    signal rx_edid_ready    : std_ulogic_vector(1 downto 0) := "00";
    
    signal rx_channels_in   : std_ulogic_vector(7 downto 0) := x"00";
    signal tx_channels_out  : std_ulogic_vector(3 downto 0) := "0000";
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    -- Inputs
    signal rxclk_clk_in : std_ulogic := '0';
    attribute keep of rxclk_clk_in : signal is "TRUE";
    
    -- Outputs
    signal rxclk_clk_out1       : std_ulogic := '0';
    signal rxclk_clk_out2       : std_ulogic := '0';
    signal rxclk_ioclk_out      : std_ulogic := '0';
    signal rxclk_ioclk_locked   : std_ulogic := '0';
    signal rxclk_serdesstrobe   : std_ulogic := '0';
    
    
    -----------------------
    --- RX HDMI Decoder ---
    -----------------------
    
    -- Inputs
    signal rx_pix_clk       : std_ulogic := '0';
    signal rx_pix_clk_x2    : std_ulogic := '0';
    signal rx_pix_clk_x10   : std_ulogic := '0';
    signal rx_rst           : std_ulogic := '0';
    
    signal rx_clk_locked    : std_ulogic := '0';
    signal rx_serdesstrobe  : std_ulogic := '0';
    
    -- Outputs
    signal rx_enc_data          : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rx_enc_data_valid    : std_ulogic := '0';
    
    signal rx_vsync             : std_ulogic := '0';
    signal rx_hsync             : std_ulogic := '0';
    signal rx_rgb               : std_ulogic_vector(23 downto 0) := x"000000";
    signal rx_aux_data          : std_ulogic_vector(8 downto 0) := (others => '0');
    signal rx_aux_data_valid    : std_ulogic := '0';
    
    
    ----------------------------
    --- LED colour extractor ---
    ----------------------------
    
    -- Inputs
    signal ledex_clk    : std_ulogic := '0';
    signal ledex_rst    : std_ulogic := '0';
    
    signal ledex_cfg_addr   : std_ulogic_vector(3 downto 0) := "0000";
    signal ledex_cfg_wr_en  : std_ulogic := '0';
    signal ledex_cfg_data   : std_ulogic_vector(7 downto 0) := x"00";
    
    signal ledex_frame_vsync    : std_ulogic := '0';
    signal ledex_frame_hsync    : std_ulogic := '0';
    
    signal ledex_frame_rgb  : std_ulogic_vector(23 downto 0) := x"000000";
    
    -- Outputs
    signal ledex_led_vsync  : std_ulogic := '0';
    signal ledex_led_valid  : std_ulogic := '0';  
    signal ledex_led_num    : std_ulogic_vector(7 downto 0) := x"00";
    signal ledex_led_rgb    : std_ulogic_vector(23 downto 0) := x"000000";
    
    
    -------------------
    --- LED control ---
    -------------------
    
    -- Inputs
    signal ledctrl_clk  : std_ulogic := '0';
    signal ledctrl_rst  : std_ulogic := '0';
    
    signal ledctrl_mode : std_ulogic_vector(1 downto 0);
    
    signal ledctrl_led_vsync        : std_ulogic := '0';
    signal ledctrl_led_rgb          : std_ulogic_vector(23 downto 0);
    signal ledctrl_led_rgb_wr_en    : std_ulogic := '0';
    
    -- Outputs
    signal ledctrl_leds_clk     : std_ulogic := '0';
    signal ledctrl_leds_data    : std_ulogic := '0';
    
    
    ----------------------
    --- LED correction ---
    ----------------------
    
    -- Inputs
    signal ledcorr_clk  : std_ulogic := '0';
    signal ledcorr_rst  : std_ulogic := '0';
    
    signal ledcorr_cfg_addr     : std_ulogic_vector(1 downto 0) := "00";
    signal ledcorr_cfg_wr_en    : std_ulogic := '0';
    signal ledcorr_cfg_data     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal ledcorr_led_in_vsync : std_ulogic := '0';
    signal ledcorr_led_in_num   : std_ulogic_vector(7 downto 0) := x"00";
    signal ledcorr_led_in_wr_en : std_ulogic := '0';
    signal ledcorr_led_in_rgb   : std_ulogic_vector(23 downto 0) := x"000000";
    
    -- Outputs
    signal ledcorr_led_out_vsync    : std_ulogic := '0';
    signal ledcorr_led_out_valid    : std_ulogic := '0';
    signal ledcorr_led_out_rgb      : std_ulogic_vector(23 downto 0) := x"000000";
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    -- Inputs
    signal rxpt_pix_clk : std_ulogic := '0';
    signal rxpt_rst     : std_ulogic := '0';
    
    -- Outputs
    signal rxpt_rx_enc_data         : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rxpt_rx_enc_data_valid   : std_ulogic := '0';
    
    signal rxpt_tx_channels_out : std_ulogic_vector(3 downto 0) := "0000";
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLK_MAN_inst : entity work.CLK_MAN
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            MULTIPLIER      => 5,
            DIVISOR         => 2
        )
        port map (
            CLK_IN          => CLK20,
            CLK_OUT         => g_clk,
            CLK_OUT_STOPPED => g_clk_stopped
        );
    
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    USB_TXD     <= microblaze_txd when uart_select='0' else '0';
    USB_RTSN    <= not microblaze_gpo1(11) when uart_select='0' else '1';
    
    BT_TXD  <= microblaze_txd when uart_select='1' else '0';
    BT_RTS  <= microblaze_gpo1(11) when uart_select='1' else '0';
    
    LEDS_CLK(0)     <= ledctrl_leds_clk;
    LEDS_DATA(0)    <= ledctrl_leds_data;
    
    g_rst   <= g_clk_stopped;
    
    uart_select <= microblaze_gpo1(12);
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    RX_EN   <= rx_edid_ready;
    
    -- drive low dominant I2C signals
    RX_SDA(RX_SEL)  <= '0' when eddc_s_sda_out='0' else 'Z';
    RX_SCL(RX_SEL)  <= '0' when eddc_s_scl_out='0' else 'Z';
    TX_SDA          <= '0' when eddc_m_sda_out='0' else 'Z';
    TX_SCL          <= '0' when eddc_m_scl_out='0' else 'Z';
    
    rx_edid_ready   <= stdulv(microblaze_gpo1(14 downto 13));
    
    TX_EN   <= rx_enc_data_valid;
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    diff_ibuf_gen : for i in 0 to 7 generate
        
        rx_channel_IBUFDS_inst : IBUFDS
            generic map (DIFF_TERM  => false)
            port map (
                I   => RX_CHANNELS_IN_P(i),
                IB  => RX_CHANNELS_IN_N(i),
                O   => rx_channels_in(i)
            );
        
    end generate;
    
    diff_obuf_gen : for i in 0 to 3 generate
        
        tx_channel_OBUFDS_inst : OBUFDS
            port map (
                I   => tx_channels_out(i),
                O   => TX_CHANNELS_OUT_P(i),
                OB  => TX_CHANNELS_OUT_N(i)
            );
        
    end generate;
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    rxclk_clk_in    <= rx_channels_in(RX_SEL*4 + 3);

    ISERDES2_CLK_MAN_inst : entity work.ISERDES2_CLK_MAN
        generic map (
            MULTIPLIER      => 10,
            CLK_IN_PERIOD   => 13.0, -- only for testing
            DIVISOR0        => 1,    -- bit clock
            DIVISOR1        => 5,    -- serdes clock = pixel clock * 2
            DIVISOR2        => 10,   -- pixel clock
            DATA_CLK_SELECT => 1,    -- clock out 1
            IO_CLK_SELECT   => 0     -- clock out 0
        )
        port map (
            CLK_IN          => rxclk_clk_in,
            CLK_OUT1        => rxclk_clk_out1,
            CLK_OUT2        => rxclk_clk_out2,
            IOCLK_OUT       => rxclk_ioclk_out,
            IOCLK_LOCKED    => rxclk_ioclk_locked,
            SERDESSTROBE    => rxclk_serdesstrobe
        );
    
    
    --------------------
    --- HDMI Decoder ---
    --------------------
    
    rx_pix_clk          <= rxclk_clk_out2;
    rx_pix_clk_x2       <= rxclk_clk_out1;
    rx_pix_clk_x10      <= rxclk_ioclk_out;
    rx_rst              <= not RX_DET(RX_SEL);
    rx_clk_locked       <= rxclk_ioclk_locked;
    rx_serdesstrobe     <= rxclk_serdesstrobe;
    
    TMDS_DECODER_inst : entity work.TMDS_DECODER
        port map (
            PIX_CLK         => rx_pix_clk,
            PIX_CLK_X2      => rx_pix_clk_x2,
            PIX_CLK_X10     => rx_pix_clk_x10,
            RST             => rx_rst,
            
            CLK_LOCKED      => rx_clk_locked,
            SERDESSTROBE    => rx_serdesstrobe,
            
            CHANNELS_IN => rx_channels_in(RX_SEL*4 + 2 downto RX_SEL*4),
            
            ENC_DATA        => rx_enc_data,
            ENC_DATA_VALID  => rx_enc_data_valid,
            
            VSYNC           => rx_vsync,
            HSYNC           => rx_hsync,
            RGB             => rx_rgb,
            AUX_DATA        => rx_aux_data,
            AUX_DATA_VALID  => rx_aux_data_valid
        );
    
    
    ---------------------------
    --- LED color extractor ---
    ---------------------------
    
    ledex_clk   <= rx_pix_clk;
    ledex_rst   <= rx_rst;
    
    ledex_cfg_addr  <= stdulv(microblaze_gpo3(11 downto 8));
    ledex_cfg_wr_en <= stdul(microblaze_gpo3(12));
    ledex_cfg_data  <= stdulv(microblaze_gpo3(7 downto 0));
    
    ledex_frame_vsync   <= rx_vsync;
    ledex_frame_hsync   <= rx_hsync;
    
    ledex_frame_rgb <= rx_rgb;
    
    LED_COLOR_EXTRACTOR_inst : entity work.LED_COLOR_EXTRACTOR
        port map (
            CLK => ledex_clk,
            RST => ledex_rst,
            
            CFG_ADDR    => ledex_cfg_addr,
            CFG_WR_EN   => ledex_cfg_wr_en,
            CFG_DATA    => ledex_cfg_data,
            
            FRAME_VSYNC => ledex_frame_vsync,
            FRAME_HSYNC => ledex_frame_hsync,
            
            FRAME_RGB   => ledex_frame_rgb,
            
            LED_VSYNC   => ledex_led_vsync,
            LED_VALID   => ledex_led_valid,
            LED_NUM     => ledex_led_num,
            LED_RGB     => ledex_led_rgb
        );
    
    
    -------------------
    --- LED control ---
    -------------------
    
    ledctrl_clk <= rx_pix_clk;
    ledctrl_rst <= rx_rst;
    
    ledctrl_mode    <= stdulv(microblaze_gpo3(14 downto 13));
    
    ledctrl_led_vsync       <= ledcorr_led_out_vsync;
    ledctrl_led_rgb         <= ledcorr_led_out_rgb;
    ledctrl_led_rgb_wr_en   <= ledcorr_led_out_valid;
    
    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD           => G_CLK_PERIOD,
            WS2801_LEDS_CLK_PERIOD  => WS2801_CLK_PERIOD
        )
        port map (
            CLK => ledctrl_clk,
            RST => ledctrl_rst,
            
            MODE    => ledctrl_mode,
            
            LED_VSYNC       => ledctrl_led_vsync,
            LED_RGB         => ledctrl_led_rgb,
            LED_RGB_WR_EN   => ledctrl_led_rgb_wr_en,
            
            LEDS_CLK    => ledctrl_leds_clk,
            LEDS_DATA   => ledctrl_leds_data
        );
    
    
    ----------------------
    --- LED correction ---
    ----------------------
    
    ledcorr_clk <= rx_pix_clk;
    ledcorr_rst <= rx_rst;
    
    ledcorr_cfg_addr    <= stdulv(microblaze_gpo3(25 downto 24));
    ledcorr_cfg_wr_en   <= stdul(microblaze_gpo3(26));
    ledcorr_cfg_data    <= stdulv(microblaze_gpo3(23 downto 16));
    
    ledcorr_led_in_vsync    <= ledex_led_vsync;
    ledcorr_led_in_num      <= ledex_led_num;
    ledcorr_led_in_wr_en    <= ledex_led_valid;
    ledcorr_led_in_rgb      <= ledex_led_rgb;
    
    LED_CORRECTION_inst : entity work.LED_CORRECTION
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            MAX_BUFFER_SIZE => MAX_LED_BUFFER_SIZE
        )
        port map (
            CLK => ledcorr_clk,
            RST => ledcorr_rst,
            
            CFG_ADDR    => ledcorr_cfg_addr,
            CFG_WR_EN   => ledcorr_cfg_wr_en,
            CFG_DATA    => ledcorr_cfg_data,
            
            LED_IN_VSYNC    => ledcorr_led_in_vsync,
            LED_IN_NUM      => ledcorr_led_in_num,
            LED_IN_WR_EN    => ledcorr_led_in_wr_en,
            LED_IN_RGB      => ledcorr_led_in_rgb,
            
            LED_OUT_VSYNC   => ledcorr_led_out_vsync,
            LED_OUT_VALID   => ledcorr_led_out_valid,
            LED_OUT_RGB     => ledcorr_led_out_rgb
        );
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    rxpt_pix_clk    <= rx_pix_clk;
    rxpt_rst        <= rx_rst;
    
    rxpt_rx_enc_data        <= rx_enc_data;
    rxpt_rx_enc_data_valid  <= rx_enc_data_valid;
    
    TMDS_PASSTHROUGH_inst : entity work.TMDS_PASSTHROUGH
        port map (
            PIX_CLK => rxpt_pix_clk,
            RST     => rxpt_rst,
            
            RX_ENC_DATA         => rxpt_rx_enc_data,
            RX_ENC_DATA_VALID   => rxpt_rx_enc_data_valid,
            
            TX_CHANNELS_OUT => rxpt_tx_channels_out
        );
    
end rtl;

