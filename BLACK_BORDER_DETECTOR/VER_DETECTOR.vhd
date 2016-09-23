----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    16:49:14 09/22/2016
-- Design Name:    BLACK_BORDER_DETECTOR
-- Module Name:    VER_DETECTOR - rtl
-- Tool versions:  Xilinx ISE 14.7
-- Description:
--  
-- Additional Comments:
--   
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity VER_DETECTOR is
    generic (
        R_BITS  : positive range 5 to 12;
        G_BITS  : positive range 6 to 12;
        B_BITS  : positive range 5 to 12
    );
    port (
        CLK : std_ulogic;
        RST : std_ulogic;
        
        CFG_ADDR    : in std_ulogic_vector(3 downto 0);
        CFG_WR_EN   : in std_ulogic;
        CFG_DATA    : in std_ulogic_vector(7 downto 0);
        
        FRAME_VSYNC     : in std_ulogic;
        FRAME_RGB_WR_EN : in std_ulogic;
        FRAME_RGB       : in std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        
        FRAME_X : in std_ulogic_vector(15 downto 0);
        FRAME_Y : in std_ulogic_vector(15 downto 0);
        
        BORDER_VALID    : out std_ulogic := '0';
        BORDER_SIZE     : out std_ulogic_vector(15 downto 0) := x"0000";
    );
end VER_DETECTOR;

architecture rtl of VER_DETECTOR is
    
    type state_type is (
        SCANNING_TOP,
        WAITING_FOR_BOTTOM_SCAN,
        SCANNING_BOTTOM,
        WAITING_FOR_FRAME_END
    );
    
    type reg_type is record
        state           : state_type;
        border_valid    : std_ulogic;
        border_size     : unsigned(15 downto 0);´
        found_non_black : boolean;
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => SCANNING_TOP,
        border_valid    => '0',
        border_size     => x"0000",
        found_non_black => false
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    -- configuration registers
    signal threshold    : std_ulogic_vector(7 downto 0) := x"00";
    signal scan_height  : std_ulogic_vector(15 downto 0) := x"0000";
    signal frame_height : std_ulogic_vector(15 downto 0) := x"0000";
    
    function is_black(
        pixel       : std_ulogic_vector(RGB_BITS-1 downto 0),
        threshold   : std_ulogic_vector(7 downto 0)
    ) return boolean is
    begin
        return
            pixel(     RGB_BITS-1 downto G_BITS+B_BITS) < threshold and
            pixel(G_BITS+B_BITS-1 downto        B_BITS) < threshold and
            pixel(       B_BITS-1 downto             0) < threshold;
    end function;
    
begin
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "0001" => threshold                    <= CFG_DATA;
                    when "0111" => scan_height (15 downto 8)    <= CFG_DATA;
                    when "1000" => scan_height ( 7 downto 0)    <= CFG_DATA;
                    when "1011" => frame_height(15 downto 8)    <= CFG_DATA;
                    when "1100" => frame_height( 7 downto 0)    <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_VSYNC, FRAME_RGB_WR_EN, FRAME_X, FRAME_Y, threshold)
        alias cr    : reg_type is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cur_reg;
        
        case cur_reg.state is
            
            when SCANNING_TOP =>
                r.border_size   := uns(FRAME_Y)+1;
                
                if FRAME_RGB_WR_EN='1' then
                    if not is_black(FRAME_RGB, threshold) then
                        r.found_non_black   := true;
                        r.state             := WAITING_FOR_BOTTOM_SCAN;
                    end if;
                end if;
            
            when WAITING_FOR_BOTTOM_SCAN =>
                
            
            when SCANNING_BOTTOM =>
                
            
            when WAITING_FOR_FRAME_END =>
                null;
            
        end case;
        
        if RST='1' or FRAME_VSYNC='1' then
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