----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    19:02:16 09/18/2014 
-- Module Name:    UART_DEBUG - rtl 
-- Project Name:   Pipistrello-HDMI-Tests
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity UART_DEBUG is
    generic (
        CLK_IN_PERIOD   : real;
        STR_LEN         : positive := 128
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        MSG     : in string(1 to 128);
        WR_EN   : in std_ulogic;
        CTS     : in std_ulogic;
        
        DONE    : out std_ulogic := '0';
        FULL    : out std_ulogic := '0';
        TXD     : out std_ulogic := '1'
    );
end UART_DEBUG;

architecture rtl of UART_DEBUG is
    signal sender_din   : std_ulogic_vector(7 downto 0) := x"00";
    signal sender_wr_en : std_ulogic := '0';
    signal sender_full  : std_ulogic := '0';
    signal char_index   : natural range 0 to STR_LEN := 0;
    signal writing      : boolean := false;
begin
    
    FULL    <= sender_full;
    
    UART_SENDER_inst : entity work.UART_SENDER
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            DIN     => sender_din,
            WR_EN   => sender_wr_en,
            CTS     => CTS,
            
            TXD     => TXD,
            FULL    => sender_full,
            BUSY    => open
        );
    
    process(RST, CLK)
    begin
        if RST='1' then
            sender_wr_en    <= '0';
            char_index      <= 0;
            writing         <= false;
        elsif rising_edge(CLK) then
            sender_wr_en    <= '0';
            if WR_EN='1' then
                writing <= true;
            end if;
            if writing then
                if sender_full='0' then
                    sender_wr_en    <= '1';
                    sender_din      <= stdulv(MSG(char_index));
                    char_index      <= char_index+1;
                end if;
                if MSG(char_index)=nul then
                    sender_din  <= stdulv(lf);
                    writing     <= false;
                end if;
            else
                char_index  <= 0;
            end if;
        end if;
    end process;
    
end rtl;

