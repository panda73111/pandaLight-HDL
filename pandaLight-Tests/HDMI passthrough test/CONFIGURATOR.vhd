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

entity CONFIGURATOR is
    generic (
        -- dummy values
        HOR_LED_CNT     : natural := 16;
        HOR_LED_WIDTH   : natural := 60;
        HOR_LED_HEIGHT  : natural := 80;
        HOR_LED_STEP    : natural := 80;
        HOR_LED_PAD     : natural := 5;
        HOR_LED_OFFS    : natural := 10;
        VER_LED_CNT     : natural := 9;
        VER_LED_WIDTH   : natural := 80;
        VER_LED_HEIGHT  : natural := 60;
        VER_LED_STEP    : natural := 80;
        VER_LED_PAD     : natural := 5;
        VER_LED_OFFS    : natural := 10
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        RECONFIGURE : in std_ulogic;
        
        FRAME_WIDTH     : in std_ulogic_vector(10 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(10 downto 0);
        
        CFG_SEL_LEDEX   : out std_ulogic;
        
        CFG_ADDR    : out std_ulogic_vector(3 downto 0);
        CFG_WR_EN   : out std_ulogic;
        CFG_DATA    : out std_ulogic_vector(7 downto 0)
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
        cfg_sel_ledex   => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
begin
    
    CFG_SEL_LEDEX   <= cur_reg.cfg_sel_ledex;
    
    stm_proc : process(RST, cur_reg, RECONFIGURE, FRAME_WIDTH, FRAME_HEIGHT)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cr;
        
        case cr.state is
            
            when WAIT_FOR_START =>
                if RECONFIGURE='1' then
                    r.state := CONFIGURE_LEDEX;
                end if;
            
            when CONFIGURE_LEDEX =>
                r.cfg_sel_ledex <= '1';
                
            
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
