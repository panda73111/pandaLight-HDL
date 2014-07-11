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
-----------------CHANNEL_NUM : natural range 0 to 2-----------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity TMDS_CHANNEL_DECODER is
    generic (
        CHANNEL_NUM     : natural range 0 to 2;
        SIM_TAP_DELAY   : integer range 20 to 100 := 50
    );
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
    
    signal channel_in           : std_ulogic := '0';
    signal bitslip              : std_ulogic := '0';
    signal idelay_incdec        : std_ulogic := '0';
    signal master_d, slave_d    : std_ulogic := '0';
    signal iserdes_d_valid      : std_ulogic := '0';
    
    signal gearbox_data_select  : std_ulogic := '0';
    signal gearbox_x2_data      : std_ulogic_vector(4 downto 0) := (others => '0');
    signal gearbox_x1_data      : std_ulogic_vector(9 downto 0) := (others => '0');
    
begin
    
    -----------------------------
    --- entity instantiations ---
    -----------------------------
    
    IBUFDS_inst : IBUFDS
        generic map (
            IOSTANDARD  => "TMDS_33"
        )
        port map (
            O   => channel_in,
            I   => CHANNEL_IN_P,
            IB  => CHANNEL_IN_N
        );
    
    TMDS_CHANNEL_DELAY_inst : entity work.TMDS_CHANNEL_IDELAY
        generic map (
            SIM_TAP_DELAY   => SIM_TAP_DELAY
        )
        port map (
            PIX_CLK_X10 => PIX_CLK_X10,
            PIX_CLK_X2  => PIX_CLK_X2,
            RST         => RST,
            
            SERDESSTROBE    => SERDESSTROBE,
            CHANNEL_IN      => channel_in,
            INCDEC          => idelay_incdec,
            DIN_VALID       => iserdes_d_valid,
            
            MASTER_DOUT => master_d,
            SLAVE_DOUT  => slave_d
        );
    
    TMDS_CHANNEL_ISERDES_inst : entity work.TMDS_CHANNEL_ISERDES
        port map (
            PIX_CLK_X10 => PIX_CLK_X10,
            PIX_CLK_X2  => PIX_CLK_X2,
            RST         => RST,
            
            MASTER_DIN      => master_d,
            SLAVE_DIN       => slave_d,
            SERDESSTROBE    => SERDESSTROBE,
            BITSLIP         => bitslip,
            
            INCDEC      => idelay_incdec,
            DOUT        => gearbox_x2_data,
            DOUT_VALID  => iserdes_d_valid
        );
    
    
    -----------------------
    --- 5 to 10 gearbox ---
    -----------------------
    
    gearbox_proc : process(PIX_CLK_X2)
    begin
        if rising_edge(PIX_CLK_X2) then
            -- less significant 5 bits first
            if gearbox_data_select = '0' then
                gearbox_x1_data(4 downto 0) <= gearbox_x2_data;
            else
                gearbox_x1_data(9 downto 5) <= gearbox_x2_data;
            end if;
            gearbox_data_select <= not gearbox_data_select;
        end if;
    end process;
    
end rtl;

