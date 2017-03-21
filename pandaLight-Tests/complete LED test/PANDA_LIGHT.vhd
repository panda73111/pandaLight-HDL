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
        RX_SEL              : natural range 0 to 1 := 0;
        MAX_LED_COUNT       : positive := 64;
        MAX_FRAME_COUNT     : natural := 128;
        PANDALIGHT_MAGIC    : string := "PANDALIGHT";
        VERSION_MAJOR       : natural range 0 to 255 := 0;
        VERSION_MINOR       : natural range 0 to 255 := 1;
        G_CLK_MULT          : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV           : positive range 1 to 256 := 2;
        FCTRL_CLK_MULT      : positive :=  2; -- Flash clock: 20 MHz
        FCTRL_CLK_DIV       : positive :=  5;
        RX0_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"000000";
        RX1_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"060000";
        SETTINGS_FLASH_ADDR : std_ulogic_vector(23 downto 0) := x"0C0000";
        R_BITS              : positive range 5 to 12 := 8;
        G_BITS              : positive range 5 to 12 := 8;
        B_BITS              : positive range 5 to 12 := 8;
        DIM_BITS            : positive range 8 to 16 := 11; -- resolutions up to 2047x2047
        ACCU_BITS           : positive range 8 to 40 := 30 -- LED areas up to 2047x2047
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
        
        -- USB UART
        USB_RXD     : in std_ulogic;
        USB_TXD     : out std_ulogic := '1';
        USB_CTSN    : in std_ulogic;
        USB_RTSN    : out std_ulogic := '0';
        USB_DSRN    : in std_ulogic;
        USB_DTRN    : out std_ulogic := '0';
        USB_DCDN    : out std_ulogic := '0';
        USB_RIN     : out std_ulogic := '0';
        
        -- ESP32 UART
        ESP_CTS : in std_ulogic;
        ESP_RTS : out std_ulogic := '0';
        ESP_RXD : in std_ulogic;
        ESP_TXD : out std_ulogic := '1';
        ESP_IO0 : out std_ulogic := '0';
        ESP_EN  : out std_ulogic := '0';
        
        -- SPI Flash
        FLASH_MISO  : in std_ulogic;
        FLASH_MOSI  : out std_ulogic := '0';
        FLASH_CS    : out std_ulogic := '1';
        FLASH_SCK   : out std_ulogic := '0';
        
        -- LEDs
        LEDS_CLK    : out std_ulogic_vector(1 downto 0) := "00";
        LEDS_DATA   : out std_ulogic_vector(1 downto 0) := "00";
        
        -- PMOD
        PMOD0   : out std_ulogic_vector(3 downto 0) := x"0";
        PMOD1   : out std_ulogic_vector(3 downto 0) := x"0";
        PMOD2   : in std_ulogic_vector(3 downto 0);
        PMOD3   : out std_ulogic_vector(3 downto 0) := x"0"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    constant G_CLK_PERIOD   : real := 50.0 * real(G_CLK_DIV) / real(G_CLK_MULT);
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    signal pmod2_deb        : std_ulogic_vector(3 downto 0) := x"0";
    
    signal start_sysinfo_to_uart            : boolean := false;
    signal start_settings_read_from_flash   : boolean := false;
    signal start_settings_write_to_flash    : boolean := false;
    signal start_settings_read_from_uart    : boolean := false;
    signal start_settings_write_to_uart     : boolean := false;
    signal start_bitfile_read_from_uart     : boolean := false;
    
    signal bitfile_index    : unsigned(0 downto 0) := "0";
    signal bitfile_size     : unsigned(23 downto 0) := x"000000";
    
    signal usb_dsrn_deb         : std_ulogic := '0';
    signal usb_dsrn_deb_q       : std_ulogic := '0';
    signal usb_connected        : boolean := false;
    
    signal uart_rst         : std_ulogic := '0';
    signal uart_connected   : boolean := false;
    signal uart_din         : std_ulogic_vector(7 downto 0) := x"00";
    signal uart_din_valid   : std_ulogic := '0';
    signal uart_dout        : std_ulogic_vector(7 downto 0) := x"00";
    signal uart_dout_wr_en  : std_ulogic := '0';
    signal uart_dout_send   : std_ulogic := '0';
    
    signal reboot   : std_ulogic := '0';
    
    type rx_bitfile_addrs_type is array(0 to 1)
        of std_ulogic_vector(23 downto 0);
    
    constant rx_bitfile_addrs   : rx_bitfile_addrs_type := (
        RX0_BITFILE_ADDR,
        RX1_BITFILE_ADDR
    );
    
    
    ----------------------------
    --- HDMI related signals ---
    ----------------------------
    
    signal rx_det_sync          : std_ulogic_vector(1 downto 0) := "00";
    signal rx_det_stable        : std_ulogic_vector(1 downto 0) := "00";
    
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
    signal analyzer_width           : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal analyzer_height          : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal analyzer_interlaced      : std_ulogic := '0';
    signal analyzer_valid           : std_ulogic := '0';
    
    
    ----------------------------
    --- LED colour extractor ---
    ----------------------------
    
    -- Inputs
    signal ledex_clk    : std_ulogic := '0';
    signal ledex_rst    : std_ulogic := '0';
    
    signal ledex_cfg_clk    : std_ulogic := '0';
    signal ledex_cfg_addr   : std_ulogic_vector(4 downto 0) := "00000";
    signal ledex_cfg_wr_en  : std_ulogic := '0';
    signal ledex_cfg_data   : std_ulogic_vector(7 downto 0) := x"00";
    
    signal ledex_frame_vsync        : std_ulogic := '0';
    signal ledex_frame_rgb_wr_en    : std_ulogic := '0';
    signal ledex_frame_rgb          : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');
    
    -- Outputs
    signal ledex_led_vsync      : std_ulogic := '0';
    signal ledex_led_num        : std_ulogic_vector(7 downto 0) := x"00";
    signal ledex_led_rgb_valid  : std_ulogic := '0';  
    signal ledex_led_rgb        : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');
    
    
    ----------------------
    --- LED correction ---
    ----------------------
    
    signal lcor_clk : std_ulogic := '0';
    signal lcor_rst : std_ulogic := '0';
    
    signal lcor_cfg_clk     : std_ulogic := '0';
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
    
    signal lctrl_led_clk_in         : std_ulogic := '0';
    signal lctrl_leds_out_clk_in    : std_ulogic := '0';
    signal lctrl_rst                : std_ulogic := '0';
    
    signal lctrl_cfg_clk    : std_ulogic := '0';
    signal lctrl_cfg_wr_en  : std_ulogic := '0';
    signal lctrl_cfg_data   : std_ulogic_vector(7 downto 0) := x"00";
    
    signal lctrl_led_vsync      : std_ulogic := '0';
    signal lctrl_led_rgb        : std_ulogic_vector(23 downto 0) := x"000000";
    signal lctrl_led_rgb_wr_en  : std_ulogic := '0';
    
    signal lctrl_leds_out_clk_out   : std_ulogic := '0';
    signal lctrl_leds_out_data      : std_ulogic := '0';
    
    
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
    
    
    ------------------------------
    --- UART Bluetooth control ---
    ------------------------------
    
    -- Inputs
    signal btctrl_clk   : std_ulogic := '0';
    signal btctrl_rst   : std_ulogic := '0';
    
    signal btctrl_bt_cts    : std_ulogic := '0';
    signal btctrl_bt_rxd    : std_ulogic := '0';
    
    signal btctrl_din           : std_ulogic_vector(7 downto 0) := x"00";
    signal btctrl_din_wr_en     : std_ulogic := '0';
    signal btctrl_send_packet   : std_ulogic := '0';
    
    -- Outputs
    signal btctrl_bt_rts    : std_ulogic := '0';
    signal btctrl_bt_txd    : std_ulogic := '0';
    signal btctrl_bt_wake   : std_ulogic := '0';
    signal btctrl_bt_rstn   : std_ulogic := '0';
    
    signal btctrl_dout          : std_ulogic_vector(7 downto 0) := x"00";
    signal btctrl_dout_valid    : std_ulogic := '0';
    
    signal btctrl_connected : std_ulogic := '0';
    
    signal btctrl_mtu_size          : std_ulogic_vector(9 downto 0) := (others => '0');
    signal btctrl_mtu_size_valid    : std_ulogic := '0';
    
    signal btctrl_error : std_ulogic := '0';
    signal btctrl_busy  : std_ulogic := '0';
    
    
    ------------------------
    --- UART USB control ---
    ------------------------
    
    signal usbctrl_clk  : std_ulogic := '0';
    signal usbctrl_rst  : std_ulogic := '0';
    
    signal usbctrl_cts  : std_ulogic := '0';
    signal usbctrl_rts  : std_ulogic := '0';
    signal usbctrl_rxd  : std_ulogic := '0';
    signal usbctrl_txd  : std_ulogic := '0';
    
    signal usbctrl_din          : std_ulogic_vector(7 downto 0) := x"00";
    signal usbctrl_din_wr_en    : std_ulogic := '0';
    
    signal usbctrl_dout         : std_ulogic_vector(7 downto 0) := x"00";
    signal usbctrl_dout_valid   : std_ulogic := '0';
    
    signal usbctrl_full     : std_ulogic := '0';
    signal usbctrl_error    : std_ulogic := '0';
    signal usbctrl_busy     : std_ulogic := '0';
    
    
    --------------------
    --- configurator ---
    --------------------
    
    -- Inputs
    signal conf_clk : std_ulogic := '0';
    signal conf_rst : std_ulogic := '0';
    
    signal conf_calculate           : std_ulogic := '0';
    signal conf_configure_ledex     : std_ulogic := '0';
    signal conf_configure_ledcor    : std_ulogic := '0';
    signal conf_configure_ledcon    : std_ulogic := '0';
    
    signal conf_frame_width     : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal conf_frame_height    : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    signal conf_settings_addr   : std_ulogic_vector(9 downto 0) := (others => '0');
    signal conf_settings_wr_en  : std_ulogic := '0';
    signal conf_settings_din    : std_ulogic_vector(7 downto 0) := x"00";
    signal conf_settings_dout   : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal conf_cfg_sel_ledex   : std_ulogic := '0';
    signal conf_cfg_sel_ledcor  : std_ulogic := '0';
    signal conf_cfg_sel_ledcon  : std_ulogic := '0';
    
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
    signal fctrl_end_wr : std_ulogic := '0';
    signal fctrl_miso   : std_ulogic := '0';
    
    -- Outputs
    signal fctrl_dout   : std_ulogic_vector(7 downto 0) := x"00";
    signal fctrl_valid  : std_ulogic := '0';
    signal fctrl_wr_ack : std_ulogic := '0';
    signal fctrl_busy   : std_ulogic := '0';
    signal fctrl_full   : std_ulogic := '0';
    signal fctrl_afull  : std_ulogic := '0';
    signal fctrl_mosi   : std_ulogic := '0';
    signal fctrl_c      : std_ulogic := '0';
    signal fctrl_sn     : std_ulogic := '1';
    
    
    -----------------------------
    --- IPROG reconfiguration ---
    -----------------------------
    
    -- Inputs
    signal iprog_clk    : std_ulogic := '0';
    signal iprog_en     : std_ulogic := '0';
    
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
    
    g_rst   <= not g_clk_locked or pmod2_deb(0);
    
    usb_connected   <= usb_dsrn_deb='0';
    
    uart_rst        <= '1' when g_rst='1' or not uart_connected else '0';
    uart_connected  <= usb_connected or btctrl_connected='1';
    uart_din        <= btctrl_dout when btctrl_dout_valid='1' else usbctrl_dout;
    uart_din_valid  <= btctrl_dout_valid or usbctrl_dout_valid;
    
    FLASH_MOSI  <= fctrl_mosi;
    FLASH_CS    <= fctrl_sn;
    FLASH_SCK   <= fctrl_c;
    
    LEDS_CLK    <= lctrl_leds_clk & lctrl_leds_clk;
    LEDS_DATA   <= lctrl_leds_data & lctrl_leds_data;
    
    BT_TXD  <= btctrl_bt_txd;
    USB_TXD <= usbctrl_txd;
    
    USB_RTSN    <= not (usbctrl_rts and not fctrl_afull);
    BT_RTSN     <= not (btctrl_bt_rts and not fctrl_afull);
    
    BT_RSTN <= btctrl_bt_rstn;
    BT_WAKE <= btctrl_bt_wake;
    
    pmod0_DEBOUNCE_gen : for i in 0 to 3 generate
        
        pmod2_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 100
            )
            port map (
                CLK => g_clk,
                I   => PMOD2(i),
                O   => pmod2_deb(i)
            );
        
    end generate;
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- only enabled chips make 'DET' signals possible!
    RX_EN(RX_SEL)   <= tx_det_stable;
    RX_EN(1-RX_SEL) <= tx_det_stable;
    TX_EN           <= not g_rst;
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    rx_SIGNAL_SYNC_and_DEBOUNCE_gen : for i in 0 to 1 generate
        
        rx_det_SIGNAL_SYNC_inst : entity work.SIGNAL_SYNC
            port map (
                CLK => g_clk,
                
                DIN     => RX_DET(i),
                DOUT    => rx_det_sync(i)
            );
        
        rx_det_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 1500
            )
            port map (
                CLK => g_clk,
                
                I   => rx_det_sync(i),
                O   => rx_det_stable(i)
            );
    
    end generate;
    
    tx_det_SIGNAL_SYNC_inst : entity work.SIGNAL_SYNC
        port map (
            CLK => g_clk,
            
            DIN     => tx_det,
            DOUT    => tx_det_sync
        );
        
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
        generic map (
            DIM_BITS    => DIM_BITS
        )
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
    
    ledex_cfg_clk   <= g_clk;
    ledex_cfg_addr  <= conf_cfg_addr(ledex_cfg_addr'range);
    ledex_cfg_wr_en <= conf_cfg_wr_en and conf_cfg_sel_ledex;
    ledex_cfg_data  <= conf_cfg_data;
    
    ledex_frame_vsync       <= analyzer_positive_vsync;
    ledex_frame_rgb_wr_en   <= rx_rgb_valid;
    ledex_frame_rgb         <= rx_rgb;
    
    LED_COLOR_EXTRACTOR_inst : entity work.LED_COLOR_EXTRACTOR
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS,
            DIM_BITS        => DIM_BITS,
            ACCU_BITS       => ACCU_BITS
        )
        port map (
            CLK => ledex_clk,
            RST => ledex_rst,
            
            CFG_CLK     => ledex_cfg_clk,
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
    
    lcor_cfg_clk    <= g_clk;
    lcor_cfg_addr   <= conf_cfg_addr(lcor_cfg_addr'range);
    lcor_cfg_wr_en  <= conf_cfg_wr_en and conf_cfg_sel_ledcor;
    lcor_cfg_data   <= conf_cfg_data;
    
    lcor_led_in_vsync       <= ledex_led_vsync;
    lcor_led_in_num         <= ledex_led_num;
    lcor_led_in_rgb         <= ledex_led_rgb;
    lcor_led_in_rgb_wr_en   <= ledex_led_rgb_valid;
    
    LED_CORRECTION_inst : entity work.LED_CORRECTION
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            MAX_FRAME_COUNT => MAX_FRAME_COUNT
        )
        port map (
            CLK => lcor_clk,
            RST => lcor_rst,
            
            CFG_CLK     => lcor_cfg_clk,
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
    
    lctrl_led_clk_in        <= lcor_clk;
    lctrl_leds_out_clk_in   <= g_clk;
    lctrl_rst               <= lcor_rst or conf_cfg_sel_ledcon;
    
    lctrl_cfg_clk   <= g_clk;
    lctrl_cfg_wr_en <= conf_cfg_wr_en and conf_cfg_sel_ledcon;
    lctrl_cfg_data  <= conf_cfg_data;
    
    lctrl_led_vsync     <= lcor_led_out_vsync;
    lctrl_led_rgb       <= lcor_led_out_rgb;
    lctrl_led_rgb_wr_en <= lcor_led_out_rgb_valid;
    
    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            LEDS_OUT_CLK_IN_PERIOD          => G_CLK_PERIOD,
            WS2801_LEDS_OUT_CLK_OUT_PERIOD  => 1000.0, -- 1 MHz
            MAX_LED_COUNT                   => MAX_LED_COUNT
        )
        port map (
            LED_CLK_IN      => lctrl_led_clk_in,
            LEDS_OUT_CLK_IN => lctrl_leds_out_clk_in,
            RST             => lctrl_rst,
            
            CFG_CLK     => lctrl_cfg_clk,
            CFG_WR_EN   => lctrl_cfg_wr_en,
            CFG_DATA    => lctrl_cfg_data,
            
            LED_VSYNC       => lctrl_led_vsync,
            LED_RGB         => lctrl_led_rgb,
            LED_RGB_WR_EN   => lctrl_led_rgb_wr_en,
            
            LEDS_OUT_CLK_OUT    => lctrl_leds_out_clk_out,
            LEDS_OUT_DATA       => lctrl_leds_out_data
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
    
    
    ------------------------------
    --- UART Bluetooth control ---
    ------------------------------
    
    btctrl_clk  <= g_clk;
    btctrl_rst  <= g_rst;
    
    btctrl_bt_cts   <= not BT_CTSN;
    btctrl_bt_rxd   <= BT_RXD;
    
    btctrl_din          <= uart_dout;
    btctrl_din_wr_en    <= uart_dout_wr_en;
    btctrl_send_packet  <= uart_dout_send;
    
    UART_BLUETOOTH_CONTROL_inst : entity work.UART_BLUETOOTH_CONTROL
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            BUFFER_SIZE     => 1024
        )
        port map (
            CLK => btctrl_clk,
            RST => btctrl_rst,
            
            BT_CTS  => btctrl_bt_cts,
            BT_RTS  => btctrl_bt_rts,
            BT_RXD  => btctrl_bt_rxd,
            BT_TXD  => btctrl_bt_txd,
            BT_WAKE => btctrl_bt_wake,
            BT_RSTN => btctrl_bt_rstn,
            
            DIN         => btctrl_din,
            DIN_WR_EN   => btctrl_din_wr_en,
            SEND_PACKET => btctrl_send_packet,
            
            DOUT        => btctrl_dout,
            DOUT_VALID  => btctrl_dout_valid,
            
            CONNECTED   => btctrl_connected,
            
            MTU_SIZE        => btctrl_mtu_size,
            MTU_SIZE_VALID  => btctrl_mtu_size_valid,
            
            ERROR   => btctrl_error,
            BUSY    => btctrl_busy
        );
    
    
    ------------------------
    --- UART USB control ---
    ------------------------
    
    usbctrl_clk <= g_clk;
    usbctrl_rst <= uart_rst;
    
    usbctrl_cts <= not USB_CTSN;
    usbctrl_rxd <= USB_RXD;
    
    usbctrl_din         <= uart_dout;
    usbctrl_din_wr_en   <= uart_dout_wr_en;
    
    usb_dsrn_DEBOUNCE_inst : entity work.DEBOUNCE
        generic map (
            CYCLE_COUNT => 100
        )
        port map (
            CLK => g_clk,
            I   => USB_DSRN,
            O   => usb_dsrn_deb
        );
    
    UART_CONTROL_inst : entity work.UART_CONTROL
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            BUFFER_SIZE     => 2048
        )
        port map (
            CLK => usbctrl_clk,
            RST => usbctrl_rst,
            
            CTS => usbctrl_cts,
            RTS => usbctrl_rts,
            RXD => usbctrl_rxd,
            TXD => usbctrl_txd,
            
            DIN         => usbctrl_din,
            DIN_WR_EN   => usbctrl_din_wr_en,
            
            DOUT        => usbctrl_dout,
            DOUT_VALID  => usbctrl_dout_valid,
            
            FULL    => usbctrl_full,
            ERROR   => usbctrl_error,
            BUSY    => usbctrl_busy
        );
    
    
    uart_stim_gen : if true generate
        type cmd_eval_state_type is (
            WAITING_FOR_COMMAND,
            RECEIVING_DATA_FROM_UART,
            RECEIVING_BITFILE_INDEX_FROM_UART,
            RECEIVING_BITFILE_SIZE_FROM_UART
        );
        
        signal cmd_eval_state   : cmd_eval_state_type := WAITING_FOR_COMMAND;
        signal cmd_eval_counter : unsigned(23 downto 0) := uns(1023, 24);
        
        type data_handling_state_type is (
            WAITING_FOR_COMMAND,
            SENDING_PANDALIGHT_MAGIC_TO_UART,
            SENDING_MAJOR_VERSION_TO_UART,
            SENDING_MINOR_VERSION_TO_UART,
            WAITING_FOR_DATA,
            SENDING_SETTINGS_TO_UART
        );
        
        signal data_handling_state      : data_handling_state_type := WAITING_FOR_COMMAND;
        signal data_handling_counter    : unsigned(20 downto 0) := uns(1022, 21);
        signal magic_char_index         : unsigned(3 downto 0) := uns(1, 4);
        
        signal cmd_counter_expired  : boolean := false;
        signal data_counter_expired : boolean := false;
    begin
        
        cmd_counter_expired     <= cmd_eval_counter(cmd_eval_counter'high)='1';
        data_counter_expired    <= data_handling_counter(data_handling_counter'high)='1';
        
        uart_evaluation_proc : process(usbctrl_rst, usbctrl_clk)
        begin
            if usbctrl_rst='1' then
                cmd_eval_state                  <= WAITING_FOR_COMMAND;
                cmd_eval_counter                <= uns(1023, cmd_eval_counter'length);
                start_sysinfo_to_uart           <= false;
                start_settings_read_from_flash  <= false;
                start_settings_write_to_flash   <= false;
                start_settings_read_from_uart   <= false;
                start_settings_write_to_uart    <= false;
                start_bitfile_read_from_uart    <= false;
            elsif rising_edge(usbctrl_clk) then
                start_sysinfo_to_uart           <= false;
                start_settings_read_from_flash  <= false;
                start_settings_write_to_flash   <= false;
                start_settings_read_from_uart   <= false;
                start_settings_write_to_uart    <= false;
                start_bitfile_read_from_uart    <= false;
                case cmd_eval_state is
                    
                    when WAITING_FOR_COMMAND =>
                        if data_handling_state=WAITING_FOR_COMMAND and uart_din_valid='1' then
                            case uart_din is
                                when x"00" => -- send system information via UART
                                    start_sysinfo_to_uart           <= true;
                                when x"01" => -- reboot
                                    reboot                          <= '1';
                                when x"20" => -- load settings from flash
                                    start_settings_read_from_flash  <= true;
                                when x"21" => -- save settings to flash
                                    start_settings_write_to_flash   <= true;
                                when x"22" => -- receive settings from UART
                                    start_settings_read_from_uart   <= true;
                                    cmd_eval_counter    <= uns(1022, cmd_eval_counter'length);
                                    cmd_eval_state      <= RECEIVING_DATA_FROM_UART;
                                when x"23" => -- send settings to UART
                                    start_settings_write_to_uart    <= true;
                                when x"40" => -- receive bitfile from UART
                                    cmd_eval_state      <= RECEIVING_BITFILE_INDEX_FROM_UART;
                                when others =>
                                    null;
                            end case;
                        end if;
                    
                    when RECEIVING_DATA_FROM_UART =>
                        if uart_din_valid='1' then
                            cmd_eval_counter    <= cmd_eval_counter-1;
                            if cmd_counter_expired then
                                cmd_eval_state  <= WAITING_FOR_COMMAND;
                            end if;
                        end if;
                    
                    when RECEIVING_BITFILE_INDEX_FROM_UART =>
                        cmd_eval_counter    <= uns(1, cmd_eval_counter'length);
                        if uart_din_valid='1' then
                            bitfile_index   <= uns(uart_din(0 downto 0));
                            cmd_eval_state  <= RECEIVING_BITFILE_SIZE_FROM_UART;
                        end if;
                    
                    when RECEIVING_BITFILE_SIZE_FROM_UART =>
                        if uart_din_valid='1' then
                            cmd_eval_counter    <= cmd_eval_counter-1;
                            -- shift the bitfile size in from the right
                            bitfile_size        <= bitfile_size(15 downto 0) & uns(uart_din);
                            if cmd_counter_expired then
                                cmd_eval_counter                <= (
                                    bitfile_size(15 downto 0) & uns(uart_din))-2;
                                start_bitfile_read_from_uart    <= true;
                                cmd_eval_state                  <= RECEIVING_DATA_FROM_UART;
                            end if;
                        end if;
                    
                end case;
            end if;
        end process;
        
        uart_stim_proc : process(usbctrl_rst, usbctrl_clk)
        begin
            if usbctrl_rst='1' then
                data_handling_state     <= WAITING_FOR_COMMAND;
                data_handling_counter   <= uns(1022, data_handling_counter'length);
                magic_char_index        <= uns(1, magic_char_index'length);
                uart_dout_wr_en         <= '0';
                uart_dout_send          <= '0';
            elsif rising_edge(usbctrl_clk) then
                uart_dout_wr_en <= '0';
                uart_dout_send  <= '0';
                
                case data_handling_state is
                    
                    when WAITING_FOR_COMMAND =>
                        if start_sysinfo_to_uart then
                            data_handling_counter   <=
                                uns(PANDALIGHT_MAGIC'length-2, data_handling_counter'length);
                            magic_char_index        <= uns(1, magic_char_index'length);
                            data_handling_state     <= SENDING_PANDALIGHT_MAGIC_TO_UART;
                        end if;
                        if start_settings_write_to_uart then
                            data_handling_counter   <= uns(1022, data_handling_counter'length);
                            data_handling_state     <= WAITING_FOR_DATA;
                        end if;
                    
                    when SENDING_PANDALIGHT_MAGIC_TO_UART =>
                        uart_dout_wr_en         <= '1';
                        uart_dout               <= stdulv(PANDALIGHT_MAGIC(int(magic_char_index)));
                        magic_char_index        <= magic_char_index+1;
                        data_handling_counter   <= data_handling_counter-1;
                        if data_counter_expired then
                            data_handling_state <= SENDING_MAJOR_VERSION_TO_UART;
                        end if;
                    
                    when SENDING_MAJOR_VERSION_TO_UART =>
                        uart_dout_wr_en     <= '1';
                        uart_dout           <= stdulv(VERSION_MAJOR, 8);
                        data_handling_state <= SENDING_MINOR_VERSION_TO_UART;
                    
                    when SENDING_MINOR_VERSION_TO_UART =>
                        uart_dout_wr_en     <= '1';
                        uart_dout           <= stdulv(VERSION_MINOR, 8);
                        uart_dout_send      <= '1';
                        data_handling_state <= WAITING_FOR_COMMAND;
                    
                    when WAITING_FOR_DATA =>
                        data_handling_state <= SENDING_SETTINGS_TO_UART;
                    
                    when SENDING_SETTINGS_TO_UART =>
                        uart_dout_wr_en         <= '1';
                        uart_dout               <= conf_settings_dout;
                        data_handling_counter   <= data_handling_counter-1;
                        if data_counter_expired then
                            data_handling_state <= WAITING_FOR_COMMAND;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
    -------------------
    -- configurator ---
    -------------------
    
    conf_clk    <= g_clk;
    conf_rst    <= g_rst;
    
    conf_frame_width    <= analyzer_width;
    conf_frame_height   <= analyzer_height;
    
    CONFIGURATOR_inst : entity work.CONFIGURATOR
        port map (
            CLK => conf_clk,
            RST => conf_rst,
            
            CALCULATE           => conf_calculate,
            CONFIGURE_LEDEX     => conf_configure_ledex,
            CONFIGURE_LEDCOR    => conf_configure_ledcor,
            CONFIGURE_LEDCON    => conf_configure_ledcon,
            
            FRAME_WIDTH     => conf_frame_width,
            FRAME_HEIGHT    => conf_frame_height,
            
            CFG_SEL_LEDEX   => conf_cfg_sel_ledex,
            CFG_SEL_LEDCOR  => conf_cfg_sel_ledcor,
            CFG_SEL_LEDCON  => conf_cfg_sel_ledcon,
            
            SETTINGS_ADDR   => conf_settings_addr,
            SETTINGS_WR_EN  => conf_settings_wr_en,
            SETTINGS_DIN    => conf_settings_din,
            SETTINGS_DOUT   => conf_settings_dout,
            
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
            READING_SETTINGS_FROM_FLASH,
            CALCULATING,
            CALCULATING_WAITING_FOR_BUSY,
            CALCULATING_WAITING_FOR_IDLE,
            CONF_LEDEX_CONFIGURING_LED_COLOR_EXTRACTOR,
            CONF_LEDEX_WAITING_FOR_BUSY,
            CONF_LEDEX_WAITING_FOR_IDLE,
            CONF_LEDCOR_CONFIGURING_LED_CORRECTION,
            CONF_LEDCOR_WAITING_FOR_BUSY,
            CONF_LEDCOR_WAITING_FOR_IDLE,
            CONF_LEDCON_CONFIGURING_LED_CONTROL,
            CONF_LEDCON_WAITING_FOR_BUSY,
            CONF_LEDCON_WAITING_FOR_IDLE,
            IDLE,
            WRITING_SETTINGS_TO_FLASH,
            RECEIVING_SETTINGS_FROM_UART,
            SENDING_SETTINGS_TO_UART
        );
        
        signal state                : state_type := INIT;
        signal counter              : unsigned(10 downto 0) := uns(1023, 11);
        signal settings_addr        : std_ulogic_vector(9 downto 0) := (others => '0');
        signal init_read_finished   : boolean := false;
        signal config_valid         : boolean := false;
        
        signal counter_expired  : boolean := false;
    begin
        
        counter_expired <= counter(counter'high)='1';
        
        configurator_stim_proc : process(conf_rst, conf_clk)
        begin
            if conf_rst='1' then
                conf_settings_wr_en     <= '0';
                conf_settings_din       <= x"00";
                conf_calculate          <= '0';
                conf_configure_ledex    <= '0';
                conf_configure_ledcor   <= '0';
                conf_configure_ledcon   <= '0';
                counter                 <= uns(1023, 11);
                settings_addr           <= (others => '0');
                conf_settings_addr      <= (others => '0');
            elsif rising_edge(conf_clk) then
                conf_settings_wr_en     <= '0';
                conf_calculate          <= '0';
                conf_configure_ledex    <= '0';
                conf_configure_ledcor   <= '0';
                conf_configure_ledcon   <= '0';
                
                if analyzer_valid='0' then
                    config_valid    <= false;
                end if;
                
                case state is
                    
                    when INIT =>
                        counter         <= uns(1023, counter'length);
                        settings_addr   <= (others => '0');
                        state           <= READING_SETTINGS_FROM_FLASH;
                        if init_read_finished then
                            state   <= CALCULATING;
                        end if;
                    
                    when READING_SETTINGS_FROM_FLASH =>
                        conf_settings_addr  <= settings_addr;
                        conf_settings_wr_en <= fctrl_valid;
                        conf_settings_din   <= fctrl_dout;
                        if fctrl_valid='1' then
                            counter         <= counter-1;
                            settings_addr   <= settings_addr+1;
                        end if;
                        if counter_expired then
                            -- read 1k bytes
                            init_read_finished  <= true;
                            state               <= CALCULATING;
                        end if;
                    
                    when CALCULATING =>
                        conf_calculate  <= '1';
                        state           <= CALCULATING_WAITING_FOR_BUSY;
                    
                    when CALCULATING_WAITING_FOR_BUSY =>
                        if conf_busy='1' then
                            state   <= CALCULATING_WAITING_FOR_IDLE;
                        end if;
                    
                    when CALCULATING_WAITING_FOR_IDLE =>
                        if conf_busy='0' then
                            state   <= CONF_LEDEX_CONFIGURING_LED_COLOR_EXTRACTOR;
                        end if;
                    
                    when CONF_LEDEX_CONFIGURING_LED_COLOR_EXTRACTOR =>
                        conf_configure_ledex    <= '1';
                        state                   <= CONF_LEDEX_WAITING_FOR_BUSY;
                    
                    when CONF_LEDEX_WAITING_FOR_BUSY =>
                        if conf_busy='1' then
                            state   <= CONF_LEDEX_WAITING_FOR_IDLE;
                        end if;
                    
                    when CONF_LEDEX_WAITING_FOR_IDLE =>
                        if conf_busy='0' then
                            state   <= CONF_LEDCOR_CONFIGURING_LED_CORRECTION;
                        end if;
                    
                    when CONF_LEDCOR_CONFIGURING_LED_CORRECTION =>
                        conf_configure_ledcor   <= '1';
                        state                   <= CONF_LEDCOR_WAITING_FOR_BUSY;
                    
                    when CONF_LEDCOR_WAITING_FOR_BUSY =>
                        if conf_busy='1' then
                            state   <= CONF_LEDCOR_WAITING_FOR_IDLE;
                        end if;
                    
                    when CONF_LEDCOR_WAITING_FOR_IDLE =>
                        if conf_busy='0' then
                            state   <= CONF_LEDCON_CONFIGURING_LED_CONTROL;
                        end if;
                    
                    when CONF_LEDCON_CONFIGURING_LED_CONTROL =>
                        conf_configure_ledcon   <= '1';
                        state                   <= CONF_LEDCON_WAITING_FOR_BUSY;
                    
                    when CONF_LEDCON_WAITING_FOR_BUSY =>
                        if conf_busy='1' then
                            state   <= CONF_LEDCON_WAITING_FOR_IDLE;
                        end if;
                    
                    when CONF_LEDCON_WAITING_FOR_IDLE =>
                        if conf_busy='0' then
                            config_valid    <= true;
                            state           <= IDLE;
                        end if;
                    
                    when IDLE =>
                        counter             <= uns(1023, counter'length);
                        settings_addr       <= (others => '0');
                        conf_settings_addr  <= (others => '0');
                        if not config_valid and analyzer_valid='1' then
                            state   <= CALCULATING;
                        end if;
                        if start_settings_read_from_flash then
                            state   <= READING_SETTINGS_FROM_FLASH;
                        end if;
                        if start_settings_write_to_flash then
                            state   <= WRITING_SETTINGS_TO_FLASH;
                        end if;
                        if start_settings_read_from_uart then
                            state   <= RECEIVING_SETTINGS_FROM_UART;
                        end if;
                        if start_settings_write_to_uart then
                            state   <= SENDING_SETTINGS_TO_UART;
                        end if;
                    
                    when WRITING_SETTINGS_TO_FLASH =>
                        conf_settings_addr  <= settings_addr;
                        counter             <= counter-1;
                        settings_addr       <= settings_addr+1;
                        if counter_expired then
                            -- wrote 1k bytes
                            state   <= IDLE;
                        end if;
                    
                    when RECEIVING_SETTINGS_FROM_UART =>
                        conf_settings_addr  <= settings_addr;
                        conf_settings_wr_en <= uart_din_valid;
                        conf_settings_din   <= uart_din;
                        if uart_din_valid='1' then
                            counter         <= counter-1;
                            settings_addr   <= settings_addr+1;
                        end if;
                        if counter_expired then
                            -- received 1k bytes
                            state   <= CALCULATING;
                        end if;
                    
                    when SENDING_SETTINGS_TO_UART =>
                        conf_settings_addr  <= conf_settings_addr+1;
                        counter             <= counter-1;
                        if counter_expired then
                            -- sent 1k bytes
                            state   <= IDLE;
                        end if;
                    
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
            CLK_IN_PERIOD       => G_CLK_PERIOD,
            CLK_OUT_MULT        => FCTRL_CLK_MULT,
            CLK_OUT_DIV         => FCTRL_CLK_DIV,
            BUFFER_SIZE         => 2048,
            BUFFER_AFULL_COUNT  => 1024
        )
        port map (
            CLK => fctrl_clk,
            RST => fctrl_rst,
            
            ADDR    => fctrl_addr,
            DIN     => fctrl_din,
            RD_EN   => fctrl_rd_en,
            WR_EN   => fctrl_wr_en,
            END_WR  => fctrl_end_wr,
            MISO    => fctrl_miso,
            
            DOUT    => fctrl_dout,
            VALID   => fctrl_valid,
            WR_ACK  => fctrl_wr_ack,
            BUSY    => fctrl_busy,
            FULL    => fctrl_full,
            AFULL   => fctrl_afull,
            MOSI    => fctrl_mosi,
            C       => fctrl_c,
            SN      => fctrl_sn
        );
    
    spi_flash_control_stim_gen : if true generate
        type state_type is (
            INIT,
            IDLE,
            READING_DATA,
            WRITING_SETTINGS,
            WRITING_BITFILE,
            WAITING_FOR_IDLE
        );
        
        signal state    : state_type := INIT;
        signal counter  : unsigned(23 downto 0) := uns(1023, 24);
        
        signal bitfile_address  : std_ulogic_vector(23 downto 0) := x"000000";
    begin
        
        bitfile_address <= RX0_BITFILE_ADDR when bitfile_index=0 else RX1_BITFILE_ADDR;
        
        spi_flash_control_stim_proc : process(fctrl_rst, fctrl_clk)
            variable next_state : state_type := INIT;
        begin
            if fctrl_rst='1' then
                state           <= INIT;
                fctrl_rd_en     <= '0';
                fctrl_wr_en     <= '0';
                fctrl_end_wr    <= '0';
            elsif rising_edge(fctrl_clk) then
                fctrl_rd_en     <= '0';
                fctrl_wr_en     <= '0';
                fctrl_end_wr    <= '0';
                
                case state is
                    
                    when INIT =>
                        state   <= READING_DATA;
                    
                    when IDLE =>
                        counter     <= uns(1023, counter'length);
                        fctrl_addr  <= SETTINGS_FLASH_ADDR;
                        
                        next_state  := state;
                        if start_settings_read_from_flash then
                            next_state  := READING_DATA;
                        end if;
                        if start_settings_write_to_flash then
                            next_state  := WRITING_SETTINGS;
                        end if;
                        if start_bitfile_read_from_uart then
                            counter     <= resize(bitfile_size-2, counter'length);
                            fctrl_addr  <= bitfile_address;
                            next_state  := WRITING_BITFILE;
                        end if;
                        state   <= next_state;
                    
                    when READING_DATA =>
                        if counter(counter'high)='1' then
                            state   <= IDLE;
                        else
                            fctrl_rd_en <= '1';
                        end if;
                        if fctrl_valid='1' then
                            counter <= counter-1;
                        end if;
                    
                    when WRITING_SETTINGS =>
                        fctrl_din   <= conf_settings_dout;
                        if uart_din_valid='1' then
                            counter     <= counter-1;
                            fctrl_wr_en <= '1';                        
                            if counter(counter'high)='1' then
                                state   <= IDLE;
                            end if;
                        end if;
                    
                    when WRITING_BITFILE =>
                        fctrl_din   <= uart_din;
                        if uart_din_valid='1' then
                            counter     <= counter-1;
                            fctrl_wr_en <= '1';
                            if counter(counter'high)='1' then
                                state   <= WAITING_FOR_IDLE;
                            end if;
                        end if;
                    
                    when WAITING_FOR_IDLE =>
                        fctrl_end_wr    <= '1';
                        if fctrl_busy='0' then
                            state   <= IDLE;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
    -----------------------------
    --- IPROG reconfiguration ---
    -----------------------------
    
    iprog_clk   <= g_clk;
    
    iprog_enable_proc : process(g_clk)
    begin
        if rising_edge(g_clk) then
            -- switch the bitfile if only the inactive RX port is connected, or a reboot is needed
            iprog_en    <= (not rx_det_stable(RX_SEL) and rx_det_stable(1-RX_SEL)) or reboot;
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
    
end rtl;

