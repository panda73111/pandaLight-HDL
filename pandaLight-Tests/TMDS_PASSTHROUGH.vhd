----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:51:11 08/06/2014 
-- Module Name:    TMDS_PASSTHROUGH - rtl 
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

entity TMDS_PASSTHROUGH is
    port (
        PIX_CLK     : in std_ulogic;
        PIX_CLK_X2  : in std_ulogic;
        PIX_CLK_X10 : in std_ulogic;
        RST         : in std_ulogic;
        
        SERDESSTROBE    : in std_ulogic;
        RX_DIN          : in std_ulogic_vector(4 downto 0);
        
        TX_CHANNELS_OUT : out std_ulogic_vector(3 downto 0)
    );
end TMDS_PASSTHROUGH;

architecture rtl of TMDS_PASSTHROUGH is

begin
    
    
    
end rtl;
