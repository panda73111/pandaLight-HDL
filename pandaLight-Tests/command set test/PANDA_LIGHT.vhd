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
        RX0_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"000000";
        RX1_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"060000";
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
    
    signal start_sysinfo_to_uart            : boolean := false;
    signal start_settings_read_from_flash   : boolean := false;
    signal start_settings_write_to_flash    : boolean := false;
    signal start_settings_read_from_uart    : boolean := false;
    signal start_settings_write_to_uart     : boolean := false;
    signal start_bitfile_read_from_uart     : boolean := false;
    signal start_led_read_from_uart         : boolean := false;
    
    signal uart_response_idle   : boolean := true;
    signal configurator_idle    : boolean := true;
    signal flash_control_idle   : boolean := true;
    signal led_control_idle     : boolean := true;
    
    signal bitfile_index    : unsigned(0 downto 0) := "0";
    signal bitfile_size     : unsigned(23 downto 0) := x"000000";
    
    signal uart_led_count   : unsigned(7 downto 0) := x"00";
    
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
    
    
    -------------------
    --- LED control ---
    -------------------
    
    signal lctrl_clk    : std_ulogic := '0';
    signal lctrl_rst    : std_ulogic := '0';
    
    signal lctrl_mode   : std_ulogic_vector(1 downto 0) := "00";
    
    signal lctrl_led_vsync      : std_ulogic := '1';
    signal lctrl_led_rgb        : std_ulogic_vector(23 downto 0) := x"000000";
    signal lctrl_led_rgb_wr_en  : std_ulogic := '0';
    
    signal lctrl_leds_clk   : std_ulogic := '0';
    signal lctrl_leds_data  : std_ulogic := '0';
    
    
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
    
    g_rst   <= '1' when g_clk_locked='0' or pmod0_deb(3)='1' else '0';
    
    usb_connected   <= usb_dsrn_deb='0';
    
    uart_rst        <= '1' when g_rst='1' or not uart_connected else '0';
    uart_connected  <= usb_connected;
    uart_din        <= usbctrl_dout;
    uart_din_valid  <= usbctrl_dout_valid;
    
    FLASH_MOSI  <= fctrl_mosi;
    FLASH_CS    <= fctrl_sn;
    FLASH_SCK   <= fctrl_c;
    
    LEDS_CLK    <= lctrl_leds_clk & lctrl_leds_clk;
    LEDS_DATA   <= lctrl_leds_data & lctrl_leds_data;
    
    USB_TXD     <= usbctrl_txd;
    USB_RTSN    <= not (usbctrl_rts and not fctrl_afull);
    
    PMOD1(0)    <= blinker;
    PMOD1(1)    <= fctrl_afull;
    PMOD1(2)    <= '0' when flash_control_idle else '0';
    
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
    
    diff_IBUFDS_gen : for i in 0 to 7 generate
        
        rx_channel_IBUFDS_inst : IBUFDS
            generic map (DIFF_TERM  => false)
            port map (
                I   => RX_CHANNELS_IN_P(i),
                IB  => RX_CHANNELS_IN_N(i),
                O   => open
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
    
    
    ------------------
    -- LED control ---
    ------------------
    
    lctrl_clk   <= g_clk;
    lctrl_rst   <= g_rst;
    
    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            MAX_LED_COUNT   => MAX_LED_CNT
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
    
    led_control_stim_gen : if true generate
        type state_type is (
            WAITING_FOR_START,
            READING_LED_RED,
            READING_LED_GREEN,
            READING_LED_BLUE
        );
        
        signal state            : state_type := WAITING_FOR_START;
        signal counter          : unsigned(8 downto 0);
        signal counter_expired  : boolean := false;
    begin
        
        led_control_idle    <= state=WAITING_FOR_START;
        counter_expired     <= counter(8)='1';
        
        led_control_stim_proc : process(lctrl_rst, lctrl_clk)
        begin
            if lctrl_rst='1' then
                state               <= WAITING_FOR_START;
                lctrl_led_rgb_wr_en <= '0';
                lctrl_led_vsync     <= '1';
                lctrl_mode          <= "00";
            elsif rising_edge(lctrl_clk) then
                lctrl_led_rgb_wr_en <= '0';
                case state is
                
                    when WAITING_FOR_START =>
                        lctrl_led_vsync <= '1';
                        counter         <= '0' & (uart_led_count-2);
                        if start_led_read_from_uart then
                            state           <= READING_LED_RED;
                            lctrl_led_vsync <= '0';
                        end if;
                        if conf_cfg_sel_ledcon='1' and conf_cfg_wr_en='1' then
                            lctrl_mode  <= conf_cfg_data(1 downto 0);
                        end if;
                    
                    when READING_LED_RED =>
                        lctrl_led_rgb(23 downto 16) <= uart_din;
                        if uart_din_valid='1' then
                            state   <= READING_LED_GREEN;
                        end if;
                    
                    when READING_LED_GREEN =>
                        lctrl_led_rgb(15 downto 8)  <= uart_din;
                        if uart_din_valid='1' then
                            state   <= READING_LED_BLUE;
                        end if;
                    
                    when READING_LED_BLUE =>
                        lctrl_led_rgb(7 downto 0)   <= uart_din;
                        if uart_din_valid='1' then
                            counter             <= counter-1;
                            lctrl_led_rgb_wr_en <= '1';
                            state               <= READING_LED_RED;
                            if counter_expired then
                                state   <= WAITING_FOR_START;
                            end if;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
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
            RECEIVING_BITFILE_INDEX_FROM_UART,
            RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_1,
            RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_2,
            RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_3,
            RECEIVING_LED_COUNT_FROM_UART,
            WAITING_FOR_BUSY,
            WAITING_FOR_IDLE
        );
        
        signal cmd_eval_state       : cmd_eval_state_type := WAITING_FOR_IDLE;
        signal recv_magic_index     : natural range 1 to PANDALIGHT_MAGIC'length+1 := 1;
        signal char_counter         : unsigned(log2(PANDALIGHT_MAGIC'length)+1 downto 0) := (others => '0');
        signal char_counter_expired : boolean := false;
        
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
        signal send_magic_index         : natural range 1 to PANDALIGHT_MAGIC'length+1 := 1;
        signal data_counter_expired     : boolean := false;
        
    begin
        
        uart_response_idle      <= data_handling_state=WAITING_FOR_COMMAND;
        char_counter_expired    <= char_counter(char_counter'high)='1';
        data_counter_expired    <= data_handling_counter(data_handling_counter'high)='1';
        
        uart_evaluation_proc : process(usbctrl_rst, usbctrl_clk)
        begin
            if usbctrl_rst='1' then
                cmd_eval_state                  <= WAITING_FOR_IDLE;
                recv_magic_index                <= 1;
                char_counter                    <= (others => '0');
                start_sysinfo_to_uart           <= false;
                start_settings_read_from_flash  <= false;
                start_settings_write_to_flash   <= false;
                start_settings_read_from_uart   <= false;
                start_settings_write_to_uart    <= false;
                start_bitfile_read_from_uart    <= false;
                start_led_read_from_uart        <= false;
            elsif rising_edge(usbctrl_clk) then
                start_sysinfo_to_uart           <= false;
                start_settings_read_from_flash  <= false;
                start_settings_write_to_flash   <= false;
                start_settings_read_from_uart   <= false;
                start_settings_write_to_uart    <= false;
                start_bitfile_read_from_uart    <= false;
                start_led_read_from_uart        <= false;
                
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
                                    cmd_eval_state  <= WAITING_FOR_BUSY;
                                when x"23" => -- send settings to UART
                                    start_settings_write_to_uart    <= true;
                                when x"40" => -- receive bitfile from UART
                                    cmd_eval_state  <= RECEIVING_BITFILE_INDEX_FROM_UART;
                                when x"60" => -- receive LED colors from UART
                                    cmd_eval_state  <= RECEIVING_LED_COUNT_FROM_UART;
                                when others =>
                                    null;
                            end case;
                        end if;
                    
                    when RECEIVING_BITFILE_INDEX_FROM_UART =>
                        if uart_din_valid='1' then
                            bitfile_index   <= uns(uart_din(0 downto 0));
                            cmd_eval_state  <= RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_1;
                        end if;
                    
                    when RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_1 =>
                        if uart_din_valid='1' then
                            bitfile_size(23 downto 16)  <= uns(uart_din);
                            cmd_eval_state              <= RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_2;
                        end if;
                    
                    when RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_2 =>
                        if uart_din_valid='1' then
                            bitfile_size(15 downto 8)   <= uns(uart_din);
                            cmd_eval_state              <= RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_3;
                        end if;
                    
                    when RECEIVING_BITFILE_SIZE_FROM_UART_BYTE_3 =>
                        if uart_din_valid='1' then
                            bitfile_size(7 downto 0)        <= uns(uart_din);
                            start_bitfile_read_from_uart    <= true;
                            cmd_eval_state                  <= WAITING_FOR_BUSY;
                        end if;
                    
                    when RECEIVING_LED_COUNT_FROM_UART =>
                        if uart_din_valid='1' then
                            uart_led_count              <= uns(uart_din);
                            start_led_read_from_uart    <= true;
                            cmd_eval_state              <= WAITING_FOR_BUSY;
                        end if;
                    
                    when WAITING_FOR_BUSY =>
                        if not (
                            uart_response_idle and
                            configurator_idle and
                            flash_control_idle and
                            led_control_idle
                        ) then
                            cmd_eval_state  <= WAITING_FOR_IDLE;
                        end if;
                    
                    when WAITING_FOR_IDLE =>
                        if
                            uart_response_idle and
                            configurator_idle and
                            flash_control_idle and
                            led_control_idle
                        then
                            cmd_eval_state  <= INITIALIZING;
                        end if;
                    
                end case;
                
            end if;
        end process;
        
        uart_stim_proc : process(usbctrl_rst, usbctrl_clk)
        begin
            if usbctrl_rst='1' then
                data_handling_state     <= WAITING_FOR_COMMAND;
                data_handling_counter   <= uns(1022, data_handling_counter'length);
                send_magic_index        <= 1;
                uart_dout_wr_en         <= '0';
                uart_dout_send          <= '0';
            elsif rising_edge(usbctrl_clk) then
                uart_dout_wr_en <= '0';
                uart_dout_send  <= '0';
                
                case data_handling_state is
                    
                    when WAITING_FOR_COMMAND =>
                        if start_sysinfo_to_uart then
                            data_handling_counter   <= uns(PANDALIGHT_MAGIC'length-2, data_handling_counter'length);
                            send_magic_index        <= 1;
                            data_handling_state     <= SENDING_PANDALIGHT_MAGIC_TO_UART;
                        end if;
                        if start_settings_write_to_uart then
                            data_handling_counter   <= uns(1022, data_handling_counter'length);
                            data_handling_state     <= WAITING_FOR_DATA;
                        end if;
                    
                    when SENDING_PANDALIGHT_MAGIC_TO_UART =>
                        uart_dout_wr_en         <= '1';
                        uart_dout               <= stdulv(PANDALIGHT_MAGIC(send_magic_index));
                        send_magic_index        <= send_magic_index+1;
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
            CONFIGURE_LEDCON    => conf_configure_ledcon,
            
            FRAME_WIDTH     => conf_frame_width,
            FRAME_HEIGHT    => conf_frame_height,
            
            SETTINGS_ADDR   => conf_settings_addr,
            SETTINGS_WR_EN  => conf_settings_wr_en,
            SETTINGS_DIN    => conf_settings_din,
            SETTINGS_DOUT   => conf_settings_dout,
            
            CFG_SEL_LEDEX   => conf_cfg_sel_ledex,
            CFG_SEL_LEDCOR  => conf_cfg_sel_ledcor,
            CFG_SEL_LEDCON  => conf_cfg_sel_ledcon,
            
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
                            state   <= IDLE;
                        end if;
                    
                    when IDLE =>
                        counter             <= uns(1023, counter'length);
                        settings_addr       <= (others => '0');
                        conf_settings_addr  <= (others => '0');
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
            INITIALIZING,
            IDLE,
            READING_DATA,
            WRITING_SETTINGS,
            WRITING_BITFILE,
            WAITING_FOR_IDLE
        );
        
        signal state    : state_type := INITIALIZING;
        signal counter  : unsigned(23 downto 0) := uns(1023, 24);
        
        signal bitfile_address  : std_ulogic_vector(23 downto 0) := x"000000";
    begin
        
        flash_control_idle  <= state=IDLE;
        bitfile_address     <= RX0_BITFILE_ADDR when bitfile_index=0 else RX1_BITFILE_ADDR;
        
        spi_flash_control_stim_proc : process(fctrl_rst, fctrl_clk)
            variable next_state : state_type := INITIALIZING;
        begin
            if fctrl_rst='1' then
                state           <= INITIALIZING;
                fctrl_rd_en     <= '0';
                fctrl_wr_en     <= '0';
                fctrl_end_wr    <= '0';
            elsif rising_edge(fctrl_clk) then
                fctrl_rd_en     <= '0';
                fctrl_wr_en     <= '0';
                fctrl_end_wr    <= '0';
                
                case state is
                    
                    when INITIALIZING =>
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
    iprog_en    <= reboot;
    
    IPROG_RECONF_inst : entity work.iprog_reconf
        generic map (
            START_ADDR      => x"000000",
            FALLBACK_ADDR   => x"000000"
        )
        port map (
            CLK => iprog_clk,
            
            EN  => iprog_en
        );
    
end rtl;

