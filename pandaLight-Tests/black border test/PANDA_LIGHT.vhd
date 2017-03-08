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
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;
use work.txt_util.all;

entity PANDA_LIGHT is
    generic (
        MAX_LED_CNT         : natural := 512;
        PANDALIGHT_MAGIC    : string := "PL";
        VERSION_MAJOR       : natural range 0 to 255 := 0;
        VERSION_MINOR       : natural range 0 to 255 := 1;
        G_CLK_MULT          : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV           : positive range 1 to 256 := 2;
        FCTRL_CLK_MULT      : positive :=  2; -- Flash clock: 20 MHz
        FCTRL_CLK_DIV       : positive :=  5;
        SETTINGS_FLASH_ADDR : std_ulogic_vector(23 downto 0) := x"0C0000";
        R_BITS              : positive range 5 to 12 := 8;
        G_BITS              : positive range 5 to 12 := 8;
        B_BITS              : positive range 5 to 12 := 8;
        DIM_BITS            : positive range 8 to 16 := 11; -- resolutions up to 2047x2047
        UART_BAUD_RATE      : positive := 921_600
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
        PMOD0   : in std_ulogic_vector(3 downto 0);
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
    
    signal pmod0_deb        : std_ulogic_vector(3 downto 0) := x"0";
    signal blinker          : std_ulogic := '0';
    signal blink_counter    : unsigned(24 downto 0) := (others => '0');
    
    signal start_settings_read_from_uart    : boolean := false;
    
    signal configurator_idle    : boolean := true;
    signal flash_control_idle   : boolean := true;
    
    signal usb_dsrn_deb         : std_ulogic := '0';
    signal usb_dsrn_deb_q       : std_ulogic := '0';
    signal usb_connected        : boolean := false;
    
    signal uart_clk         : std_ulogic := '0';
    signal uart_rst         : std_ulogic := '0';
    signal uart_connected   : boolean := false;
    signal uart_din         : std_ulogic_vector(7 downto 0) := x"00";
    signal uart_din_valid   : std_ulogic := '0';
    signal uart_dout        : std_ulogic_vector(7 downto 0) := x"00";
    signal uart_dout_wr_en  : std_ulogic := '0';
    signal uart_dout_send   : std_ulogic := '0';
    
    
    ----------------------------
    --- HDMI related signals ---
    ----------------------------
    
    signal rx_det_sync      : std_ulogic := '0';
    signal rx_det_stable    : std_ulogic := '0';
    
    signal rx_channels_in   : std_ulogic_vector(3 downto 0) := x"0";
    
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
    
    
    ------------------------
    --- USB UART control ---
    ------------------------
    
    -- Inputs
    signal usbctrl_clk  : std_ulogic := '0';
    signal usbctrl_rst  : std_ulogic := '0';
    
    signal usbctrl_cts  : std_ulogic := '0';
    signal usbctrl_rxd  : std_ulogic := '0';
    
    signal usbctrl_din          : std_ulogic_vector(7 downto 0) := x"00";
    signal usbctrl_din_wr_en    : std_ulogic := '0';
    
    -- Outputs
    signal usbctrl_rts  : std_ulogic := '0';
    signal usbctrl_txd  : std_ulogic := '0';
    
    signal usbctrl_dout         : std_ulogic_vector(7 downto 0) := x"00";
    signal usbctrl_dout_valid   : std_ulogic := '0';
    
    signal usbctrl_full     : std_ulogic := '0';
    signal usbctrl_error    : std_ulogic := '0';
    signal usbctrl_busy     : std_ulogic := '0';
    
    
    ------------------
    --- UART debug ---
    ------------------
    
    -- Inputs
    signal dbg_clk  : std_ulogic := '0';
    signal dbg_rst  : std_ulogic := '0';
    
    signal dbg_msg      : string(1 to 128) := (others => nul);
    signal dbg_wr_en    : std_ulogic := '0';
    signal dbg_cts      : std_ulogic := '0';
    
    -- Outputs
    signal dbg_busy : std_ulogic := '0';
    signal dbg_full : std_ulogic := '0';
    signal dbg_txd  : std_ulogic := '0';
    
    
    -----------------------------
    --- black border detector ---
    -----------------------------
    
    -- Inputs
    signal bbd_clk  : std_ulogic := '0';
    signal bbd_rst  : std_ulogic := '0';
    
    signal bbd_cfg_addr     : std_ulogic_vector(3 downto 0) := (others => '0');
    signal bbd_cfg_wr_en    : std_ulogic := '0';
    signal bbd_cfg_data     : std_ulogic_vector(7 downto 0) := (others => '0');
    
    signal bbd_frame_vsync      : std_ulogic := '0';
    signal bbd_frame_hsync      : std_ulogic := '0';
    signal bbd_frame_rgb_wr_en  : std_ulogic := '0';
    signal bbd_frame_rgb        : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');
    
    -- Outputs
    signal bbd_border_valid     : std_ulogic;
    signal bbd_hor_border_size  : std_ulogic_vector(DIM_BITS-1 downto 0);
    signal bbd_ver_border_size  : std_ulogic_vector(DIM_BITS-1 downto 0);
    
    
    --------------------
    --- configurator ---
    --------------------
    
    -- Inputs
    signal conf_clk : std_ulogic := '0';
    signal conf_rst : std_ulogic := '0';
    
    signal conf_calculate           : std_ulogic := '0';
    signal conf_configure_ledex     : std_ulogic := '0';
    signal conf_configure_ledcor    : std_ulogic := '0';
    signal conf_configure_bbd       : std_ulogic := '0';
    
    signal conf_frame_width     : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal conf_frame_height    : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    signal conf_settings_addr   : std_ulogic_vector(9 downto 0) := (others => '0');
    signal conf_settings_wr_en  : std_ulogic := '0';
    signal conf_settings_din    : std_ulogic_vector(7 downto 0) := x"00";
    signal conf_settings_dout   : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal conf_cfg_sel_ledex   : std_ulogic := '0';
    signal conf_cfg_sel_ledcor  : std_ulogic := '0';
    signal conf_cfg_sel_bbd     : std_ulogic := '0';
    
    signal conf_cfg_addr        : std_ulogic_vector(9 downto 0) := (others => '0');
    signal conf_cfg_wr_en       : std_ulogic := '0';
    signal conf_cfg_data        : std_ulogic_vector(7 downto 0) := x"00";
    
    signal conf_busy    : std_ulogic := '0';
    
    
    -------------------------
    --- SPI flash control ---
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
    
    g_rst   <= '1' when g_clk_locked='0' or pmod0_deb(3)='1' else '0';
    
    usb_connected   <= usb_dsrn_deb='0';
    
    uart_clk        <= g_clk;
    uart_rst        <= '1' when g_rst='1' or not uart_connected else '0';
    uart_connected  <= usb_connected;
    uart_din        <= usbctrl_dout;
    uart_din_valid  <= usbctrl_dout_valid;
    
    FLASH_MOSI  <= fctrl_mosi;
    FLASH_CS    <= fctrl_sn;
    FLASH_SCK   <= fctrl_c;
    
    LEDS_CLK    <= lctrl_leds_clk & lctrl_leds_clk;
    LEDS_DATA   <= lctrl_leds_data & lctrl_leds_data;
    
    USB_TXD     <= dbg_txd;
    USB_RTSN    <= dbg_full;
    
    PMOD1(0)    <= blinker;
    
    pmod0_DEBOUNCE_gen : for i in 0 to 3 generate
        
        pmod0_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 100
            )
            port map (
                CLK => g_clk,
                I   => PMOD0(i),
                O   => pmod0_deb(i)
            );
        
    end generate;
    
    blink_proc : process(g_clk)
    begin
        if rising_edge(g_clk) then
            blink_counter   <= blink_counter+1;
            blinker         <= blink_counter(blink_counter'high);
        end if;
    end process;
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    RX_EN(0)    <= '1';
        
    rx_det_SIGNAL_SYNC_inst : entity work.SIGNAL_SYNC
        port map (
            CLK => g_clk,
            
            DIN     => RX_DET(0),
            DOUT    => rx_det_sync
        );
    
    rx_det_DEBOUNCE_inst : entity work.DEBOUNCE
        generic map (
            CYCLE_COUNT => 1500
        )
        port map (
            CLK => g_clk,
            
            I   => rx_det_sync,
            O   => rx_det_stable
        );
    
    diff_IBUFDS_gen : for i in 0 to 3 generate
        
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
                I   => '1',
                O   => TX_CHANNELS_OUT_P(i),
                OB  => TX_CHANNELS_OUT_N(i)
            );
        
    end generate;
    
    
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
    rx_rst              <= g_rst or not rx_det_stable or not rxclk_ioclk_locked;
    rx_serdesstrobe     <= rxclk_serdesstrobe;
    
    TMDS_DECODER_inst : entity work.TMDS_DECODER
        port map (
            PIX_CLK         => rx_pix_clk,
            PIX_CLK_X2      => rx_pix_clk_x2,
            PIX_CLK_X10     => rx_pix_clk_x10,
            RST             => rx_rst,
            
            SERDESSTROBE    => rx_serdesstrobe,
            
            CHANNELS_IN => rx_channels_in(2 downto 0),
            
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
    
    
    ------------------------
    --- USB UART control ---
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
            BUFFER_SIZE     => 2048,
            BAUD_RATE       => UART_BAUD_RATE
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
            INITIALIZING,
            WAITING_FOR_MAGIC,
            EVALUATING_COMMAND,
            WAITING_FOR_BUSY,
            WAITING_FOR_IDLE
        );
        
        signal cmd_eval_state       : cmd_eval_state_type := WAITING_FOR_IDLE;
        signal recv_magic_index     : natural range 1 to PANDALIGHT_MAGIC'length+1 := 1;
        signal char_counter         : unsigned(log2(PANDALIGHT_MAGIC'length)+1 downto 0) := (others => '0');
        signal char_counter_expired : boolean := false;
        
    begin
        
        char_counter_expired    <= char_counter(char_counter'high)='1';
        
        uart_evaluation_proc : process(uart_rst, uart_clk)
        begin
            if uart_rst='1' then
                cmd_eval_state                  <= WAITING_FOR_IDLE;
                recv_magic_index                <= 1;
                char_counter                    <= (others => '0');
                start_settings_read_from_uart   <= false;
            elsif rising_edge(uart_clk) then
                start_settings_read_from_uart   <= false;
                
                case cmd_eval_state is
                    
                    when INITIALIZING =>
                        recv_magic_index     <= 1;
                        char_counter    <= uns(PANDALIGHT_MAGIC'length-2, char_counter'length);
                        cmd_eval_state  <= WAITING_FOR_MAGIC;
                    
                    when WAITING_FOR_MAGIC =>
                        if uart_din_valid='1' then
                            recv_magic_index    <= recv_magic_index+1;
                            char_counter        <= char_counter-1;
                            if char_counter_expired then
                                cmd_eval_state  <= EVALUATING_COMMAND;
                            end if;
                            if uns(uart_din)/=character'pos(PANDALIGHT_MAGIC(recv_magic_index)) then
                                cmd_eval_state  <= INITIALIZING;
                            end if;
                        end if;
                    
                    when EVALUATING_COMMAND =>
                        if uart_din_valid='1' then
                            case uart_din is
                                when x"22" => -- receive settings from UART
                                    start_settings_read_from_uart   <= true;
                                    cmd_eval_state  <= WAITING_FOR_BUSY;
                                when others =>
                                    null;
                            end case;
                        end if;
                    
                    when WAITING_FOR_BUSY =>
                        if not (
                            configurator_idle and
                            flash_control_idle
                        ) then
                            cmd_eval_state  <= WAITING_FOR_IDLE;
                        end if;
                    
                    when WAITING_FOR_IDLE =>
                        if
                            configurator_idle and
                            flash_control_idle
                        then
                            cmd_eval_state  <= INITIALIZING;
                        end if;
                    
                end case;
                
            end if;
        end process;
        
    end generate;
    
    
    ------------------
    --- UART debug ---
    ------------------
    
    dbg_clk <= g_clk;
    dbg_rst <= g_rst;
    
    dbg_cts <= not USB_CTSN;
    
    UART_DEBUG_inst : entity work.UART_DEBUG
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            BAUD_RATE       => UART_BAUD_RATE
        )
        port map (
            CLK => dbg_clk,
            RST => dbg_rst,
            
            MSG     => dbg_msg,
            WR_EN   => dbg_wr_en,
            CTS     => dbg_cts,
            
            BUSY    => dbg_busy,
            FULL    => dbg_full,
            TXD     => dbg_txd
        );
    
    
    UART_DEBUG_gen : if true generate
        
        constant BOOT_DELAY_CYCLES  : natural := 1000;
        
        type state_type is (
            IDLE,
            PRINTING_RX_DET_EVENT,
            PRINTING_ANALYZER_VALID_EVENT,
            PRINTING_BLACK_BORDER_DETECTOR_EVENT
        );
        
        signal state                : state_type := IDLE;
        signal rx_det_stable_q      : std_ulogic := '0';
        signal analyzer_valid_q     : std_ulogic := '0';
        signal bbd_border_valid_q   : std_ulogic := '0';
        signal border_hor_string    : string(1 to DIM_BIT) := (others => nul);
        signal border_ver_string    : string(1 to DIM_BIT) := (others => nul);
        
    begin
        
        border_hor_string   <= str(bbd_hor_border_size);
        border_ver_string   <= str(bbd_ver_border_size);
        
        process(dbg_rst, dbg_clk)
        begin
            if dbg_rst='1' then
                dbg_wr_en       <= '0';
                state           <= WAITING_FOR_BOOT;
                boot_msg_delay  <= 0;
                cycle_cnt       <= 0;
            elsif rising_edge(dbg_clk) then
                rx_det_stable_q     <= rx_det_stable;
                analyzer_valid_q    <= analyzer_valid;
                bbd_border_valid_q  <= bbd_border_valid;
                dbg_wr_en           <= '0';
                
                case state is
                    
                    when IDLE =>
                        if rx_det_stable_q='0' and rx_det_stable='1' then
                            state   <= PRINTING_RX_DET_EVENT;
                        end if;
                        if analyzer_valid_q='0' and analyzer_valid='1' then
                            state   <= PRINTING_ANALYZER_VALID_EVENT;
                        end if;
                        if bbd_border_valid_q='0' and bbd_border_valid='1' then
                            state   <= PRINTING_BLACK_BORDER_DETECTOR_EVENT;
                        end if;
                    
                    when PRINTING_RX_DET_EVENT =>
                        dbg_msg(1 to 13)    <= "RX0 detected" & nul;
                        dbg_wr_en           <= '1';
                        state               <= IDLE;
                    
                    when PRINTING_ANALYZER_VALID_EVENT =>
                        dbg_msg(1 to 15)    <= "analyzer valid" & nul;
                        dbg_wr_en           <= '1';
                        state               <= IDLE;
                    
                    when PRINTING_BLACK_BORDER_DETECTOR_EVENT =>
                        dbg_msg(1 to 8)                         <= "border: ";
                        dbg_msg(9 to 9+DIM_BITS)                <= border_hor_string;
                        dbg_msg(10+DIM_BITS)                    <= '|';
                        dbg_msg(11+DIM_BITS to 11+2*DIM_BITS)   <= border_ver_string;
                        dbg_msg(12+2*DIM_BITS)                  <= nul;
                        dbg_wr_en                               <= '1';
                        state                                   <= IDLE;
                    
                end case;
                
            end if;
        end process;
        
    end generate;
    
    
    -----------------------------
    --- black border detector ---
    -----------------------------
    
    bbd_clk <= g_clk;
    bbd_rst <= g_rst or not analyzer_valid;
    
    bbd_cfg_addr    <= conf_cfg_addr(bbd_cfg_addr'range);
    bbd_cfg_wr_en   <= conf_cfg_wr_en and conf_cfg_sel_bbd;
    bbd_cfg_data    <= conf_cfg_data;
    
    bbd_frame_vsync     <= analyzer_positive_vsync;
    bbd_frame_hsync     <= analyzer_positive_hsync;
    bbd_frame_rgb_wr_en <= rx_rgb_valid;
    bbd_frame_rgb       <= rx_rgb;
    
    BLACK_BORDER_DETECTOR_inst : entity work.BLACK_BORDER_DETECTOR
        generic map (
            R_BITS      => R_BITS,
            G_BITS      => G_BITS,
            B_BITS      => B_BITS,
            DIM_BITS    => DIM_BITS
        )
        port map (
            CLK => bbd_clk,
            RST => bbd_rst,
            
            CFG_ADDR    => bbd_cfg_addr,
            CFG_WR_EN   => bbd_cfg_wr_en,
            CFG_DATA    => bbd_cfg_data,
            
            FRAME_VSYNC     => bbd_frame_vsync,
            FRAME_HSYNC     => bbd_frame_hsync,
            FRAME_RGB_WR_EN => bbd_frame_rgb_wr_en,
            FRAME_RGB       => bbd_frame_rgb,
            
            BORDER_VALID    => bbd_border_valid,
            HOR_BORDER_SIZE => bbd_hor_border_size,
            VER_BORDER_SIZE => bbd_ver_border_size
        );
    
    
    -------------------
    -- configurator ---
    -------------------
    
    conf_clk    <= g_clk;
    conf_rst    <= g_rst;
    
    CONFIGURATOR_inst : entity work.CONFIGURATOR
        generic map (
            DIM_BITS    => DIM_BITS
        )
        port map (
            CLK => conf_clk,
            RST => conf_rst,
            
            CALCULATE           => conf_calculate,
            CONFIGURE_LEDEX     => conf_configure_ledex,
            CONFIGURE_LEDCOR    => conf_configure_ledcor,
            CONFIGURE_BBD       => conf_configure_bbd,
            
            FRAME_WIDTH     => conf_frame_width,
            FRAME_HEIGHT    => conf_frame_height,
            
            SETTINGS_ADDR   => conf_settings_addr,
            SETTINGS_WR_EN  => conf_settings_wr_en,
            SETTINGS_DIN    => conf_settings_din,
            SETTINGS_DOUT   => conf_settings_dout,
            
            CFG_SEL_LEDEX   => conf_cfg_sel_ledex,
            CFG_SEL_LEDCOR  => conf_cfg_sel_ledcor,
            CFG_SEL_BBD     => conf_cfg_sel_bbd,
            
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
            INITIALIZING,
            READING_SETTINGS_FROM_FLASH,
            CALCULATING,
            CALCULATING_WAITING_FOR_BUSY,
            CALCULATING_WAITING_FOR_IDLE,
            CONF_BBD_CONFIGURING_BLACK_BORDER_DETECTOR,
            CONF_BBD_WAITING_FOR_BUSY,
            CONF_BBD_WAITING_FOR_IDLE,
            IDLE,
            RECEIVING_SETTINGS_FROM_UART
        );
        
        signal state                : state_type := INITIALIZING;
        signal counter              : unsigned(10 downto 0) := uns(1023, 11);
        signal settings_addr        : std_ulogic_vector(9 downto 0) := (others => '0');
        signal init_read_finished   : boolean := false;
        
        signal counter_expired  : boolean := false;
    begin
        
        configurator_idle   <= state=IDLE;
        counter_expired     <= counter(counter'high)='1';
        
        conf_frame_width    <= stdulv(1280, conf_frame_width'length);
        conf_frame_height   <= stdulv(720, conf_frame_height'length);
        
        configurator_stim_proc : process(conf_rst, conf_clk)
        begin
            if conf_rst='1' then
                conf_settings_wr_en     <= '0';
                conf_settings_din       <= x"00";
                conf_calculate          <= '0';
                conf_configure_bbd      <= '0';
                counter                 <= uns(1023, 11);
                settings_addr           <= (others => '0');
                conf_settings_addr      <= (others => '0');
            elsif rising_edge(conf_clk) then
                conf_settings_wr_en     <= '0';
                conf_calculate          <= '0';
                conf_configure_bbd      <= '0';
                
                case state is
                    
                    when INITIALIZING =>
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
                            state   <= CONF_BBD_CONFIGURING_BLACK_BORDER_DETECTOR;
                        end if;
                    
                    when CONF_BBD_CONFIGURING_BLACK_BORDER_DETECTOR =>
                        conf_configure_ledex    <= '1';
                        state                   <= CONF_BBD_WAITING_FOR_BUSY;
                    
                    when CONF_BBD_WAITING_FOR_BUSY =>
                        if conf_busy='1' then
                            state   <= CONF_BBD_WAITING_FOR_IDLE;
                        end if;
                    
                    when CONF_BBD_WAITING_FOR_IDLE =>
                        if conf_busy='0' then
                            state   <= IDLE;
                        end if;
                    
                    when IDLE =>
                        counter             <= uns(1023, counter'length);
                        settings_addr       <= (others => '0');
                        conf_settings_addr  <= (others => '0');
                        if start_settings_read_from_uart then
                            state   <= RECEIVING_SETTINGS_FROM_UART;
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
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
    -------------------------
    --- SPI Flash control ---
    -------------------------
    
    fctrl_clk   <= g_clk;
    fctrl_rst   <= g_rst;
    
    fctrl_addr  <= SETTINGS_FLASH_ADDR;
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
            INITIALIZING,
            READING_DATA,
            IDLE
        );
        
        signal state    : state_type := INITIALIZING;
        signal counter  : unsigned(23 downto 0) := uns(1023, 24);
    begin
        
        flash_control_idle  <= state=IDLE;
        
        spi_flash_control_stim_proc : process(fctrl_rst, fctrl_clk)
        begin
            if fctrl_rst='1' then
                state           <= INITIALIZING;
                fctrl_rd_en     <= '0';
            elsif rising_edge(fctrl_clk) then
                fctrl_rd_en     <= '0';
                
                case state is
                    
                    when INITIALIZING =>
                        state   <= READING_DATA;
                    
                    when READING_DATA =>
                        if counter(counter'high)='1' then
                            state   <= IDLE;
                        else
                            fctrl_rd_en <= '1';
                        end if;
                        if fctrl_valid='1' then
                            counter <= counter-1;
                        end if;
                    
                    when IDLE =>
                        null;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
end rtl;

