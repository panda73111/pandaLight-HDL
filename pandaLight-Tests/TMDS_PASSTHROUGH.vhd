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
        PIX_CLK : in std_ulogic;
        RST     : in std_ulogic;
        
        RX_ENC_DATA         : in std_ulogic_vector(14 downto 0);
        RX_ENC_DATA_VALID   : in std_ulogic;
        
        TX_CHANNELS_OUT : out std_ulogic_vector(3 downto 0)
    );
end TMDS_PASSTHROUGH;

architecture rtl of TMDS_PASSTHROUGH is
    
    type serdes_din_type is
        array(0 to 3) of
        std_ulogic_vector(4 downto 0);
    
    signal pix_clk_x2   : std_ulogic := '0';
    signal pix_clk_x10  : std_ulogic := '0';
    signal serdesstrobe : std_ulogic := '0';
    
    signal serdes_rst   : std_ulogic := '0';
    signal serdes_din   : serdes_din_type := (others => "00000");
    
    signal cascade_di   : std_ulogic_vector(3 downto 0) := "0000";
    signal cascade_do   : std_ulogic_vector(3 downto 0) := "0000";
    signal cascade_ti   : std_ulogic_vector(3 downto 0) := "0000";
    signal cascade_to   : std_ulogic_vector(3 downto 0) := "0000";
    
    signal tx_clk   : std_ulogic := '0';
    signal tx_clk_v : std_ulogic_vector(4 downto 0) := "00000";
    
begin
    
    serdes_rst  <= RST or not RX_ENC_DATA_VALID;
    
    serdes_din(3)   <= tx_clk_v;
    serdes_din(2)   <= RX_ENC_DATA(14 downto 10);
    serdes_din(1)   <= RX_ENC_DATA(9 downto 5);
    serdes_din(0)   <= RX_ENC_DATA(4 downto 0);
    
    tx_clk_v    <= "11111" when tx_clk='1' else "00000";
    
    OSERDES2_CLK_MAN_inst : entity work.OSERDES2_CLK_MAN
        generic map (
            CLK_IN_PERIOD   => 7.0,
            MULTIPLIER      => 10,
            DIVISOR0        => 1,
            DIVISOR1        => 5,
            DIVISOR2        => 10,
            IO_CLK_SELECT   => 0,
            DATA_CLK_SELECT => 1,
            SKIP_INBUF      => true
        )
        port map (
            CLK_IN  => PIX_CLK,
            
            CLK_OUT1        => pix_clk_x2,
            IOCLK_OUT       => pix_clk_x10,
            SERDESSTROBE    => serdesstrobe
        );
    
    OSERDES_gen : for i in 0 to 3 generate
        
        master_OSERDES_inst : OSERDES2
            generic map (
                DATA_WIDTH      => 5,
                DATA_RATE_OQ    => "SDR",
                DATA_RATE_OT    => "SDR",
                SERDES_MODE     => "MASTER",
                OUTPUT_MODE     => "DIFFERENTIAL"
            )
            port map (
                OQ          => TX_CHANNELS_OUT(i),
                OCE         => '1',
                CLK0        => pix_clk_x10,
                CLK1        => '0',
                IOCE        => serdesstrobe,
                RST         => serdes_rst,
                CLKDIV      => pix_clk_x2,
                D4          => '0',
                D3          => '0',
                D2          => '0',
                D1          => serdes_din(i)(4),
                TQ          => open,
                T1          => '0',
                T2          => '0',
                T3          => '0',
                T4          => '0',
                TRAIN       => '0',
                TCE         => '1',
                SHIFTIN1    => '1',
                SHIFTIN2    => '1',
                SHIFTIN3    => cascade_do(i), -- Cascade output D data from slave
                SHIFTIN4    => cascade_to(i), -- Cascade output T data from slave
                SHIFTOUT1   => cascade_di(i), -- Cascade input D data to slave
                SHIFTOUT2   => cascade_ti(i), -- Cascade input T data to slave
                SHIFTOUT3   => open,
                SHIFTOUT4   => open
            );
        
        slave_OSERDES_inst : OSERDES2
            generic map (
                DATA_WIDTH      => 5,
                DATA_RATE_OQ    => "SDR",
                DATA_RATE_OT    => "SDR",
                SERDES_MODE     => "SLAVE",
                OUTPUT_MODE     => "DIFFERENTIAL"
            )
            port map (
            OQ          => open,
            OCE         => '1',
            CLK0        => pix_clk_x10,
            CLK1        => '0',
            IOCE        => serdesstrobe,
            RST         => serdes_rst,
            CLKDIV      => pix_clk_x2,
            D4          => serdes_din(i)(3),
            D3          => serdes_din(i)(2),
            D2          => serdes_din(i)(1),
            D1          => serdes_din(i)(0),
            TQ          => open,
            T1          => '0',
            T2          => '0',
            T3          => '0',
            T4          => '0',
            TRAIN       => '0',
            TCE         => '1',
            SHIFTIN1    => cascade_di(i), -- Cascade input D from Master
            SHIFTIN2    => cascade_ti(i), -- Cascade input T from Master
            SHIFTIN3    => '1',
            SHIFTIN4    => '1',
            SHIFTOUT1   => open,
            SHIFTOUT2   => open,
            SHIFTOUT3   => cascade_do(i), -- Cascade output D data to Master
            SHIFTOUT4   => cascade_to(i)  -- Cascade output T data to Master
        );
        
    end generate;
    
    tx_clk_proc : process(RST, pix_clk_x2)
    begin
        if RST='1' then
            tx_clk  <= '0';
        elsif rising_edge(pix_clk_x2) then
            tx_clk  <= not tx_clk;
            if RX_ENC_DATA_VALID='0' then
                tx_clk  <= '0';
            end if;
        end if;
    end process;
    
end rtl;
