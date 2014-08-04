----------------------------------------------------------------------------------
-- Engineer: Sebastian Hther
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
use work.help_funcs.all;

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
        CFG_DATA    : in std_ulogic_vector(7 downto 0) := x"00";
        
        LED_VSYNC_IN        : in std_ulogic;
        LED_RGB_IN          : in std_ulogic_vector(23 downto 0);
        LED_RGB_IN_WR_EN    : in std_ulogic;
        
        LED_VSYNC_OUT       : out std_ulogic := '0';
        LED_RGB_OUT         : out std_ulogic_vector(23 downto 0) := x"000000";
        LED_RGB_OUT_VALID   : out std_ulogic := '0'
    );
end LED_CORRECTION;

architecture rtl of LED_CORRECTION is
    
    constant MAX_FRAME_COUNT    : natural := MAX_BUFFER_SIZE/MAX_LED_COUNT;
    
    type led_buf_type is
        array (0 to MAX_BUFFER_SIZE-1) of
        std_ulogic_vector(23 downto 0);
    
    signal led_buf              : led_buf_type;
    signal led_buf_rst          : std_ulogic := '0';
    signal led_buf_rd_p         : natural range 0 to MAX_BUFFER_SIZE-1 := 0;
    signal led_buf_wr_p         : natural range 0 to MAX_BUFFER_SIZE-1 := 0;
    signal led_buf_led_i        : natural range 0 to MAX_LED_COUNT-1 := 0;
    signal led_buf_frame_p      : natural range 0 to MAX_BUFFER_SIZE-1 := 0;
    signal led_buf_rd_frame_i   : natural range 0 to MAX_FRAME_COUNT-1 := 0;
    signal led_buf_wr_frame_i   : natural range 0 to MAX_FRAME_COUNT-1 := 0;
    
    signal led_vsync_in_q   : std_ulogic := '0';
    signal frame_end        : std_ulogic := '0';
    signal start_read       : std_ulogic := '0';
    
    -- configuration registers
    signal led_count        : std_ulogic_vector(7 downto 0) := x"00";
    signal start_led_num    : std_ulogic_vector(7 downto 0) := x"00";
    signal frame_delay      : std_ulogic_vector(7 downto 0) := x"00";
    signal rgb_mode         : std_ulogic_vector(2 downto 0) := "000";
    
begin
    
    frame_end   <= not LED_VSYNC_IN and led_vsync_in_q;
    
    cfg_proc : process(RST, CLK)
    begin
        if RST='1' then
            led_count       <= x"00";
            start_led_num   <= x"00";
            frame_delay     <= x"00";
            rgb_mode        <= "000";
        elsif rising_edge(CLK) then
            led_buf_rst <= '0';
            if CFG_WR_EN='1' and LED_VSYNC_IN='0' then
                case CFG_ADDR is
                    when "00" => led_count      <= CFG_DATA;
                    when "01" => start_led_num  <= CFG_DATA;
                    when "10" => frame_delay    <= CFG_DATA;
                    when "11" => rgb_mode       <= CFG_DATA(2 downto 0);
                    when others => null;
                end case;
                led_buf_rst <= '1';
            end if;
        end if;
    end process;
    
    led_buf_write_proc : process(RST, CLK)
        alias r is LED_RGB_IN(23 downto 16);
        alias g is LED_RGB_IN(15 downto 8);
        alias b is LED_RGB_IN(7 downto 0);
        variable din    : std_ulogic_vector(23 downto 0);
    begin
        if RST='1' then
            led_buf_wr_p        <= 0;
            led_buf_led_i       <= 0;
            led_buf_frame_p     <= 0;
            led_buf_wr_frame_i  <= 0;
        elsif rising_edge(CLK) then
            if LED_RGB_IN_WR_EN='1' then
                case rgb_mode is
                    when "000" => din   := r & g & b;
                    when "001" => din   := r & b & g;
                    when "010" => din   := g & r & b;
                    when "011" => din   := g & b & r;
                    when "100" => din   := b & r & g;
                    when "101" => din   := b & g & r;
                    when others => null;
                end case;
                led_buf(led_buf_wr_p)   <= din;
                led_buf_wr_p            <= led_buf_wr_p+1;
                led_buf_led_i           <= led_buf_led_i+1;
                if led_buf_led_i=led_count-1 then
                    led_buf_wr_p    <= led_buf_frame_p;
                    led_buf_led_i   <= 0;
                end if;
            end if;
            if frame_end='1' then
                led_buf_wr_p        <= int(led_count)+led_buf_wr_p;
                led_buf_frame_p     <= int(led_count)+led_buf_frame_p;
                led_buf_wr_frame_i  <= led_buf_wr_frame_i+1;
            end if;
            if
                led_buf_rst='1' or
                (frame_end='1' and led_buf_wr_frame_i=frame_delay)
            then
                led_buf_wr_p        <= int(start_led_num);
                led_buf_led_i       <= int(start_led_num);
                led_buf_frame_p     <= 0;
                led_buf_wr_frame_i  <= 0;
            end if;
        end if;
    end process;
    
    led_buf_read_proc : process(RST, CLK)
    begin
        if RST='1' then
            start_read          <= '0';
            led_buf_rd_p        <= 0;
            led_buf_rd_frame_i  <= 0;
        elsif rising_edge(CLK) then
            if start_read='1' then
                if LED_RGB_IN_WR_EN='1' then
                    LED_RGB_OUT     <= led_buf(led_buf_rd_p);
                    led_buf_rd_p    <= led_buf_rd_p+1;
                end if;
                if frame_delay=0 then
                    LED_RGB_OUT <= LED_RGB_IN;
                end if;
                if frame_end='1' then
                    led_buf_rd_frame_i  <= led_buf_rd_frame_i+1;
                end if;
            end if;
            if led_buf_wr_frame_i=frame_delay then
                start_read  <= '1';
            end if;
            if led_buf_rst='1' then
                start_read  <= '0';
            end if;
            if
                led_buf_rst='1' or
                (frame_end='1' and led_buf_rd_frame_i=frame_delay)
            then
                led_buf_rd_p        <= 0;
                led_buf_rd_frame_i  <= 0;
            end if;
            LED_VSYNC_OUT       <= LED_VSYNC_IN and start_read;
            LED_RGB_OUT_VALID   <= LED_RGB_IN_WR_EN and start_read;
        end if;
    end process;
    
    process(CLK)
    begin
        if rising_edge(CLK) then
            led_vsync_in_q  <= LED_VSYNC_IN;
        end if;
    end process;
    
end rtl;

