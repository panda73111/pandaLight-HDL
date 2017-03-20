----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    11:28:20 02/03/2017
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
        G_CLK_MULT          : natural range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV           : natural range 1 to 256 := 2;
        G_CLK_PERIOD        : real := 20.0; -- 50 MHz in nano seconds
        LED_CONTROL_TEST    : boolean := true
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
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    
    -------------------
    --- LED control ---
    -------------------
    
    signal LCTRL_CLK    : std_ulogic := '0';
    signal LCTRL_RST    : std_ulogic := '0';
    
    signal LCTRL_MODE   : std_ulogic_vector(1 downto 0) := "00";
    
    signal LCTRL_LED_VSYNC      : std_ulogic := '0';
    signal LCTRL_LED_RGB        : std_ulogic_vector(23 downto 0) := x"000000";
    signal LCTRL_LED_RGB_WR_EN  : std_ulogic := '0';
    
    signal LCTRL_LEDS_CLK   : std_ulogic := '0';
    signal LCTRL_LEDS_DATA  : std_ulogic := '0';
    
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
    
    LEDS_CLK    <= LCTRL_LEDS_CLK & LCTRL_LEDS_CLK;
    LEDS_DATA   <= LCTRL_LEDS_DATA & LCTRL_LEDS_DATA;
    
    PMOD0(0)    <= '0';
    PMOD0(1)    <= '0';
    PMOD0(2)    <= '0';
    PMOD0(3)    <= '0';
    
    
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
    
    LCTRL_CLK   <= g_clk;
    LCTRL_RST   <= g_rst;
    
    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD           => G_CLK_PERIOD,
            WS2801_LEDS_CLK_PERIOD  => 1000.0, -- 1 MHz
            MAX_LED_CNT             => 512
        )
        port map (
            CLK => LCTRL_CLK,
            RST => LCTRL_RST,
            
            MODE    => LCTRL_MODE,
            
            LED_VSYNC       => LCTRL_LED_VSYNC,
            LED_RGB         => LCTRL_LED_RGB,
            LED_RGB_WR_EN   => LCTRL_LED_RGB_WR_EN,
            
            LEDS_CLK    => LCTRL_LEDS_CLK,
            LEDS_DATA   => LCTRL_LEDS_DATA
        );
    
    LED_CONTROL_TEST_gen : if LED_CONTROL_TEST generate
        constant LED_COUNT      : natural := 210;
        constant PAUSE_CYCLES   : natural := 416_666-LED_COUNT; -- 120 Hz
        
        constant LED_BITS       : natural := log2(LED_COUNT)+1;
        constant PAUSE_BITS     : natural := log2(PAUSE_CYCLES)+1;
        
        type state_type is (
            WRITING_LEDS,
            PAUSING,
            CHANGING_FRAME
        );
        signal state        : state_type := WRITING_LEDS;
        signal leds_left    : unsigned(LED_BITS-1 downto 0) := uns(LED_COUNT-2, LED_BITS);
        signal pause_left   : unsigned(PAUSE_BITS-1 downto 0) := uns(PAUSE_CYCLES-2, PAUSE_BITS);
        
        signal colored_led_index    : natural range 0 to LED_COUNT := 0;
        signal led_index            : natural range 0 to LED_COUNT := 0;
        signal led_color            : std_ulogic_vector(23 downto 0) := x"0000FF";
    begin
        
        LCTRL_MODE  <= "11";
        
        led_ctrl_test_proc : process(g_clk, g_rst)
        begin
            if g_rst='1' then
                state               <= WRITING_LEDS;
                LCTRL_LED_VSYNC     <= '0';
                LCTRL_LED_RGB       <= x"000000";
                LCTRL_LED_RGB_WR_EN <= '0';
                leds_left           <= uns(LED_COUNT-2, LED_BITS);
                pause_left          <= uns(PAUSE_CYCLES-2, PAUSE_BITS);
                colored_led_index   <= 0;
                led_color           <= x"0000FF";
            elsif rising_edge(g_clk) then
                LCTRL_LED_VSYNC     <= '0';
                LCTRL_LED_RGB_WR_EN <= '0';
                
                case state is
                    
                    when WRITING_LEDS =>
                        LCTRL_LED_RGB   <= x"000000";
                        if led_index=colored_led_index then
                            LCTRL_LED_RGB   <= led_color;
                        end if;
                        LCTRL_LED_RGB_WR_EN <= '1';
                        led_index           <= led_index+1;
                        leds_left           <= leds_left-1;
                        pause_left          <= uns(PAUSE_CYCLES-3, PAUSE_BITS);
                        if leds_left(leds_left'high)='1' then
                            state   <= PAUSING;
                        end if;
                    
                    when PAUSING =>
                        LCTRL_LED_VSYNC <= '1';
                        pause_left      <= pause_left-1;
                        leds_left       <= uns(LED_COUNT-2, LED_BITS);
                        if pause_left(pause_left'high)='1' then
                            state   <= CHANGING_FRAME;
                        end if;
                    
                    when CHANGING_FRAME =>
                        led_index           <= 0;
                        colored_led_index   <= colored_led_index+1;
                        if colored_led_index=LED_COUNT-1 then
                            colored_led_index   <= 0;
                            led_color           <= led_color(15 downto 0) & led_color(23 downto 16);
                        end if;
                        state   <= WRITING_LEDS;
                    
                end case;
            end if;
        end process;
    
    end generate;
    
end rtl;

