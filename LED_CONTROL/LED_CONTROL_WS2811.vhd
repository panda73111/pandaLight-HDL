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
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity LED_CONTROL_WS2811 is
    generic (
        CLK_IN_PERIOD   : real;
        MAX_LED_CNT     : natural := 100
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
    
    -- ticks in one 800 kHz clock cycle
    constant TICKS  : natural := natural(1250.0 / CLK_IN_PERIOD);
    
    -- in tens of a nanoseconds
    constant HIGH_BIT_TICKS : natural := 60; -- 1.2 us, 0.6 us in fast mode
    constant LOW_BIT_TICKS  : natural := 25; -- 0.5 us, 0.25 us in fast mode
    
    type state_type is (
        WAIT_FOR_START,
        GET_NEXT_RGB,
        WAIT_FOR_RGB,
        EVAL_RGB_BIT,
        HIGH_BIT_SET_HIGH,
        LOW_BIT_SET_HIGH,
        SET_LOW,
        DEC_BIT_I,
        CHECK_BIT_I
        );
    
    type reg_type is record
        state   : state_type;
        bit_i       : unsigned(5 downto 0);
        tick_cnt    : natural range 0 to 2*TICKS-1;
        leds_data   : std_ulogic;
        rgb_rd_en   : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAIT_FOR_START,
        bit_i       => "000000",
        tick_cnt    => 0,
        leds_data   => '0',
        rgb_rd_en   => '0'
        );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal tick_cnt             : natural range 0 to TICKS-1 := 0;
    
begin
    
    RGB_RD_EN   <= cur_reg.rgb_rd_en;
    LEDS_DATA   <= cur_reg.leds_data;
    
    -- in slow mode, count half as fast
    tick_cnt    <=
        cur_reg.tick_cnt when SLOW_MODE='0' else
        cur_reg.tick_cnt/2;
    
    process(RST, cur_reg, START, STOP, RGB, tick_cnt)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.tick_cnt  := cr.tick_cnt+1;
        r.rgb_rd_en := '0';
        
        if tick_cnt=TICKS-1 then
            r.tick_cnt  := 0;
        end if;
        
        case cr.state is
            
            when WAIT_FOR_START =>
                r.tick_cnt  := 0;
                if START='1' then
                    r.state := GET_NEXT_RGB;
                end if;
            
            when GET_NEXT_RGB =>
                r.bit_i := uns(23, 6);
                r.state := WAIT_FOR_START;
                if STOP='0' then
                    r.rgb_rd_en := '1';
                    r.state     := WAIT_FOR_RGB;
                end if;
            
            when WAIT_FOR_RGB =>
                r.state := EVAL_RGB_BIT;
            
            when EVAL_RGB_BIT =>
                r.tick_cnt  := 0;
                r.state     := LOW_BIT_SET_HIGH;
                if RGB(int(cr.bit_i))='1' then
                    r.state     := HIGH_BIT_SET_HIGH;
                end if;
            
            when LOW_BIT_SET_HIGH =>
                r.leds_data := '1';
                if tick_cnt=LOW_BIT_TICKS-1 then
                    r.state     := SET_LOW;
                end if;
            
            when HIGH_BIT_SET_HIGH =>
                r.leds_data := '1';
                if tick_cnt=HIGH_BIT_TICKS-1 then
                    r.state     := SET_LOW;
                end if;
            
            when SET_LOW =>
                r.leds_data := '0';
                if tick_cnt=TICKS-4 then
                    -- compensate tick loss due to state machine
                    r.state := DEC_BIT_I;
                end if;
            
            when DEC_BIT_I =>
                r.bit_i := cr.bit_i-1;
                r.state := CHECK_BIT_I;
            
            when CHECK_BIT_I =>
                r.state := EVAL_RGB_BIT;
                if cr.bit_i(5)='1' then
                    r.state := GET_NEXT_RGB;
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

