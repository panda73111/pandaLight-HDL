----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    21:49:35 07/28/2014 
-- Module Name:    PANDA_LIGHT - rtl 
-- Project Name:   PANDA_LIGHT
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;
use work.txt_util.all;

entity PANDA_LIGHT is
    generic (
        G_CLK_MULT          : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV           : positive range 1 to 256 := 2;
        G_CLK_PERIOD        : real := 20.0; -- 50 MHz in nano seconds
        FCTRL_CLK_MULT      : positive :=  2; -- Flash clock: 20 MHz
        FCTRL_CLK_DIV       : positive :=  5;
        RX_SEL              : natural range 0 to 1 := 1;
        RX0_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"000000";
        RX1_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"060000";
        SETTINGS_FLASH_ADDR : std_ulogic_vector(23 downto 0) := x"0C0000";
        ENABLE_IPROG_RECONF : boolean := false
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
        
        TX_CHANNELS_OUT_P   : out std_ulogic_vector(3 downto 0) := "1111";
        TX_CHANNELS_OUT_N   : out std_ulogic_vector(3 downto 0) := "1111";
        TX_SDA              : inout std_ulogic := 'Z';
        TX_SCL              : inout std_ulogic := 'Z';
        TX_CEC              : inout std_ulogic := 'Z';
        TX_DET              : in std_ulogic := '0';
        TX_EN               : out std_ulogic := '0';
        
        -- SPI Flash
        FLASH_MISO  : in std_ulogic;
        FLASH_MOSI  : out std_ulogic := '0';
        FLASH_CS    : out std_ulogic := '1';
        FLASH_SCK   : out std_ulogic := '0';
        
        -- LEDs
        LEDS_CLK    : out std_ulogic_vector(1 downto 0) := "00";
        LEDS_DATA   : out std_ulogic_vector(1 downto 0) := "00";
        
        -- PMOD
        PMOD0   : inout std_ulogic_vector(3 downto 0) := x"0"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    signal pmod0_deb    : std_ulogic_vector(3 downto 0) := x"0";
    signal pmod0_deb_q  : std_ulogic_vector(3 downto 0) := x"0";
    
    signal start_settings_read  : boolean := false;
    
    
    ----------------------------
    --- HDMI related signals ---
    ----------------------------
    
    signal rx_det_stable    : std_ulogic_vector(1 downto 0) := "00";
    signal rx_det_stable_q  : std_ulogic_vector(1 downto 0) := "00";
    signal rx_det_sync      : std_ulogic_vector(1 downto 0) := "00";
    signal tx_det_sync      : std_ulogic := '0';
    signal tx_det_stable    : std_ulogic := '0';
    
    signal rx_channels_in   : std_ulogic_vector(7 downto 0) := x"00";
    signal tx_channels_out  : std_ulogic_vector(3 downto 0) := "0000";
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    -- Inputs
    signal rxclk_clk_in : std_ulogic := '0';
    attribute keep of rxclk_clk_in : signal is true;
    
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
    
    signal rx_serdesstrobe  : std_ulogic := '0';
    
    -- Outputs
    signal rx_raw_data          : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rx_raw_data_valid    : std_ulogic := '0';
    
    signal rx_vsync     : std_ulogic := '0';
    signal rx_hsync     : std_ulogic := '0';
    signal rx_rgb       : std_ulogic_vector(23 downto 0) := x"000000";
    signal rx_rgb_valid : std_ulogic := '0';
    signal rx_aux       : std_ulogic_vector(8 downto 0) := (others => '0');
    signal rx_aux_valid : std_ulogic := '0';
    
    
    ----------------------
    --- video analyzer ---
    ----------------------
    
    -- Inputs
    signal analyzer_clk : std_ulogic := '0';
    signal analyzer_rst : std_ulogic := '0';
    
    signal analyzer_start       : std_ulogic := '0';
    signal analyzer_vsync       : std_ulogic := '0';
    signal analyzer_hsync       : std_ulogic := '0';
    signal analyzer_rgb_valid   : std_ulogic := '0';
    
    -- Outputs
    signal analyzer_positive_vsync  : std_ulogic := '0';
    signal analyzer_positive_hsync  : std_ulogic := '0';
    signal analyzer_width           : std_ulogic_vector(10 downto 0) := (others => '0');
    signal analyzer_height          : std_ulogic_vector(10 downto 0) := (others => '0');
    signal analyzer_interlaced      : std_ulogic := '0';
    signal analyzer_valid           : std_ulogic := '0';
    
    
    ----------------------------
    --- LED colour extractor ---
    ----------------------------
    
    -- Inputs
    signal ledex_clk    : std_ulogic := '0';
    signal ledex_rst    : std_ulogic := '0';
    
    signal ledex_cfg_addr   : std_ulogic_vector(3 downto 0) := "0000";
    signal ledex_cfg_wr_en  : std_ulogic := '0';
    signal ledex_cfg_data   : std_ulogic_vector(7 downto 0) := x"00";
    
    signal ledex_frame_vsync        : std_ulogic := '0';
    signal ledex_frame_rgb_wr_en    : std_ulogic := '0';
    signal ledex_frame_rgb          : std_ulogic_vector(23 downto 0) := x"000000";
    
    -- Outputs
    signal ledex_led_vsync      : std_ulogic := '0';
    signal ledex_led_num        : std_ulogic_vector(7 downto 0) := x"00";
    signal ledex_led_rgb_valid  : std_ulogic := '0';  
    signal ledex_led_rgb        : std_ulogic_vector(23 downto 0) := x"000000";
    
    
    ----------------------
    --- LED correction ---
    ----------------------
    
    signal lcor_clk : std_ulogic := '0';
    signal lcor_rst : std_ulogic := '0';
    
    signal lcor_cfg_addr    : std_ulogic_vector(9 downto 0) := (others => '0');
    signal lcor_cfg_wr_en   : std_ulogic := '0';
    signal lcor_cfg_data    : std_ulogic_vector(7 downto 0) := x"00";
    
    signal lcor_led_in_vsync        : std_ulogic := '0';
    signal lcor_led_in_num          : std_ulogic_vector(7 downto 0) := x"FF";
    signal lcor_led_in_rgb          : std_ulogic_vector(23 downto 0) := x"000000";
    signal lcor_led_in_rgb_wr_en    : std_ulogic := '0';
    
    signal lcor_led_out_vsync       : std_ulogic := '0';
    signal lcor_led_out_rgb         : std_ulogic_vector(23 downto 0) := x"000000";
    signal lcor_led_out_rgb_valid   : std_ulogic := '0';
    
    
    -------------------
    --- LED control ---
    -------------------
    
    signal lctrl_clk    : std_ulogic := '0';
    signal lctrl_rst    : std_ulogic := '0';
    
    signal lctrl_mode   : std_ulogic_vector(1 downto 0) := "00";
    
    signal lctrl_led_vsync      : std_ulogic := '0';
    signal lctrl_led_rgb        : std_ulogic_vector(23 downto 0) := x"000000";
    signal lctrl_led_rgb_wr_en  : std_ulogic := '0';
    
    signal lctrl_leds_clk   : std_ulogic := '0';
    signal lctrl_leds_data  : std_ulogic := '0';
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    -- Inputs
    signal rxpt_pix_clk : std_ulogic := '0';
    signal rxpt_rst     : std_ulogic := '0';
    
    -- Outputs
    signal rxpt_rx_raw_data         : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rxpt_rx_raw_data_valid   : std_ulogic := '0';
    
    signal rxpt_tx_channels_out : std_ulogic_vector(3 downto 0) := "0000";
    
    
    --------------------
    --- configurator ---
    --------------------
    
    -- Inputs
    signal conf_clk : std_ulogic := '0';
    signal conf_rst : std_ulogic := '0';
    
    signal conf_calculate           : std_ulogic := '0';
    signal conf_configure_ledex     : std_ulogic := '0';
    signal conf_configure_ledcor    : std_ulogic := '0';
    
    signal conf_frame_width     : std_ulogic_vector(10 downto 0) := (others => '0');
    signal conf_frame_height    : std_ulogic_vector(10 downto 0) := (others => '0');
    
    signal conf_settings_addr   : std_ulogic_vector(9 downto 0) := (others => '0');
    signal conf_settings_wr_en  : std_ulogic := '0';
    signal conf_settings_data   : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal conf_cfg_sel_ledex   : std_ulogic := '0';
    signal conf_cfg_sel_ledcor  : std_ulogic := '0';
    
    signal conf_cfg_addr        : std_ulogic_vector(9 downto 0) := (others => '0');
    signal conf_cfg_wr_en       : std_ulogic := '0';
    signal conf_cfg_data        : std_ulogic_vector(7 downto 0) := x"00";
    
    signal conf_busy    : std_ulogic := '0';
    
    
    -------------------------
    --- SPI Flash control ---
    -------------------------
    
    -- Inputs
    signal fctrl_clk    : std_ulogic := '0';
    signal fctrl_rst    : std_ulogic := '0';
    
    signal fctrl_addr   : std_ulogic_vector(23 downto 0) := x"000000";
    signal fctrl_din    : std_ulogic_vector(7 downto 0) := x"00";
    signal fctrl_rd_en  : std_ulogic := '0';
    signal fctrl_wr_en  : std_ulogic := '0';
    signal fctrl_miso   : std_ulogic := '0';
    
    -- Outputs
    signal fctrl_dout   : std_ulogic_vector(7 downto 0) := x"00";
    signal fctrl_valid  : std_ulogic := '0';
    signal fctrl_wr_ack : std_ulogic := '0';
    signal fctrl_busy   : std_ulogic := '0';
    signal fctrl_full   : std_ulogic := '0';
    signal fctrl_mosi   : std_ulogic := '0';
    signal fctrl_c      : std_ulogic := '0';
    signal fctrl_sn     : std_ulogic := '1';
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLK_MAN_inst : entity work.CLK_MAN
        generic map (
            CLK_IN_PERIOD   => 50.0, -- 20 MHz in nano seconds
            MULTIPLIER      => G_CLK_MULT,
            DIVISOR         => G_CLK_DIV
        )
        port map (
            RST => '0',
            
            CLK_IN  => CLK20,
            CLK_OUT => g_clk,
            LOCKED  => g_clk_locked
        );
    
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    g_rst   <= not g_clk_locked;
    
    FLASH_MOSI  <= fctrl_mosi;
    FLASH_CS    <= fctrl_sn;
    FLASH_SCK   <= fctrl_c;
    
    LEDS_CLK    <= lctrl_leds_clk & lctrl_leds_clk;
    LEDS_DATA   <= lctrl_leds_data & lctrl_leds_data;
    
    PMOD0(0)    <= 'Z';
    PMOD0(1)    <= 'Z';
    PMOD0(2)    <= 'Z';
    PMOD0(3)    <= 'Z';
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- only enabled chips make 'DET' signals possible!
    RX_EN(RX_SEL)   <= tx_det_stable;
    RX_EN(1-RX_SEL) <= tx_det_stable;
    TX_EN           <= '1';
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    rx_det_sync_proc : process(g_clk)
    begin
        if rising_edge(g_clk) then
            rx_det_sync <= rx_det;
            tx_det_sync <= tx_det;
        end if;
    end process;
    
    rx_DEBOUNCE_gen : for i in 0 to 1 generate
        
        rx_det_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 1000
            )
            port map (
                CLK => g_clk,
                
                I   => rx_det_sync(i),
                O   => rx_det_stable(i)
            );
    
    end generate;
        
    tx_det_DEBOUNCE_inst : entity work.DEBOUNCE
        generic map (
            CYCLE_COUNT => 1000
        )
        port map (
            CLK => g_clk,
            
            I   => tx_det_sync,
            O   => tx_det_stable
        );
    
    diff_IBUFDS_gen : for i in 0 to 7 generate
        
        rx_channel_IBUFDS_inst : IBUFDS
            generic map (DIFF_TERM  => false)
            port map (
                I   => RX_CHANNELS_IN_P(i),
                IB  => RX_CHANNELS_IN_N(i),
                O   => rx_channels_in(i)
            );
        
    end generate;
    
    diff_OBUFDS_gen : for i in 0 to 3 generate
        
        tx_channel_OBUFDS_inst : OBUFDS
            port map (
                I   => tx_channels_out(i),
                O   => TX_CHANNELS_OUT_P(i),
                OB  => TX_CHANNELS_OUT_N(i)
            );
        
    end generate;
    
    
    ----------------------------
    --- HDMI DDC passthrough ---
    ----------------------------
    
    scl_BIDIR_REPEAT_BUFFER_inst : entity work.BIDIR_REPEAT_BUFFER
        generic map (
            PULL    => "UP"
        )
        port map (
            CLK => g_clk,
            
            P0_IN   => RX_SCL(RX_SEL),
            P0_OUT  => RX_SCL(RX_SEL),
            P1_IN   => TX_SCL,
            P1_OUT  => TX_SCL
        );
    
    sda_BIDIR_REPEAT_BUFFER_inst : entity work.BIDIR_REPEAT_BUFFER
        generic map (
            PULL    => "UP"
        )
        port map (
            CLK => g_clk,
            
            P0_IN   => RX_SDA(RX_SEL),
            P0_OUT  => RX_SDA(RX_SEL),
            P1_IN   => TX_SDA,
            P1_OUT  => TX_SDA
        );
    
    
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
    rx_rst              <= g_rst or not rx_det_stable(RX_SEL) or not rxclk_ioclk_locked;
    rx_serdesstrobe     <= rxclk_serdesstrobe;
    
    TMDS_DECODER_inst : entity work.TMDS_DECODER
        port map (
            PIX_CLK         => rx_pix_clk,
            PIX_CLK_X2      => rx_pix_clk_x2,
            PIX_CLK_X10     => rx_pix_clk_x10,
            RST             => rx_rst,
            
            SERDESSTROBE    => rx_serdesstrobe,
            
            CHANNELS_IN => rx_channels_in(RX_SEL*4 + 2 downto RX_SEL*4),
            
            RAW_DATA        => rx_raw_data,
            RAW_DATA_VALID  => rx_raw_data_valid,
            
            VSYNC       => rx_vsync,
            HSYNC       => rx_hsync,
            RGB         => rx_rgb,
            RGB_VALID   => rx_rgb_valid,
            AUX         => rx_aux,
            AUX_VALID   => rx_aux_valid
        );
    
    
    ----------------------
    --- video analyzer ---
    ----------------------
    
    analyzer_clk    <= rx_pix_clk;
    analyzer_rst    <= rx_rst;
    
    analyzer_start      <= rx_raw_data_valid;
    analyzer_vsync      <= rx_vsync;
    analyzer_hsync      <= rx_hsync;
    analyzer_rgb_valid  <= rx_rgb_valid;
    
    VIDEO_ANALYZER_inst : entity work.VIDEO_ANALYZER
        port map (
            CLK => analyzer_clk,
            RST => analyzer_rst,
            
            START       => analyzer_start,
            VSYNC       => analyzer_vsync,
            HSYNC       => analyzer_hsync,
            RGB_VALID   => analyzer_rgb_valid,
            
            POSITIVE_VSYNC  => analyzer_positive_vsync,
            POSITIVE_HSYNC  => analyzer_positive_hsync,
            WIDTH           => analyzer_width,
            HEIGHT          => analyzer_height,
            INTERLACED      => analyzer_interlaced,
            VALID           => analyzer_valid
        );
    
    
    ---------------------------
    --- LED color extractor ---
    ---------------------------
    
    ledex_clk   <= rx_pix_clk;
    ledex_rst   <= not analyzer_valid or conf_cfg_sel_ledex;
    
    ledex_cfg_addr  <= conf_cfg_addr(ledex_cfg_addr'range);
    ledex_cfg_wr_en <= conf_cfg_wr_en and conf_cfg_sel_ledex;
    ledex_cfg_data  <= conf_cfg_data;
    
    ledex_frame_vsync       <= analyzer_positive_vsync;
    ledex_frame_rgb_wr_en   <= rx_rgb_valid;
    ledex_frame_rgb         <= rx_rgb;
    
    LED_COLOR_EXTRACTOR_inst : entity work.LED_COLOR_EXTRACTOR
        port map (
            CLK => ledex_clk,
            RST => ledex_rst,
            
            CFG_ADDR    => ledex_cfg_addr,
            CFG_WR_EN   => ledex_cfg_wr_en,
            CFG_DATA    => ledex_cfg_data,
            
            FRAME_VSYNC     => ledex_frame_vsync,
            FRAME_RGB_WR_EN => ledex_frame_rgb_wr_en,
            FRAME_RGB       => ledex_frame_rgb,
            
            LED_VSYNC       => ledex_led_vsync,
            LED_NUM         => ledex_led_num,
            LED_RGB_VALID   => ledex_led_rgb_valid,
            LED_RGB         => ledex_led_rgb
        );
    
    
    ----------------------
    --- LED correction ---
    ----------------------
    
    lcor_clk    <= ledex_clk;
    lcor_rst    <= ledex_rst or conf_cfg_sel_ledcor;
    
    lcor_cfg_addr   <= conf_cfg_addr(lcor_cfg_addr'range);
    lcor_cfg_wr_en  <= conf_cfg_wr_en and conf_cfg_sel_ledcor;
    lcor_cfg_data   <= conf_cfg_data;
    
    lcor_led_in_vsync       <= ledex_led_vsync;
    lcor_led_in_num         <= ledex_led_num;
    lcor_led_in_rgb         <= ledex_led_rgb;
    lcor_led_in_rgb_wr_en   <= ledex_led_rgb_valid;
    
    LED_CORRECTION_inst : entity work.LED_CORRECTION
        generic map (
            MAX_LED_COUNT   => 64,
            MAX_FRAME_COUNT => 128
        )
        port map (
            CLK => lcor_clk,
            RST => lcor_rst,
            
            CFG_ADDR    => lcor_cfg_addr,
            CFG_WR_EN   => lcor_cfg_wr_en,
            CFG_DATA    => lcor_cfg_data,
            
            LED_IN_VSYNC        => lcor_led_in_vsync,
            LED_IN_NUM          => lcor_led_in_num,
            LED_IN_RGB          => lcor_led_in_rgb,
            LED_IN_RGB_WR_EN    => lcor_led_in_rgb_wr_en,
            
            LED_OUT_VSYNC       => lcor_led_out_vsync,
            LED_OUT_RGB         => lcor_led_out_rgb,
            LED_OUT_RGB_VALID   => lcor_led_out_rgb_valid
        );
    
    
    ------------------
    -- LED control ---
    ------------------
    
    lctrl_clk   <= lcor_clk;
    lctrl_rst   <= lcor_rst;
    
    lctrl_mode  <= "00";
    
    lctrl_led_vsync     <= lcor_led_out_vsync;
    lctrl_led_rgb       <= lcor_led_out_rgb;
    lctrl_led_rgb_wr_en <= lcor_led_out_rgb_valid;
    
    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD           => G_CLK_PERIOD,
            WS2801_LEDS_CLK_PERIOD  => 1000.0 -- 1 MHz
        )
        port map (
            CLK => lctrl_clk,
            RST => lctrl_rst,
            
            MODE    => lctrl_mode,
            
            LED_VSYNC       => lctrl_led_vsync,
            LED_RGB         => lctrl_led_rgb,
            LED_RGB_WR_EN   => lctrl_led_rgb_wr_en,
            
            LEDS_CLK    => lctrl_leds_clk,
            LEDS_DATA   => lctrl_leds_data
        );
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    rxpt_pix_clk    <= rx_pix_clk;
    rxpt_rst        <= rx_rst;
    
    rxpt_rx_raw_data        <= rx_raw_data;
    rxpt_rx_raw_data_valid  <= rx_raw_data_valid;
    
    TMDS_PASSTHROUGH_inst : entity work.TMDS_PASSTHROUGH
        port map (
            PIX_CLK => rxpt_pix_clk,
            RST     => rxpt_rst,
            
            RX_RAW_DATA         => rxpt_rx_raw_data,
            RX_RAW_DATA_VALID   => rxpt_rx_raw_data_valid,
            
            TX_CHANNELS_OUT => rxpt_tx_channels_out
        );
    
    
    -------------------
    -- configurator ---
    -------------------
    
    conf_clk    <= rx_pix_clk;
    conf_rst    <= g_rst or not analyzer_valid;
    
    conf_frame_width    <= analyzer_width;
    conf_frame_height   <= analyzer_height;
    
    CONFIGURATOR_inst : entity work.CONFIGURATOR
        port map (
            CLK => conf_clk,
            RST => conf_rst,
            
            CALCULATE           => conf_calculate,
            CONFIGURE_LEDEX     => conf_configure_ledex,
            CONFIGURE_LEDCOR    => conf_configure_ledcor,
            
            FRAME_WIDTH     => conf_frame_width,
            FRAME_HEIGHT    => conf_frame_height,
            
            CFG_SEL_LEDEX   => conf_cfg_sel_ledex,
            CFG_SEL_LEDCOR  => conf_cfg_sel_ledcor,
            
            SETTINGS_ADDR   => conf_settings_addr,
            SETTINGS_WR_EN  => conf_settings_wr_en,
            SETTINGS_DATA   => conf_settings_data,
            
            CFG_ADDR    => conf_cfg_addr,
            CFG_WR_EN   => conf_cfg_wr_en,
            CFG_DATA    => conf_cfg_data,
            
            BUSY    => conf_busy
        );
    
    configurator_stim_gen : if true generate
        type led_lookup_table_type is
            array(0 to 255) of
            std_ulogic_vector(7 downto 0);
        
        type state_type is (
            INIT,
            SENDING_SETTINGS,
            CALCULATING,
            CONF_LEDCOR_WAITING_FOR_BUSY,
            CONF_LEDCOR_WAITING_FOR_IDLE,
            CONF_LEDCOR_CONFIGURING_LED_CORRECTION,
            CONF_LEDEX_WAITING_FOR_BUSY,
            CONF_LEDEX_WAITING_FOR_IDLE,
            CONF_LEDEX_CONFIGURING_LED_COLOR_EXTRACTOR,
            IDLE
        );
        
        signal state            : state_type := INIT;
        signal counter          : unsigned(10 downto 0) := uns(1023, 11);
        signal settings_addr    : std_ulogic_vector(9 downto 0) := (others => '0');
    begin
        
        configurator_stim_proc : process(g_clk, g_rst)
        begin
            if g_rst='1' then
                conf_settings_wr_en     <= '0';
                conf_settings_data      <= x"00";
                conf_calculate          <= '0';
                conf_configure_ledex    <= '0';
                conf_configure_ledcor   <= '0';
                counter                 <= uns(1023, 11);
                settings_addr           <= (others => '0');
                start_settings_read     <= false;
            elsif rising_edge(g_clk) then
                conf_settings_wr_en     <= '0';
                conf_calculate          <= '0';
                conf_configure_ledex    <= '0';
                conf_configure_ledcor   <= '0';
                start_settings_read     <= false;
                
                case state is
                    
                    when INIT =>
                        counter             <= uns(1023, 11);
                        settings_addr       <= (others => '0');
                        start_settings_read <= true;
                        state               <= SENDING_SETTINGS;
                    
                    when SENDING_SETTINGS =>
                        conf_settings_addr  <= settings_addr;
                        conf_settings_wr_en <= fctrl_valid;
                        conf_settings_data  <= fctrl_dout;
                        if fctrl_valid='1' then
                            counter         <= counter-1;
                            settings_addr   <= settings_addr+1;
                        end if;
                        if counter(counter'high)='1' then
                            -- read 1k bytes
                            state   <= CALCULATING;
                        end if;
                    
                    when CALCULATING =>
                        conf_calculate  <= '1';
                        state           <= CONF_LEDCOR_WAITING_FOR_BUSY;
                    
                    when CONF_LEDCOR_WAITING_FOR_BUSY =>
                        if conf_busy='1' then
                            state   <= CONF_LEDCOR_WAITING_FOR_IDLE;
                        end if;
                    
                    when CONF_LEDCOR_WAITING_FOR_IDLE =>
                        if conf_busy='0' then
                            state   <= CONF_LEDCOR_CONFIGURING_LED_CORRECTION;
                        end if;
                    
                    when CONF_LEDCOR_CONFIGURING_LED_CORRECTION =>
                        conf_configure_ledcor   <= '1';
                        state                   <= CONF_LEDEX_WAITING_FOR_BUSY;
                    
                    when CONF_LEDEX_WAITING_FOR_BUSY =>
                        if conf_busy='1' then
                            state   <= CONF_LEDEX_WAITING_FOR_IDLE;
                        end if;
                    
                    when CONF_LEDEX_WAITING_FOR_IDLE =>
                        if conf_busy='0' then
                            state   <= CONF_LEDEX_CONFIGURING_LED_COLOR_EXTRACTOR;
                        end if;
                    
                    when CONF_LEDEX_CONFIGURING_LED_COLOR_EXTRACTOR =>
                        conf_configure_ledex    <= '1';
                        state                   <= IDLE;
                    
                    when IDLE =>
                        null;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
    -------------------------
    --- SPI Flash control ---
    -------------------------
    
    fctrl_clk   <= g_clk;
    fctrl_rst   <= g_rst;
    
    fctrl_miso  <= FLASH_MISO;
    
    SPI_FLASH_CONTROL_inst : entity work.SPI_FLASH_CONTROL
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            CLK_OUT_MULT    => FCTRL_CLK_MULT,
            CLK_OUT_DIV     => FCTRL_CLK_DIV,
            BUF_SIZE        => 1024
        )
        port map (
            CLK => fctrl_clk,
            RST => fctrl_rst,
            
            ADDR    => fctrl_addr,
            DIN     => fctrl_din,
            RD_EN   => fctrl_rd_en,
            WR_EN   => fctrl_wr_en,
            MISO    => fctrl_miso,
            
            DOUT    => fctrl_dout,
            VALID   => fctrl_valid,
            WR_ACK  => fctrl_wr_ack,
            BUSY    => fctrl_busy,
            FULL    => fctrl_full,
            MOSI    => fctrl_mosi,
            C       => fctrl_c,
            SN      => fctrl_sn
        );
    
    spi_flash_control_stim_gen : if true generate
        type state_type is (
            INIT,
            READING_SETTINGS
        );
        
        signal state    : state_type := INIT;
        signal counter  : unsigned(10 downto 0) := uns(1023, 11);
    begin
        
        fctrl_addr  <= SETTINGS_FLASH_ADDR;
        
        spi_flash_control_stim_proc : process(g_clk, g_rst)
        begin
            if g_rst='1' then
                state       <= INIT;
                fctrl_rd_en <= '0';
            elsif rising_edge(g_clk) then
                fctrl_rd_en <= '0';
                
                case state is
                    
                    when INIT =>
                        counter <= uns(1023, 11);
                        if start_settings_read then
                            state   <= READING_SETTINGS;
                        end if;
                    
                    when READING_SETTINGS =>
                        fctrl_rd_en <= '1';
                        if counter(counter'high)='1' then
                            state   <= INIT;
                        end if;
                        if fctrl_valid='1' then
                            counter <= counter-1;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
    -----------------------------
    --- IPROG reconfiguration ---
    -----------------------------
    
    IPROG_RECONF_gen : if ENABLE_IPROG_RECONF generate
    
        type rx_bitfile_addrs_type is array(0 to 1)
            of std_ulogic_vector(23 downto 0);
        
        constant rx_bitfile_addrs   : rx_bitfile_addrs_type := (
            RX0_BITFILE_ADDR,
            RX1_BITFILE_ADDR
        );
        
        -- Inputs
        signal iprog_clk    : std_ulogic := '0';
        signal iprog_en     : std_ulogic := '0';
        
    begin
        
        iprog_clk   <= g_clk;
        
        iprog_enable_proc : process(g_clk)
        begin
            if rising_edge(g_clk) then
                -- switch the bitfile if the inactive RX port gets connected
                iprog_en        <= rx_det_stable(1-RX_SEL) and not rx_det_stable_q(1-RX_SEL);
                rx_det_stable_q <= rx_det_stable;
            end if;
        end process;
        
        
        IPROG_RECONF_inst : entity work.iprog_reconf
            generic map (
                START_ADDR      => rx_bitfile_addrs(1-RX_SEL),
                FALLBACK_ADDR   => rx_bitfile_addrs(RX_SEL)
            )
            port map (
                CLK => iprog_clk,
                
                EN  => iprog_en
            );
    
    end generate;
    
end rtl;

