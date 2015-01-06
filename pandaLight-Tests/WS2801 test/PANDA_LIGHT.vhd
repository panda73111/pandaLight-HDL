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
        G_CLK_MULT          : natural range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV           : natural range 1 to 256 := 2;
        G_CLK_PERIOD        : real := 20.0; -- 50 MHz in nano seconds
        LED_CONTROL_TEST    : boolean := true
    );
    port (
        CLK20   : in std_ulogic;
        
        -- LEDs
        LEDS_CLK    : out std_ulogic_vector(1 downto 0) := "00";
        LEDS_DATA   : out std_ulogic_vector(1 downto 0) := "00";
        
        -- PMOD
        PMOD0   : out std_ulogic_vector(3 downto 0) := "0000"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_stopped    : std_ulogic := '0';
    
    
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
            
            CLK_IN          => CLK20,
            CLK_OUT         => g_clk,
            CLK_OUT_STOPPED => g_clk_stopped
        );
    
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    g_rst   <= g_clk_stopped;
    
    LEDS_CLK    <= LCTRL_LEDS_CLK & LCTRL_LEDS_CLK;
    LEDS_DATA   <= LCTRL_LEDS_DATA & LCTRL_LEDS_DATA;
    
    PMOD0(0)    <= '0';
    PMOD0(1)    <= '0';
    PMOD0(2)    <= '0';
    PMOD0(3)    <= '0';
    
    
    ------------------
    -- LED control ---
    ------------------
    
    LCTRL_CLK   <= g_clk;
    LCTRL_RST   <= g_rst;
    
    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD           => G_CLK_PERIOD,
            WS2801_LEDS_CLK_PERIOD  => 1000.0 -- 1 MHz
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
        constant LED_COUNT      : natural := 50;
        constant PAUSE_CYCLES   : natural := 416_666-LED_COUNT; -- 120 Hz
        
        constant LED_BITS       : natural := log2(LED_COUNT)+1;
        constant PAUSE_BITS     : natural := log2(PAUSE_CYCLES)+1;
        
        type state_type is (
            WRITING_LEDS,
            PAUSING
        );
        signal state        : state_type := WRITING_LEDS;
        signal leds_left    : unsigned(LED_BITS-1 downto 0) := uns(LED_COUNT-2, LED_BITS);
        signal pause_left   : unsigned(PAUSE_BITS-1 downto 0) := uns(PAUSE_CYCLES-2, PAUSE_BITS);
        signal start_color  : std_ulogic_vector(23 downto 0) := x"000000";
    begin
        
        LCTRL_MODE  <= "00";
        
        led_ctrl_test_proc : process(g_clk, g_rst)
        begin
            if g_rst='1' then
                state               <= WRITING_LEDS;
                LCTRL_LED_VSYNC     <= '0';
                LCTRL_LED_RGB       <= x"000000";
                LCTRL_LED_RGB_WR_EN <= '0';
                leds_left           <= uns(LED_COUNT-2, LED_BITS);
                pause_left          <= uns(PAUSE_CYCLES-2, PAUSE_BITS);
                start_color         <= x"000000";
            elsif rising_edge(g_clk) then
                LCTRL_LED_VSYNC     <= '0';
                LCTRL_LED_RGB_WR_EN <= '0';
                
                case state is
                    
                    when WRITING_LEDS =>
                        LCTRL_LED_RGB       <= LCTRL_LED_RGB+5;
                        LCTRL_LED_RGB_WR_EN <= '1';
                        leds_left           <= leds_left-1;
                        pause_left          <= uns(PAUSE_CYCLES-2, PAUSE_BITS);
                        if leds_left(leds_left'high)='1' then
                            state   <= PAUSING;
                        end if;
                    
                    when PAUSING =>
                        LCTRL_LED_VSYNC <= '1';
                        LCTRL_LED_RGB   <= start_color;
                        pause_left      <= pause_left-1;
                        leds_left       <= uns(LED_COUNT-2, LED_BITS);
                        if pause_left(pause_left'high)='1' then
                            start_color <= start_color+(LED_COUNT*5);
                            state       <= WRITING_LEDS;
                        end if;
                    
                end case;
            end if;
        end process;
    
    end generate;
    
end rtl;

