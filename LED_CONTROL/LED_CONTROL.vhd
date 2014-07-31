----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    12:27:29 07/30/2014 
-- Module Name:    LED_CONTROL - rtl 
-- Project Name:   LED_CONTROL
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--   Modes (to be extended):
--    [0] = ws2801
--    [1] = ws2811
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity LED_CONTROL is
    generic (
        CLK_IN_PERIOD           : real;
        WS2801_LEDS_CLK_PERIOD  : real;
        MAX_LED_CNT             : natural := 100
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        MODE    : in std_ulogic_vector(0 downto 0);
        
        VSYNC       : in std_ulogic;
        RGB         : in std_ulogic_vector(23 downto 0);
        RGB_WR_EN   : in std_ulogic;
        
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end LED_CONTROL;

architecture rtl of LED_CONTROL is
    
    signal vsync_q      : std_ulogic := '0';
    signal frame_end    : std_ulogic := '0';
    
    signal ws2801_rst       : std_ulogic := '0';
    signal ws2801_start     : std_ulogic := '0';
    signal ws2801_leds_clk  : std_ulogic := '0';
    signal ws2801_leds_data : std_ulogic := '0';
    signal ws2801_rgb_rd_en : std_ulogic := '0';
    
    signal ws2811_rst       : std_ulogic := '0';
    signal ws2811_start     : std_ulogic := '0';
    signal ws2811_leds_data : std_ulogic := '0';
    signal ws2811_rgb_rd_en : std_ulogic := '0';
    
    signal fifo_rd_en   : std_ulogic := '0';
    signal fifo_dout    : std_ulogic_vector(23 downto 0) := x"000000";
    signal fifo_empty   : std_ulogic := '0';
    
begin
    
    LEDS_CLK    <= ws2801_leds_clk;
    
    with MODE select LEDS_DATA <=
        ws2801_leds_data when "0",
        ws2811_leds_data when others;
    
    ws2801_rst  <= '1' when MODE/="0" else '0';
    ws2811_rst  <= '1' when MODE/="1" else '0';
    
    ws2801_start    <= '1' when frame_end='1' and MODE="0" else '0';
    ws2811_start    <= '1' when frame_end='1' and MODE="1" else '0';
    
    frame_end   <= not VSYNC and vsync_q;
    
    fifo_rd_en  <= ws2801_rgb_rd_en or ws2811_rgb_rd_en;
    
    FIFO_inst : entity work.ASYNC_FIFO
        generic map (
            WIDTH   => 24,
            DEPTH   => MAX_LED_CNT
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            DIN     => RGB,
            RD_EN   => fifo_rd_en,
            WR_EN   => RGB_WR_EN,
            
            DOUT    => fifo_dout,
            EMPTY   => fifo_empty
        );
    
    LED_CONTROL_WS2801_inst : entity work.LED_CONTROL_WS2801
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            LEDS_CLK_PERIOD => WS2801_LEDS_CLK_PERIOD,
            MAX_LED_CNT     => MAX_LED_CNT
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
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            MAX_LED_CNT     => MAX_LED_CNT
        )
        port map (
            CLK => CLK,
            RST => ws2811_rst,
            
            START       => ws2811_start,
            STOP        => fifo_empty,
            RGB         => fifo_dout,
            
            RGB_RD_EN   => ws2811_rgb_rd_en,
            LEDS_DATA   => ws2811_leds_data
        );
    
    process(CLK)
    begin
        if rising_edge(CLK) then
            vsync_q <= VSYNC;
        end if;
    end process;
    
end rtl;

