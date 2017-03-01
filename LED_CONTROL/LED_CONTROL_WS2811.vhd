----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    20:33:20 07/30/2014 
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

entity LED_CONTROL_WS2811 is
    generic (
        CLK_IN_PERIOD   : real
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        START       : in std_ulogic;
        STOP        : in std_ulogic;
        SLOW_MODE   : in std_ulogic;
        RGB         : in std_ulogic_vector(23 downto 0);
        
        RGB_RD_EN   : out std_ulogic;
        LEDS_DATA   : out std_ulogic := '0'
    );
end LED_CONTROL_WS2811;

architecture rtl of LED_CONTROL_WS2811 is
    
    -- ticks to the "logic high"/"logic low" time of a 1 Bit/0 Bit
    constant ONE_BIT_HIGH_TICKS     : natural := int(600.0 / CLK_IN_PERIOD); -- 1.2 us in slow mode, 0.6 us in fast mode
    constant ONE_BIT_LOW_TICKS      : natural := int(650.0 / CLK_IN_PERIOD); -- 1.3 us in slow mode, 0.65 us in fast mode
    constant ZERO_BIT_HIGH_TICKS    : natural := int(250.0 / CLK_IN_PERIOD); -- 0.5 us in slow mode, 0.25 us in fast mode
    constant ZERO_BIT_LOW_TICKS     : natural := int(1000.0 / CLK_IN_PERIOD); -- 2.0 us in slow mode, 1.0 us in fast mode
    
    constant TICK_BITS  : positive := log2(ZERO_BIT_LOW_TICKS);
    
    type state_type is (
        WAITING_FOR_START,
        GETTING_NEXT_RGB,
        WAITING_FOR_RGB,
        SLOW_EVALUATING_RGB_BIT,
        FAST_EVALUATING_RGB_BIT,
        SLOW_ONE_BIT_SETTING_HIGH,
        SLOW_ZERO_BIT_SETTING_HIGH,
        FAST_ONE_BIT_SETTING_HIGH,
        FAST_ZERO_BIT_SETTING_HIGH,
        SETTING_LOW,
        DECREMENTING_BIT_I,
        CHECKING_BIT_I
        );
    
    type reg_type is record
        state   : state_type;
        bit_i       : unsigned(5 downto 0);
        tick_cnt    : unsigned(TICK_BITS+1 downto 0);
        leds_data   : std_ulogic;
        rgb_rd_en   : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAITING_FOR_START,
        bit_i       => "000000",
        tick_cnt    => (others => '0'),
        leds_data   => '0',
        rgb_rd_en   => '0'
        );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal switch               : boolean := false;
    
begin
    
    RGB_RD_EN   <= cur_reg.rgb_rd_en;
    LEDS_DATA   <= cur_reg.leds_data;
    switch      <= cur_reg.tick_cnt(cur_reg.tick_cnt'high)='1';
    
    process(RST, cur_reg, START, STOP, RGB, switch)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.tick_cnt  := cr.tick_cnt-1;
        r.rgb_rd_en := '0';
        
        case cr.state is
            
            when WAITING_FOR_START =>
                r.tick_cnt  := (others => '0');
                if START='1' then
                    r.state := GETTING_NEXT_RGB;
                end if;
            
            when GETTING_NEXT_RGB =>
                r.bit_i := uns(23, 6);
                r.state := WAITING_FOR_START;
                if STOP='0' then
                    r.rgb_rd_en := '1';
                    r.state     := WAITING_FOR_RGB;
                end if;
            
            when WAITING_FOR_RGB =>
                r.state := SLOW_EVALUATING_RGB_BIT;
                if SLOW_MODE='0' then
                    r.state := FAST_EVALUATING_RGB_BIT;
                end if;
            
            when SLOW_EVALUATING_RGB_BIT =>
                r.tick_cnt  := uns(ZERO_BIT_HIGH_TICKS/2, TICK_BITS);
                r.state     := SLOW_ZERO_BIT_SETTING_HIGH;
                if RGB(int(cr.bit_i))='1' then
                    r.tick_cnt  := uns(ONE_BIT_HIGH_TICKS/2, TICK_BITS);
                    r.state     := SLOW_ONE_BIT_SETTING_HIGH;
                end if;
            
            when FAST_EVALUATING_RGB_BIT =>
                r.tick_cnt  := uns(ZERO_BIT_HIGH_TICKS, TICK_BITS);
                r.state     := FAST_ZERO_BIT_SETTING_HIGH;
                if RGB(int(cr.bit_i))='1' then
                    r.tick_cnt  := uns(ONE_BIT_HIGH_TICKS, TICK_BITS);
                    r.state     := FAST_ONE_BIT_SETTING_HIGH;
                end if;
            
            when SLOW_ZERO_BIT_SETTING_HIGH =>
                r.leds_data := '1';
                if switch then
                    r.tick_cnt  := uns(ZERO_BIT_LOW_TICKS/2, TICK_BITS);
                    r.state     := SETTING_LOW;
                end if;
            
            when SLOW_ONE_BIT_SETTING_HIGH =>
                r.leds_data := '1';
                if switch then
                    r.tick_cnt  := uns(ONE_BIT_LOW_TICKS/2, TICK_BITS);
                    r.state     := SETTING_LOW;
                end if;
            
            when FAST_ZERO_BIT_SETTING_HIGH =>
                r.leds_data := '1';
                if switch then
                    r.tick_cnt  := uns(ZERO_BIT_LOW_TICKS, TICK_BITS);
                    r.state     := SETTING_LOW;
                end if;
            
            when FAST_ONE_BIT_SETTING_HIGH =>
                r.leds_data := '1';
                if switch then
                    r.tick_cnt  := uns(ONE_BIT_LOW_TICKS, TICK_BITS);
                    r.state     := SETTING_LOW;
                end if;
            
            when SETTING_LOW =>
                r.leds_data := '0';
                if switch then
                    r.state := DECREMENTING_BIT_I;
                end if;
            
            when DECREMENTING_BIT_I =>
                r.bit_i := cr.bit_i-1;
                r.state := CHECKING_BIT_I;
            
            when CHECKING_BIT_I =>
                r.state := SLOW_EVALUATING_RGB_BIT;
                if SLOW_MODE='0' then
                    r.state := FAST_EVALUATING_RGB_BIT;
                end if;
                if cr.bit_i(5)='1' then
                    r.state := GETTING_NEXT_RGB;
                end if;
            
        end case;
        
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

