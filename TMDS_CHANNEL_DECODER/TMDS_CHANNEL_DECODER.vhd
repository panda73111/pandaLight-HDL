----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    09:40:21 02/07/2014 
-- Module Name:    TMDS_CHANNEL_DECODER - rtl
-- Description:    Decoder of a single TMDS channel compliant to the
--                 HDMI 1.4 specification
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

entity TMDS_CHANNEL_DECODER is
    port (
        PIX_CLK         : in std_ulogic;
        PIX_CLK_X2      : in std_ulogic;
        PIX_CLK_X10     : in std_ulogic;
        RST             : in std_ulogic;
        CLK_LOCKED      : in std_ulogic;
        SERDESSTROBE    : in std_ulogic;
        CHANNEL_IN_P    : in std_ulogic;
        CHANNEL_IN_N    : in std_ulogic;
        DATA_OUT        : out std_ulogic_vector(7 downto 0) := (others => '0');
        ENCODING        : out std_ulogic_vector(2 downto 0)
    );
end TMDS_CHANNEL_DECODER;

architecture rtl of TMDS_CHANNEL_DECODER is
    signal channel_in   : std_ulogic := '0';
begin
    
    ibuf_inst : IBUFDS
        generic map (
            IOSTANDARD  => "TMDS_33"
        )
        port map (
            O   => channel_in,
            I   => CHANNEL_IN_P,
            IB  => CHANNEL_IN_N
        );
    
end rtl;

