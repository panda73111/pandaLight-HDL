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
        MAX_LED_COUNT       : natural := 100;
        MAX_LED_BUFFER_SIZE : natural := 1024
    );
    port (
        CLK20   : in std_ulogic;
        
        -- HDMI
        RX0_CHANNELS_IN_P   : in std_ulogic_vector(3 downto 0);
        RX0_CHANNELS_IN_N   : in std_ulogic_vector(3 downto 0);
        RX0_SDA             : inout std_ulogic := 'Z';
        RX0_SCL             : inout std_ulogic := 'Z';
        RX0_DET             : in std_ulogic;
        
        TX0_CHANNELS_OUT_P  : out std_ulogic_vector(3 downto 0) := "0000";
        TX0_CHANNELS_OUT_N  : out std_ulogic_vector(3 downto 0) := "0000";
        
        -- USB UART
        USB_TXD     : out std_ulogic;
        USB_RXD     : in std_ulogic;
        USB_RTS     : out std_ulogic;
        USB_CTS     : in std_ulogic;
        USB_RXLED   : in std_ulogic;
        USB_TXLED   : in std_ulogic;
        
        -- LED strip
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    constant G_CLK_PERIOD   : real := 10.0; -- in nano seconds
    
    -- 1 MHz, 100 LEDs: 2.9 ms latency, ~344 fps
    constant WS2801_CLK_PERIOD  : real := 1000.0;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_stopped    : std_ulogic := '0';
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    -- Inputs
    signal e_ddc_edid_clk   : std_ulogic := '0';
    signal e_ddc_edid_rst   : std_ulogic := '0';
    signal e_ddc_edid_start : std_ulogic := '0';

    -- BiDirs
    signal e_ddc_edid_sda_in    : std_ulogic := '1';
    signal e_ddc_edid_sda_out   : std_ulogic := '1';
    signal e_ddc_edid_scl_in    : std_ulogic := '1';
    signal e_ddc_edid_scl_out   : std_ulogic := '1';

    -- Outputs
    signal e_ddc_edid_block_number      : std_ulogic_vector(7 downto 0) := (others => '0');
    signal e_ddc_edid_busy              : std_ulogic := '0';
    signal e_ddc_edid_transm_error      : std_ulogic := '0';
    signal e_ddc_edid_data_out          : std_ulogic_vector(7 downto 0) := (others => '0');
    signal e_ddc_edid_data_out_valid    : std_ulogic := '0';
    signal e_ddc_edid_byte_index        : std_ulogic_vector(6 downto 0) := (others => '0');
    
    
    ----------------------------------------
    ------ MicroBlaze microcontroller ------
    ----------------------------------------
    
    component microblaze_mcs_v1_4
        port (
            Clk             : in std_logic;
            Reset           : in std_logic;
            UART_Rx         : in std_logic;
            UART_Tx         : out std_logic;
            GPO1            : out std_logic_vector(8 downto 0);
            GPO2            : out std_logic_vector(6 downto 0);
            GPO3            : out std_logic_vector(26 downto 0);
            GPI1            : in std_logic_vector(4 downto 0);
            GPI1_Interrupt  : out std_logic;
            GPI2            : in std_logic_vector(16 downto 0);
            GPI2_Interrupt  : out std_logic;
            INTC_IRQ        : out std_logic
        );
    end component;
    
    -- Inputs
    signal microblaze_clk   : std_logic := '0';
    signal microblaze_rst   : std_logic := '0';
    signal microblaze_rxd   : std_logic := '0';
    signal microblaze_gpi1  : std_logic_vector(4 downto 0) := (others => '0');
    signal microblaze_gpi2  : std_logic_vector(16 downto 0) := (others => '0');
    
    -- Outputs
    signal microblaze_txd           : std_logic := '0';
    signal microblaze_gpo1          : std_logic_vector(8 downto 0) := (others => '0');
    signal microblaze_gpo2          : std_logic_vector(6 downto 0) := (others => '0');
    signal microblaze_gpo3          : std_logic_vector(26 downto 0) := (others => '0');
    signal microblaze_gpi1_int      : std_logic := '0';
    signal microblaze_gpi2_int      : std_logic := '0';
    
    
    ----------------------
    ------ EDID RAM ------
    ----------------------
    
    -- Inputs
    signal edid_ram_clk         : std_ulogic := '0';
    signal edid_ram_rd_addr     : std_ulogic_vector(6 downto 0) := (others => '0');
    signal edid_ram_wr_en       : std_ulogic := '0';
    signal edid_ram_wr_addr     : std_ulogic_vector(6 downto 0) := (others => '0');
    signal edid_ram_data_in     : std_ulogic_vector(7 downto 0) := (others => '0');
    
    -- Outputs
    signal edid_ram_data_out    : std_ulogic_vector(7 downto 0) := (others => '0');
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    -- Inputs
    signal rxclk_clk_in : std_ulogic := '0';
    
    -- Outputs
    signal rxclk_clk_out0       : std_ulogic := '0';
    signal rxclk_clk_out1       : std_ulogic := '0';
    signal rxclk_clk_out2       : std_ulogic := '0';
    signal rxclk_ioclk_out      : std_ulogic := '0';
    signal rxclk_ioclk_locked   : std_ulogic := '0';
    signal rxclk_serdesstrobe   : std_ulogic := '0';
    
    
    --------------------
    --- HDMI Decoder ---
    --------------------
    
    -- Inputs
    signal rx0_pix_clk      : std_ulogic := '0';
    signal rx0_pix_clk_x2   : std_ulogic := '0';
    signal rx0_pix_clk_x10  : std_ulogic := '0';
    signal rx0_rst          : std_ulogic := '0';
    
    signal rx0_clk_locked   : std_ulogic := '0';
    signal rx0_serdesstrobe : std_ulogic := '0';
    
    signal rx0_ch_in_p  : std_ulogic_vector(2 downto 0) := "000";
    signal rx0_ch_in_n  : std_ulogic_vector(2 downto 0) := "111";
    
    -- Outputs
    signal rx0_vsync            : std_ulogic := '0';
    signal rx0_hsync            : std_ulogic := '0';
    signal rx0_rgb              : std_ulogic_vector(23 downto 0) := x"000000";
    signal rx0_aux_data         : std_ulogic_vector(8 downto 0) := (others => '0');
    signal rx0_aux_data_valid   : std_ulogic := '0';
    
    
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
--    signal ledex_led_num    : std_ulogic_vector(7 downto 0) := x"00";
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
    
    signal ledcorr_led_vsync_in     : std_ulogic := '0';
    signal ledcorr_led_rgb_in_wr_en : std_ulogic := '0';
    signal ledcorr_led_rgb_in       : std_ulogic_vector(23 downto 0) := x"000000";
    
    -- Outputs
    signal ledcorr_led_vsync_out        : std_ulogic := '0';
    signal ledcorr_led_rgb_out_valid    : std_ulogic := '0';
    signal ledcorr_led_rgb_out          : std_ulogic_vector(23 downto 0) := x"000000";
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLKMAN_inst : entity work.CLKMAN
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            MULTIPLIER      => 5,
            DIVISOR         => 1
        )
        port map (
            CLK_IN          => CLK20,
            CLK_OUT         => g_clk,
            CLK_OUT_STOPPED => g_clk_stopped
        );
    
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    USB_TXD <= microblaze_txd;
    USB_RTS <= microblaze_gpo1(0);
    
    LEDS_CLK    <= ledctrl_leds_clk;
    LEDS_DATA   <= ledctrl_leds_data;
    
    g_rst   <= g_clk_stopped;
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- drive low dominant I2C signals
    RX0_SDA <= '0' when e_ddc_edid_sda_out = '0' else 'Z';
    RX0_SCL <= '0' when e_ddc_edid_scl_out = '0' else 'Z';
    
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    e_ddc_edid_clk          <= g_clk;
    e_ddc_edid_rst          <= g_rst;
    e_ddc_edid_sda_in       <= RX0_SDA;
    e_ddc_edid_scl_in       <= RX0_SCL;
    e_ddc_edid_block_number <= stdulv(microblaze_gpo1(7 downto 0));
    e_ddc_edid_start        <= microblaze_gpo1(8);
    
    DDC_EDID_MASTER_inst : entity work.DDC_EDID_MASTER
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD
        )
        port map (
            CLK => e_ddc_edid_clk,
            RST => e_ddc_edid_rst,
            
            SDA_IN  => e_ddc_edid_sda_in,
            SDA_OUT => e_ddc_edid_sda_out,
            SCL_IN  => e_ddc_edid_scl_in,
            SCL_OUT => e_ddc_edid_scl_out,
            
            START           => e_ddc_edid_start,
            BLOCK_NUMBER    => e_ddc_edid_block_number,
            
            BUSY            => e_ddc_edid_busy,
            TRANSM_ERROR    => e_ddc_edid_transm_error,
            DATA_OUT        => e_ddc_edid_data_out,
            DATA_OUT_VALID  => e_ddc_edid_data_out_valid,
            BYTE_INDEX      => e_ddc_edid_byte_index
        );
    
    
    ----------------------------------------
    ------ MicroBlaze microcontroller ------
    ----------------------------------------
    
    microblaze_clk  <= g_clk;
    microblaze_rst  <= g_rst;
    
    microblaze_rxd  <= USB_RXD;
    
    microblaze_gpi1(4)              <= rx0_aux_data_valid;
    microblaze_gpi1(3)              <= rx0_det;
    microblaze_gpi1(2)              <= e_ddc_edid_transm_error;
    microblaze_gpi1(1)              <= e_ddc_edid_busy;
    microblaze_gpi1(0)              <= USB_CTS;
    
    microblaze_gpi2(16 downto 8)    <= stdlv(rx0_aux_data);
    microblaze_gpi2(7 downto 0)     <= stdlv(edid_ram_data_out);
    
    microblaze_inst : microblaze_mcs_v1_4
        port map (
            Clk             => microblaze_clk,
            Reset           => microblaze_rst,
            UART_Rx         => microblaze_rxd,
            UART_Tx         => microblaze_txd,
            GPO1            => microblaze_gpo1,
            GPO2            => microblaze_gpo2,
            GPO3            => microblaze_gpo3,
            GPI1            => microblaze_gpi1,
            GPI2            => microblaze_gpi2
        );
    
    
    ----------------------
    ------ EDID RAM ------
    ----------------------
    
    edid_ram_clk        <= g_clk;
    edid_ram_rd_addr    <= stdulv(microblaze_gpo2(6 downto 0));
    edid_ram_wr_en      <= e_ddc_edid_data_out_valid;
    edid_ram_wr_addr    <= e_ddc_edid_byte_index;
    edid_ram_data_in    <= e_ddc_edid_data_out;
    
    edid_ram_inst : entity work.DUAL_PORT_RAM
        generic map (
            ADDR_WIDTH  => 7,
            DATA_WIDTH  => 8
        )
        port map (
            CLK         => edid_ram_clk,
            RD_ADDR     => edid_ram_rd_addr,
            WR_EN       => edid_ram_wr_en,
            WR_ADDR     => edid_ram_wr_addr,
            DATA_IN     => edid_ram_data_in,
            DATA_OUT    => edid_ram_data_out
        );
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    rx0_IBUFDS_inst : IBUFDS
        generic map (
            DIFF_TERM   => false
        )
        port map (
            I   => RX0_CHANNELS_IN_P(3),
            IB  => RX0_CHANNELS_IN_N(3),
            O   => rxclk_clk_in
        );
    
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
            CLK_OUT0        => rxclk_clk_out0,
            CLK_OUT1        => rxclk_clk_out1,
            CLK_OUT2        => rxclk_clk_out2,
            IOCLK_OUT       => rxclk_ioclk_out,
            IOCLK_LOCKED    => rxclk_ioclk_locked,
            SERDESSTROBE    => rxclk_serdesstrobe
        );
    
    
    --------------------
    --- HDMI Decoder ---
    --------------------
    
    rx0_pix_clk         <= rxclk_clk_out2;
    rx0_pix_clk_x2      <= rxclk_clk_out1;
    rx0_pix_clk_x10     <= rxclk_ioclk_out;
    rx0_rst             <= not RX0_DET;
    rx0_clk_locked      <= rxclk_ioclk_locked;
    rx0_serdesstrobe    <= rxclk_serdesstrobe;
    
    rx0_ch_in_p         <= RX0_CHANNELS_IN_P(2 downto 0);
    rx0_ch_in_n         <= RX0_CHANNELS_IN_N(2 downto 0);
    
    TMDS_DECODER_inst : entity work.TMDS_DECODER
        port map (
            PIX_CLK         => rx0_pix_clk,
            PIX_CLK_X2      => rx0_pix_clk_x2,
            PIX_CLK_X10     => rx0_pix_clk_x10,
            RST             => rx0_rst,
            
            CLK_LOCKED      => rx0_clk_locked,
            SERDESSTROBE    => rx0_serdesstrobe,
            
            CHANNELS_IN_P   => rx0_ch_in_p,
            CHANNELS_IN_N   => rx0_ch_in_n,
            
            VSYNC           => rx0_vsync,
            HSYNC           => rx0_hsync,
            RGB             => rx0_rgb,
            AUX_DATA        => rx0_aux_data,
            AUX_DATA_VALID  => rx0_aux_data_valid
        );
    
    
    ---------------------------
    --- LED color extractor ---
    ---------------------------
    
    ledex_clk   <= rx0_pix_clk;
    ledex_rst   <= rx0_rst;
    
    ledex_cfg_addr  <= stdulv(microblaze_gpo3(11 downto 8));
    ledex_cfg_wr_en <= stdul(microblaze_gpo3(12));
    ledex_cfg_data  <= stdulv(microblaze_gpo3(7 downto 0));
    
    ledex_frame_vsync   <= rx0_vsync;
    ledex_frame_hsync   <= rx0_hsync;
    
    ledex_frame_rgb <= rx0_rgb;
    
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
--            LED_NUM     => ledex_led_num,
            LED_RGB     => ledex_led_rgb
        );
    
    
    -------------------
    --- LED control ---
    -------------------
    
    ledctrl_clk <= rx0_pix_clk;
    ledctrl_rst <= rx0_rst;
    
    ledctrl_mode    <= stdulv(microblaze_gpo3(14 downto 13));
    
    ledctrl_led_vsync       <= ledcorr_led_vsync_out;
    ledctrl_led_rgb         <= ledcorr_led_rgb_out;
    ledctrl_led_rgb_wr_en   <= ledcorr_led_rgb_out_valid;
    
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
    
    ledcorr_clk <= rx0_pix_clk;
    ledcorr_rst <= rx0_rst;
    
    ledcorr_cfg_addr    <= stdulv(microblaze_gpo3(25 downto 24));
    ledcorr_cfg_wr_en   <= stdul(microblaze_gpo3(26));
    ledcorr_cfg_data    <= stdulv(microblaze_gpo3(23 downto 16));
    
    ledcorr_led_vsync_in        <= ledex_led_vsync;
    ledcorr_led_rgb_in_wr_en    <= ledex_led_valid;
    ledcorr_led_rgb_in          <= ledex_led_rgb;
    
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
            
            LED_VSYNC_IN        => ledcorr_led_vsync_in,
            LED_RGB_IN_WR_EN    => ledcorr_led_rgb_in_wr_en,
            LED_RGB_IN          => ledcorr_led_rgb_in,
            
            LED_VSYNC_OUT       => ledcorr_led_vsync_out,
            LED_RGB_OUT_VALID   => ledcorr_led_rgb_out_valid,
            LED_RGB_OUT         => ledcorr_led_rgb_out
        );
    
end rtl;

