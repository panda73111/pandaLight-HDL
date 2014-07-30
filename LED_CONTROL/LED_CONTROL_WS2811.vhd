----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    20:33:20 07/30/2014 
-- Module Name:    LED_CONTROL - rtl 
-- Project Name:   LED_CONTROL
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

entity LED_CONTROL_WS2811 is
    generic (
        CLK_IN_PERIOD   : real;
        MAX_LED_CNT     : natural := 100
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        START       : in std_ulogic;
        STOP        : in std_ulogic;
        RGB         : in std_ulogic_vector(23 downto 0);
        
        RGB_RD_EN   : in std_ulogic;
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end LED_CONTROL_WS2811;

architecture rtl of LED_CONTROL_WS2811 is
    
    -- tick at 10 MHz for a resolution of 0.1 ns
    constant LEDS_CLK_TICKS : natural := natural(0.1 / CLK_IN_PERIOD);
    
begin
    
    process(RST, CLK)
    begin
        
    end process;
    
end rtl;

