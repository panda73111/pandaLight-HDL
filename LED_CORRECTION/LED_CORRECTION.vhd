----------------------------------------------------------------------------------
-- Engineer: Sebastian Hüther
-- 
-- Create Date:    11:12:37 08/03/2014 
-- Module Name:    LED_CORRECTION - rtl 
-- Project Name:   LED_CORRECTION
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

entity LED_CORRECTION is
    generic (
        MAX_LED_COUNT   : natural;
        MAX_BUFFER_SIZE : natural
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CFG_ADDR    : in std_ulogic_vector(1 downto 0);
        CFG_WR_EN   : in std_ulogic := '0';
        CFG_DATA    : in std_ulogic := '0';
        
        LED_VSYNC_IN        : in std_ulogic;
        LED_RGB_IN          : in std_ulogic_vector(23 downto 0);
        LED_RGB_IN_VALID    : in std_ulogic;
        LED_NUM             : in std_ulogic_vector(7 downto 0);
        
        LED_VSYNC_OUT       : out std_ulogic := '0';
        LED_RGB_OUT         : out std_ulogic_vector(23 downto 0) := x"000000";
        LED_RGB_OUT_VALID   : out std_ulogic := '0'
    );
end LED_CORRECTION;

architecture rtl of LED_CORRECTION is
    
    signal skip_counter     : unsigned(7 downto 0) := x"00";
    signal start_led_num    : unsigned(7 downto 0) := x"00";
    signal skipped          : boolean := false;
    
    signal fifo_rst     : std_ulogic := '0';
    signal fifo_din     : std_ulogic_vector(24 downto 0) := x"000000";
    signal fifo_rd_en   : std_ulogic := '0';
    signal fifo_wr_en   : std_ulogic := '0';
    signal fifo_dout    : std_ulogic_vector(24 downto 0) := x"000000";
    signal fifo_rd_ack  : std_ulogic := '0';
    
begin
    
    fifo_rst    <= RST or CFG_WR_EN;
    skipped     <= skip_counter=start_led_num;
    
    cfg_proc : process(RST, CLK)
    begin
        if RST='1' then
            start_led_num   <= x"00";
        elsif rising_edge(CLK) then
            if CFG_WR_EN='1' and LED_VSYNC_IN='0' then
                case CFG_ADDR is
                    when "00" => start_led_num  <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    process(RST, CLK)
    begin
        if RST='1' then
            skip_counter    <= x"00";
            skipped         <= false;
        elsif rising_edge(CLK) then
            if
                not skipped and
                LED_VSYNC_IN='1' and
                LED_RGB_IN_VALID='1'
            then
                skip_counter    <= skip_counter+1;
            end if;
            if CFG_WR_EN='1' then
                skip_counter    <= x"00";
            end if;
        end if;
    end process;
    
    ASYNC_FIFO_inst : entity work.ASYNC_FIFO
        generic map (
            WIDTH   => 24,
            DEPTH   => MAX_BUFFER_SIZE
        )
        port map (
            CLK => CLK,
            RST => fifo_rst,
            
            DIN     => fifo_din,
            RD_EN   => fifo_rd_en,
            WR_EN   => fifo_wr_en,
            
            DOUT    => fifo_dout,
            RD_ACK  => fifo_rd_ack
        );
    
end rtl;

