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
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity LED_CONTROL_WS2801 is
    generic (
        CLK_IN_PERIOD   : real;
        LEDS_CLK_PERIOD : real;
        MAX_LED_CNT     : natural := 100
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
    constant LEDS_CLK_TICKS : natural := natural(LEDS_CLK_PERIOD / CLK_IN_PERIOD) / 4;
    
    type state_type is (
        WAIT_FOR_START,
        GET_NEXT_RGB,
        WAIT_FOR_DATA_SWITCH,
        SET_DATA,
        DEC_BIT_I,
        WAIT_FOR_CLK_SWITCH,
        SET_CLK,
        CHECK_BIT_I,
        WAIT_FOR_LAST_SWITCH,
        SET_LAST_CLK_LOW
        );
    
    type reg_type is record
        state       : state_type;
        bit_i       : unsigned(5 downto 0);
        tick_cnt    : natural range 0 to LEDS_CLK_TICKS-1;
        leds_clk    : std_ulogic;
        leds_data   : std_ulogic;
        rgb_rd_en   : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAIT_FOR_START,
        bit_i       => "000000",
        tick_cnt    => 0,
        leds_clk    => '0',
        leds_data   => '0',
        rgb_rd_en   => '0'
        );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal switch               : std_ulogic := '0';
    
begin
    
    RGB_RD_EN   <= cur_reg.rgb_rd_en;
    LEDS_CLK    <= cur_reg.leds_clk;
    LEDS_DATA   <= cur_reg.leds_data;
    
    switch  <= '1' when cur_reg.tick_cnt=LEDS_CLK_TICKS-1 else '0';
    
    process(RST, cur_reg, START, STOP, RGB, switch)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.tick_cnt  := cr.tick_cnt+1;
        r.rgb_rd_en := '0';
        
        case cr.state is
            
            when WAIT_FOR_START =>
                r.tick_cnt  := 0;
                if START='1' then
                    r.state := GET_NEXT_RGB;
                end if;
            
            when GET_NEXT_RGB =>
                r.bit_i := uns(23, 6);
                r.state := WAIT_FOR_LAST_SWITCH;
                if STOP='0' then
                    r.rgb_rd_en := '1';
                    r.state     := WAIT_FOR_DATA_SWITCH;
                end if;
            
            when WAIT_FOR_DATA_SWITCH =>
                if switch='1' then
                    r.state     := SET_DATA;
                end if;
            
            when SET_DATA =>
                r.leds_clk  := '0';
                r.leds_data := RGB(int(cr.bit_i));
                if switch='1' then
                    r.state := DEC_BIT_I;
                end if;
            
            when DEC_BIT_I =>
                r.bit_i := cr.bit_i-1;
                r.state := WAIT_FOR_CLK_SWITCH;
            
            when WAIT_FOR_CLK_SWITCH =>
                if switch='1' then
                    r.state := SET_CLK;
                end if;
            
            when SET_CLK =>
                r.leds_clk  := '1';
                if switch='1' then
                    r.state := CHECK_BIT_I;
                end if;
            
            when CHECK_BIT_I =>
                r.state := WAIT_FOR_DATA_SWITCH;
                if cr.bit_i(5)='1' then
                    r.state := GET_NEXT_RGB;
                end if;
            
            when WAIT_FOR_LAST_SWITCH =>
                if switch='1' then
                    r.state := SET_LAST_CLK_LOW;
                end if;
                
            when SET_LAST_CLK_LOW =>
                r.leds_clk  := '0';
                r.state     := WAIT_FOR_START;
            
        end case;
        
        if switch='1' then
            r.tick_cnt  := 0;
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

