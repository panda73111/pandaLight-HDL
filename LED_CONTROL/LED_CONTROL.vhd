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
        CLK_IN_PERIOD   : real;
        LEDS_CLK_PERIOD : real
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        MODE    : in std_ulogic_vector(0 downto 0);
        
        VSYNC   : in std_ulogic;
        HSYNC   : in std_ulogic;
        
        RGB : in std_ulogic_vector(23 downto 0);
        
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end LED_CONTROL;

architecture rtl of LED_CONTROL is
    
    constant LEDS_CLK_TICKS : natural := natural(LEDS_CLK_PERIOD / CLK_IN_PERIOD);
    constant TICK_CNT_BITS  : natural := log2(LEDS_CLK_TICKS);
    
    signal tick_cnt         : unsigned(TICK_CNT_BITS-1 downto 0) := (others => '0');
    
    alias tick_cnt_quarter  : unsigned is tick_cnt(TICK_CNT_BITS-3 downto 0);
    
begin
    
    process(RST, CLK)
    begin
        
    end process;
    
end rtl;

