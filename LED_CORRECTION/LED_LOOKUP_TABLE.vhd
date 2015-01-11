----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    15:47:42 01/11/2015 
-- Module Name:    LED_LOOKUP_TABLE - rtl 
-- Project Name:   LED_CORRECTION
-- Tool versions:  Xilinx ISE 14.7
-- Description:
--
-- Additional Comments:
--  channel addresses:   [0]...[255] - R
--                     [256]...[511] - G
--                     [512]...[767] - B
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity LED_LOOKUP_TABLE is
    port (
        CLK : in std_ulogic;
        
        TABLE_ADDR  : in std_ulogic_vector(9 downto 0);
        TABLE_WR_EN : in std_ulogic;
        TABLE_DATA  : in std_ulogic_vector(7 downto 0);
        
        LED_IN_VSYNC        : in std_ulogic;
        LED_IN_RGB          : in std_ulogic_vector(23 downto 0);
        LED_IN_RGB_WR_EN    : in std_ulogic;
        
        LED_OUT_VSYNC       : out std_ulogic := '0';
        LED_OUT_RGB         : out std_ulogic_vector(23 downto 0) := x"000000";
        LED_OUT_RGB_VALID   : out std_ulogic := '0'
    );
end LED_LOOKUP_TABLE;

architecture rtl of LED_LOOKUP_TABLE is
    
begin
    
    channel_DUAL_PORT_RAMs_gen : for i in 0 to 2 generate
        signal wr_en    : std_ulogic := '0';
    begin
        
        -- 0 = R
        -- 1 = G
        -- 2 = B
        wr_en   <= '1' when
                TABLE_WR_EN='1' and
                TABLE_ADDR(9 downto 8)=i
            else '0';
        
        DUAL_PORT_RAM_inst : entity work.DUAL_PORT_RAM
            generic map (
                WIDTH   => 8,
                DEPTH   => 256
            )
            port map (
                CLK => CLK,
                
                RD_ADDR => LED_IN_RGB(23-i*8 downto 16-i*8),
                WR_EN   => wr_en,
                WR_ADDR => TABLE_ADDR(7 downto 0),
                DIN     => TABLE_DATA,
                
                DOUT    => LED_OUT_RGB(23-i*8 downto 16-i*8)
            );
        
    end generate;
    
    sync_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            LED_OUT_VSYNC       <= LED_IN_VSYNC;
            LED_OUT_RGB_VALID   <= LED_IN_RGB_WR_EN;
        end if;
    end process;
    
end rtl;
