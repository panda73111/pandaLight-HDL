----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    12:27:29 07/30/2014 
-- Module Name:    LED_CONTROL - rtl 
-- Project Name:   LED_CONTROL
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--   Modes (to be extended):
--    [0] = WS2801
--    [1] = WS2811, fast mode (800 kHz)
--    [2] = WS2811, slow mode (400 kHz)
--    [3] = WS2812/WS2812B
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity LED_CONTROL is
    generic (
        CLK_IN_PERIOD           : real;
        WS2801_LEDS_CLK_PERIOD  : real;
        MAX_LED_CNT             : natural := 128
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        MODE    : in std_ulogic_vector(1 downto 0);
        
        LED_VSYNC       : in std_ulogic;
        LED_RGB         : in std_ulogic_vector(23 downto 0);
        LED_RGB_WR_EN   : in std_ulogic;
        
        BUSY    : out std_ulogic := '0';
        
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end LED_CONTROL;

architecture rtl of LED_CONTROL is
    
    signal led_vsync_q  : std_ulogic := '0';
    signal led_vsync_qq : std_ulogic := '0';
    signal frame_end    : std_ulogic := '0';
    
    signal ws2801_rst       : std_ulogic := '0';
    signal ws2801_start     : std_ulogic := '0';
    signal ws2801_leds_clk  : std_ulogic := '0';
    signal ws2801_leds_data : std_ulogic := '0';
    signal ws2801_rgb_rd_en : std_ulogic := '0';
    
    signal ws2811_rst       : std_ulogic := '0';
    signal ws2811_start     : std_ulogic := '0';
    signal ws2811_slow_mode : std_ulogic := '0';
    signal ws2811_leds_data : std_ulogic := '0';
    signal ws2811_rgb_rd_en : std_ulogic := '0';
    
    signal ws2812_rst       : std_ulogic := '0';
    signal ws2812_start     : std_ulogic := '0';
    signal ws2812_leds_data : std_ulogic := '0';
    signal ws2812_rgb_rd_en : std_ulogic := '0';
    
    signal fifo_rd_en   : std_ulogic := '0';
    signal fifo_dout    : std_ulogic_vector(23 downto 0) := x"000000";
    signal fifo_empty   : std_ulogic := '0';
    
begin
    
    LEDS_CLK    <= ws2801_leds_clk;
    
    with MODE select LEDS_DATA <=
        ws2801_leds_data when "00",
        ws2811_leds_data when "01",
        ws2811_leds_data when "10",
        ws2812_leds_data when others;
    
    ws2801_rst  <= '1' when MODE/="00" else '0';
    ws2811_rst  <= '1' when MODE/="01" and MODE/="10" else '0';
    ws2812_rst  <= '1' when MODE/="11" else '0';
    
    ws2801_start    <= frame_end;
    ws2811_start    <= frame_end;
    ws2812_start    <= frame_end;
    
    ws2811_slow_mode    <= '1' when MODE="10" else '0';
    frame_end           <= led_vsync_q and not led_vsync_qq;
    fifo_rd_en          <= ws2801_rgb_rd_en or ws2811_rgb_rd_en or ws2812_rgb_rd_en;
    
    FIFO_inst : entity work.ASYNC_FIFO
        generic map (
            WIDTH   => 24,
            DEPTH   => MAX_LED_CNT
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            DIN     => LED_RGB,
            RD_EN   => fifo_rd_en,
            WR_EN   => LED_RGB_WR_EN,
            
            DOUT    => fifo_dout,
            EMPTY   => fifo_empty
        );
    
    LED_CONTROL_WS2801_inst : entity work.LED_CONTROL_WS2801
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            LEDS_CLK_PERIOD => WS2801_LEDS_CLK_PERIOD
        )
        port map (
            CLK => CLK,
            RST => ws2801_rst,
            
            START       => ws2801_start,
            STOP        => fifo_empty,
            RGB         => fifo_dout,
            
            RGB_RD_EN   => ws2801_rgb_rd_en,
            LEDS_CLK    => ws2801_leds_clk,
            LEDS_DATA   => ws2801_leds_data
        );
    
    LED_CONTROL_WS2811_inst : entity work.LED_CONTROL_WS2811
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD
        )
        port map (
            CLK => CLK,
            RST => ws2811_rst,
            
            START       => ws2811_start,
            STOP        => fifo_empty,
            SLOW_MODE   => ws2811_slow_mode,
            RGB         => fifo_dout,
            
            RGB_RD_EN   => ws2811_rgb_rd_en,
            LEDS_DATA   => ws2811_leds_data
        );
    
    LED_CONTROL_WS2812_inst : entity work.LED_CONTROL_WS2812
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD
        )
        port map (
            CLK => CLK,
            RST => ws2812_rst,
            
            START       => ws2812_start,
            STOP        => fifo_empty,
            RGB         => fifo_dout,
            
            RGB_RD_EN   => ws2812_rgb_rd_en,
            LEDS_DATA   => ws2812_leds_data
        );
    
    process(CLK)
    begin
        if rising_edge(CLK) then
            -- for some reason, simulation doesn't work using only 1 cycle delay
            led_vsync_q     <= LED_VSYNC;
            led_vsync_qq    <= led_vsync_q;
        end if;
    end process;
    
end rtl;

