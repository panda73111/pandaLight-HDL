----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:04:59 07/11/2014 
-- Design Name:    TMDS_CHANNEL_DECODER
-- Module Name:    TMDS_CHANNEL_ISERDES - rtl 
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

entity TMDS_CHANNEL_ISERDES is
    port (
        PIX_CLK_X10 : in std_ulogic;
        PIX_CLK_X2  : in std_ulogic;
        RST         : in std_ulogic;
        
        MASTER_DIN      : in std_ulogic;
        SLAVE_DIN       : in std_ulogic;
        SERDESSTROBE    : in std_ulogic;
        BITSLIP         : in std_ulogic;
        
        INCDEC          : out std_ulogic := '0';
        INCDEC_VALID    : out std_ulogic := '0';
        DOUT            : out std_ulogic_vector(4 downto 0) := "00000"
    );
end TMDS_CHANNEL_ISERDES;

architecture rtl of TMDS_CHANNEL_ISERDES is
    
    signal pd_edge  : std_ulogic;
    signal cascade  : std_ulogic;
    
begin
    
    -- master
    
    ISERDES2_master_inst : ISERDES2
        generic map (
            DATA_WIDTH     		=> 5,
            DATA_RATE      		=> "SDR",
            BITSLIP_ENABLE 		=> TRUE,
            SERDES_MODE    		=> "MASTER",
            INTERFACE_TYPE 		=> "RETIMED"
        )
        port map (
            D           => MASTER_DIN,
            CE0         => '1',
            CLK0        => PIX_CLK_X10,
            CLK1        => '0',
            IOCE        => SERDESSTROBE,
            RST         => RST,
            CLKDIV      => PIX_CLK_X2,
            SHIFTIN     => pd_edge,
            BITSLIP     => BITSLIP,
            FABRICOUT   => open,
            Q4          => DOUT(4),
            Q3          => DOUT(3),
            Q2          => DOUT(2),
            Q1          => DOUT(1),
            DFB         => open,
            CFB0        => open,
            CFB1        => open,
            VALID       => INCDEC_VALID,
            INCDEC      => INCDEC,
            SHIFTOUT    => cascade
        );
    
    -- slave
    
    ISERDES2_slave_inst : ISERDES2
        generic map (
            DATA_WIDTH     		=> 5,
            DATA_RATE      		=> "SDR",
            BITSLIP_ENABLE 		=> TRUE,
            SERDES_MODE    		=> "SLAVE",
            INTERFACE_TYPE 		=> "RETIMED"
        )
        port map (
            D           => SLAVE_DIN,
            CE0         => '1',
            CLK0        => PIX_CLK_X10,
            CLK1        => '0',
            IOCE        => SERDESSTROBE,
            RST         => RST,
            CLKDIV      => PIX_CLK_X2,
            SHIFTIN     => cascade,
            BITSLIP     => BITSLIP,
            FABRICOUT   => open,
            Q4          => DOUT(0),
            Q3          => open,
            Q2          => open,
            Q1          => open,
            DFB         => open,
            CFB0        => open,
            CFB1        => open,
            VALID       => open,
            INCDEC      => open,
            SHIFTOUT    => pd_edge
        );
    
    
end rtl;

