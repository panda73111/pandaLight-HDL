----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    20:15:50 07/30/2014 
-- Module Name:    LED_CONTROL - rtl 
-- Project Name:   LED_CONTROL
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

entity LED_CONTROL_WS2801 is
    generic (
        CLK_IN_PERIOD   : real;
        LEDS_CLK_PERIOD : real
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        START       : in std_ulogic;
        STOP        : in std_ulogic;
        RGB         : in std_ulogic_vector(23 downto 0);
        
        RGB_RD_EN   : out std_ulogic;
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end LED_CONTROL_WS2801;

architecture rtl of LED_CONTROL_WS2801 is
    
    -- tick at one fourth of LEDS_CLK_PERIOD
    constant LEDS_CLK_TICKS : natural := int(LEDS_CLK_PERIOD / CLK_IN_PERIOD) / 4;
    
    type state_type is (
        WAITING_FOR_START,
        GETTING_NEXT_RGB,
        WAITING_FOR_DATA_SWITCH,
        SETTING_DATA,
        DECREMENTING_BIT_I,
        WAITING_FOR_CLK_SWITCH,
        SETTING_CLK,
        CHECKING_BIT_I,
        WAITING_FOR_LAST_SWITCH,
        SETTING_LAST_CLK_LOW
        );
    
    type reg_type is record
        state       : state_type;
        bit_i       : unsigned(5 downto 0);
        tick_cnt    : unsigned(log2(LEDS_CLK_TICKS)+1 downto 0);
        leds_clk    : std_ulogic;
        leds_data   : std_ulogic;
        rgb_rd_en   : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAITING_FOR_START,
        bit_i       => "000000",
        tick_cnt    => (others => '0'),
        leds_clk    => '0',
        leds_data   => '0',
        rgb_rd_en   => '0'
        );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal switch               : boolean := false;
    
begin
    
    RGB_RD_EN   <= cur_reg.rgb_rd_en;
    LEDS_CLK    <= cur_reg.leds_clk;
    LEDS_DATA   <= cur_reg.leds_data;
    
    switch  <= cur_reg.tick_cnt(cur_reg.tick_cnt'high)='1';
    
    process(RST, cur_reg, START, STOP, RGB, switch)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.tick_cnt  := cr.tick_cnt-1;
        r.rgb_rd_en := '0';
        
        case cr.state is
            
            when WAITING_FOR_START =>
                r.tick_cnt  := uns(LEDS_CLK_TICKS, cur_reg.tick_cnt'length);
                if START='1' then
                    r.state := GETTING_NEXT_RGB;
                end if;
            
            when GETTING_NEXT_RGB =>
                r.bit_i := uns(23, 6);
                r.state := WAITING_FOR_LAST_SWITCH;
                if STOP='0' then
                    r.rgb_rd_en := '1';
                    r.state     := WAITING_FOR_DATA_SWITCH;
                end if;
            
            when WAITING_FOR_DATA_SWITCH =>
                if switch then
                    r.state     := SETTING_DATA;
                end if;
            
            when SETTING_DATA =>
                r.leds_clk  := '0';
                r.leds_data := RGB(int(cr.bit_i));
                if switch then
                    r.state := DECREMENTING_BIT_I;
                end if;
            
            when DECREMENTING_BIT_I =>
                r.bit_i := cr.bit_i-1;
                r.state := WAITING_FOR_CLK_SWITCH;
            
            when WAITING_FOR_CLK_SWITCH =>
                if switch then
                    r.state := SETTING_CLK;
                end if;
            
            when SETTING_CLK =>
                r.leds_clk  := '1';
                if switch then
                    r.state := CHECKING_BIT_I;
                end if;
            
            when CHECKING_BIT_I =>
                r.state := WAITING_FOR_DATA_SWITCH;
                if cr.bit_i(5)='1' then
                    r.state := GETTING_NEXT_RGB;
                end if;
            
            when WAITING_FOR_LAST_SWITCH =>
                if switch then
                    r.state := SETTING_LAST_CLK_LOW;
                end if;
                
            when SETTING_LAST_CLK_LOW =>
                r.leds_clk  := '0';
                r.state     := WAITING_FOR_START;
            
        end case;
        
        if switch then
            r.tick_cnt  := uns(LEDS_CLK_TICKS-2, cur_reg.tick_cnt'length);
        end if;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        next_reg    <= r;
    end process;
    
    stm_sync_proc : process(RST, CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;

