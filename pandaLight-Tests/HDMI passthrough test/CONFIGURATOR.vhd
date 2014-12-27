----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    15:32:18 12/10/2014 
-- Module Name:    CONFIGURATOR - rtl 
-- Project Name:   CONFIGURATOR
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

entity CONFIGURATOR is
    generic (
        -- dummy values
        HOR_LED_CNT     : std_ulogic_vector(7 downto 0) := stdulv(16, 8);
        HOR_LED_WIDTH   : std_ulogic_vector(7 downto 0) := stdulv(60, 8);
        HOR_LED_HEIGHT  : std_ulogic_vector(7 downto 0) := stdulv(80, 8);
        HOR_LED_STEP    : std_ulogic_vector(7 downto 0) := stdulv(80, 8);
        HOR_LED_PAD     : std_ulogic_vector(7 downto 0) := stdulv( 5, 8);
        HOR_LED_OFFS    : std_ulogic_vector(7 downto 0) := stdulv(10, 8);
        VER_LED_CNT     : std_ulogic_vector(7 downto 0) := stdulv( 9, 8);
        VER_LED_WIDTH   : std_ulogic_vector(7 downto 0) := stdulv(80, 8);
        VER_LED_HEIGHT  : std_ulogic_vector(7 downto 0) := stdulv(60, 8);
        VER_LED_STEP    : std_ulogic_vector(7 downto 0) := stdulv(80, 8);
        VER_LED_PAD     : std_ulogic_vector(7 downto 0) := stdulv( 5, 8);
        VER_LED_OFFS    : std_ulogic_vector(7 downto 0) := stdulv( 1, 8)
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CONFIGURE   : in std_ulogic;
        
        FRAME_WIDTH     : in std_ulogic_vector(10 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(10 downto 0);
        
        CFG_SEL_LEDEX   : out std_ulogic := '0';
        
        CFG_ADDR    : out std_ulogic_vector(3 downto 0) := "0000";
        CFG_WR_EN   : out std_ulogic := '0';
        CFG_DATA    : out std_ulogic_vector(7 downto 0) := x"00"
    );
end CONFIGURATOR;

architecture rtl of CONFIGURATOR is
    
    type state_type is (
        WAIT_FOR_START,
        CONFIGURE_LEDEX
    );
    
    type reg_type is record
        state           : state_type;
        cfg_sel_ledex   : std_ulogic;
        cfg_addr        : std_ulogic_vector(3 downto 0);
        cfg_wr_en       : std_ulogic;
        cfg_data        : std_ulogic_vector(7 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => WAIT_FOR_START,
        cfg_sel_ledex   => '0',
        cfg_addr        => "0000",
        cfg_wr_en       => '0',
        cfg_data        => x"00"
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
begin
    
    CFG_SEL_LEDEX   <= cur_reg.cfg_sel_ledex;
    CFG_ADDR        <= cur_reg.cfg_addr;
    CFG_WR_EN       <= cur_reg.cfg_wr_en;
    CFG_DATA        <= cur_reg.cfg_data;
    
    stm_proc : process(RST, cur_reg, CONFIGURE, FRAME_WIDTH, FRAME_HEIGHT)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r               := cr;
        r.cfg_sel_ledex := '0';
        r.cfg_wr_en     := '0';
        
        case cr.state is
            
            when WAIT_FOR_START =>
                r.cfg_addr  := (others => '0');
                if CONFIGURE='1' then
                    r.state := CONFIGURE_LEDEX;
                end if;
            
            when CONFIGURE_LEDEX =>
                r.cfg_sel_ledex := '1';
                r.cfg_wr_en     := '1';
                r.cfg_addr      := cr.cfg_addr+1;
                case cr.cfg_addr is
                    when "0000" =>  r.cfg_data  := HOR_LED_CNT;
                    when "0001" =>  r.cfg_data  := HOR_LED_WIDTH;
                    when "0010" =>  r.cfg_data  := HOR_LED_HEIGHT;
                    when "0011" =>  r.cfg_data  := HOR_LED_STEP;
                    when "0100" =>  r.cfg_data  := HOR_LED_PAD;
                    when "0101" =>  r.cfg_data  := HOR_LED_OFFS;
                    when "0110" =>  r.cfg_data  := VER_LED_CNT;
                    when "0111" =>  r.cfg_data  := VER_LED_WIDTH;
                    when "1000" =>  r.cfg_data  := VER_LED_HEIGHT;
                    when "1001" =>  r.cfg_data  := VER_LED_STEP;
                    when "1010" =>  r.cfg_data  := VER_LED_PAD;
                    when "1011" =>  r.cfg_data  := VER_LED_OFFS;
                    when "1100" =>  r.cfg_data  := "00000" & FRAME_WIDTH(10 downto 8);
                    when "1101" =>  r.cfg_data  := FRAME_WIDTH(7 downto 0);
                    when "1110" =>  r.cfg_data  := "00000" & FRAME_HEIGHT(10 downto 8);
                    when others =>  r.cfg_data  := FRAME_HEIGHT(7 downto 0);
                                    r.state     := WAIT_FOR_START;
                end case;
            
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
