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
        RX_CHANNELS_IN_P    : in std_ulogic_vector(3 downto 0);
        RX_CHANNELS_IN_N    : in std_ulogic_vector(3 downto 0);
        RX_SDA              : inout std_ulogic := 'Z';
        RX_SCL              : inout std_ulogic := 'Z';
        RX_CEC              : inout std_ulogic := 'Z';
        RX_DET              : in std_ulogic;
        RX_EN               : out std_ulogic := '0';
        
        TX_CHANNELS_OUT_P   : out std_ulogic_vector(3 downto 0) := "0000";
        TX_CHANNELS_OUT_N   : out std_ulogic_vector(3 downto 0) := "0000";
        TX_SDA              : inout std_ulogic := 'Z';
        TX_SCL              : inout std_ulogic := 'Z';
        TX_CEC              : inout std_ulogic := 'Z';
        TX_EN               : out std_ulogic := '0';
        
        -- USB UART
        USB_TXD     : out std_ulogic := '0';
        USB_RXD     : in std_ulogic;
        USB_RTS     : out std_ulogic := '0';
        USB_CTS     : in std_ulogic;
        USB_RXLED   : in std_ulogic;
        USB_TXLED   : in std_ulogic;
        
        -- Blutooth UART
        BT_TXD  : out std_ulogic := '0';
        BT_RXD  : in std_ulogic;
        BT_RTS  : out std_ulogic := '0';
        BT_CTS  : in std_ulogic;
        
        -- LED strip
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
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
    
    signal rx_sda_in        : std_ulogic := '1';
    signal rx_scl_in        : std_ulogic := '1';
    signal rx_cec_in        : std_ulogic := '0';
    signal rx_edid_ready    : std_ulogic := '0';
    
    signal rx_channels_in   : std_ulogic_vector(3 downto 0) := "0000";
    signal tx_channels_out  : std_ulogic_vector(3 downto 0) := "0000";
    
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    -- Inputs
    signal eddc_m_edid_clk      : std_ulogic := '0';
    signal eddc_m_edid_rst      : std_ulogic := '0';
    signal eddc_m_edid_start    : std_ulogic := '0';

    -- BiDirs
    signal eddc_m_edid_sda_in   : std_ulogic := '1';
    signal eddc_m_edid_sda_out  : std_ulogic := '1';
    signal eddc_m_edid_scl_in   : std_ulogic := '1';
    signal eddc_m_edid_scl_out  : std_ulogic := '1';

    -- Outputs
    signal eddc_m_edid_block_number     : std_ulogic_vector(7 downto 0) := (others => '0');
    signal eddc_m_edid_busy             : std_ulogic := '0';
    signal eddc_m_edid_transm_error     : std_ulogic := '0';
    signal eddc_m_edid_data_out         : std_ulogic_vector(7 downto 0) := (others => '0');
    signal eddc_m_edid_data_out_valid   : std_ulogic := '0';
    signal eddc_m_edid_byte_index       : std_ulogic_vector(6 downto 0) := (others => '0');
    
    
    ----------------------------------------
    ------ MicroBlaze microcontroller ------
    ----------------------------------------
    
    component microblaze_mcs_v1_4
        port (
            Clk             : in std_logic;
            Reset           : in std_logic;
            UART_Rx         : in std_logic;
            UART_Tx         : out std_logic;
            GPO1            : out std_logic_vector(11 downto 0);
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
    signal microblaze_gpo1          : std_logic_vector(11 downto 0) := (others => '0');
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
    signal edid_ram_din         : std_ulogic_vector(7 downto 0) := (others => '0');
    
    -- Outputs
    signal edid_ram_dout    : std_ulogic_vector(7 downto 0) := (others => '0');
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    -- Inputs
    signal rxclk_clk_in : std_ulogic := '0';
    
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
    
    USB_TXD <= microblaze_txd when uart_select='0' else '0';
    USB_RTS <= microblaze_gpo1(10) when uart_select='0' else '0';
    
    BT_TXD  <= microblaze_txd when uart_select='1' else '0';
    BT_RTS  <= microblaze_gpo1(10) when uart_select='1' else '0';
    
    LEDS_CLK    <= ledctrl_leds_clk;
    LEDS_DATA   <= ledctrl_leds_data;
    
    g_rst   <= g_clk_stopped;
    
    uart_select <= microblaze_gpo1(11);
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    RX_EN   <= rx_edid_ready;
    
    -- drive low dominant I2C signals
    TX_SDA <= '0' when eddc_m_edid_sda_out='0' else 'Z';
    TX_SCL <= '0' when eddc_m_edid_scl_out='0' else 'Z';
    
    rx_sda_in   <= RX_SDA;
    rx_scl_in   <= RX_SCL;
    
    rx_edid_ready   <= microblaze_gpo1(9);
    
    TX_EN   <= rx_enc_data_valid;
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    diff_buf_gen : for i in 0 to 3 generate
        
        rx_channel_IBUFDS_inst : IBUFDS
            generic map (DIFF_TERM  => false)
            port map (
                I   => RX_CHANNELS_IN_P(i),
                IB  => RX_CHANNELS_IN_N(i),
                O   => rx_channels_in(i)
            );
        
        tx_channel_OBUFDS_inst : OBUFDS
            port map (
                I   => tx_channels_out(i),
                O   => TX_CHANNELS_OUT_P(i),
                OB  => TX_CHANNELS_OUT_N(i)
            );
        
    end generate;
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    eddc_m_edid_clk             <= g_clk;
    eddc_m_edid_rst             <= g_rst;
    eddc_m_edid_sda_in          <= TX_SDA;
    eddc_m_edid_scl_in          <= TX_SCL;
    eddc_m_edid_block_number    <= stdulv(microblaze_gpo1(7 downto 0));
    eddc_m_edid_start           <= microblaze_gpo1(8);
    
    DDC_EDID_MASTER_inst : entity work.DDC_EDID_MASTER
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD
        )
        port map (
            CLK => eddc_m_edid_clk,
            RST => eddc_m_edid_rst,
            
            SDA_IN  => eddc_m_edid_sda_in,
            SDA_OUT => eddc_m_edid_sda_out,
            SCL_IN  => eddc_m_edid_scl_in,
            SCL_OUT => eddc_m_edid_scl_out,
            
            START           => eddc_m_edid_start,
            BLOCK_NUMBER    => eddc_m_edid_block_number,
            
            BUSY            => eddc_m_edid_busy,
            TRANSM_ERROR    => eddc_m_edid_transm_error,
            DATA_OUT        => eddc_m_edid_data_out,
            DATA_OUT_VALID  => eddc_m_edid_data_out_valid,
            BYTE_INDEX      => eddc_m_edid_byte_index
        );
    
    
    ----------------------------------------
    ------ MicroBlaze microcontroller ------
    ----------------------------------------
    
    microblaze_clk  <= g_clk;
    microblaze_rst  <= g_rst;
    
    microblaze_rxd  <= USB_RXD when uart_select='0' else BT_RXD;
    
    microblaze_gpi1(4)              <= RX_DET;
    microblaze_gpi1(3)              <= rx_aux_data_valid;
    microblaze_gpi1(2)              <= eddc_m_edid_transm_error;
    microblaze_gpi1(1)              <= eddc_m_edid_busy;
    microblaze_gpi1(0)              <= USB_CTS when uart_select='0' else BT_CTS;
    
    microblaze_gpi2(16 downto 8)    <= stdlv(rx_aux_data);
    microblaze_gpi2(7 downto 0)     <= stdlv(edid_ram_dout);
    
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
    edid_ram_wr_en      <= eddc_m_edid_data_out_valid;
    edid_ram_wr_addr    <= eddc_m_edid_byte_index;
    edid_ram_din        <= eddc_m_edid_data_out;
    
    edid_ram_inst : entity work.DUAL_PORT_RAM
        generic map (
            WIDTH   => 8,
            DEPTH   => 128
        )
        port map (
            CLK         => edid_ram_clk,
            
            RD_ADDR     => edid_ram_rd_addr,
            WR_EN       => edid_ram_wr_en,
            WR_ADDR     => edid_ram_wr_addr,
            DIN         => edid_ram_din,
            
            DOUT    => edid_ram_dout
        );
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    rxclk_clk_in    <= rx_channels_in(3);

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
    rx_rst              <= not RX_DET;
    rx_clk_locked       <= rxclk_ioclk_locked;
    rx_serdesstrobe     <= rxclk_serdesstrobe;
    
    rx_TMDS_DECODER_inst : entity work.TMDS_DECODER
        port map (
            PIX_CLK         => rx_pix_clk,
            PIX_CLK_X2      => rx_pix_clk_x2,
            PIX_CLK_X10     => rx_pix_clk_x10,
            RST             => rx_rst,
            
            CLK_LOCKED      => rx_clk_locked,
            SERDESSTROBE    => rx_serdesstrobe,
            
            CHANNELS_IN => rx_channels_in(2 downto 0),
            
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

