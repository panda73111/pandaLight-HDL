----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    20:27:16 12/07/2014 
-- Module Name:    VIDEO_ANALYZER - rtl 
-- Project Name:   VIDEO_ANALYZER
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--  polarities: '0' = positive, low during active pixels
--              '1' = negative, high during active pixels
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity VIDEO_ANALYZER is
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        START       : in std_ulogic;
        VSYNC       : in std_ulogic;
        HSYNC       : in std_ulogic;
        RGB_VALID   : in std_ulogic;
        
        POSITIVE_VSYNC  : out std_ulogic := '0';
        POSITIVE_HSYNC  : out std_ulogic := '0';
        WIDTH           : out std_ulogic_vector(10 downto 0) := (others => '0');
        HEIGHT          : out std_ulogic_vector(10 downto 0) := (others => '0');
        VALID           : out std_ulogic := '0'
    );
end VIDEO_ANALYZER;

architecture rtl of VIDEO_ANALYZER is
    
    type state_type is (
        WAIT_FOR_START,
        WAIT_FOR_RGB_VALID,
        WAIT_FOR_FRAME_END,
        WAIT_FOR_FRAME_BEGINNING,
        WAIT_FOR_FIRST_LINE_BEGINNING,
        COUNT_PIXELS_IN_LINE,
        INCREMENT_HEIGHT,
        WAIT_FOR_LINE_END,
        WAIT_FOR_LINE_BEGINNING,
        REVALIDATE,
        FINISHED
    );
    
    type reg_type is record
        state       : state_type;
        vsync_pol   : std_ulogic;
        hsync_pol   : std_ulogic;
        tmp_width   : unsigned(10 downto 0);
        tmp_height  : unsigned(10 downto 0);
        width       : unsigned(10 downto 0);
        height      : unsigned(10 downto 0);
        valid       : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAIT_FOR_START,
        vsync_pol   => '0',
        hsync_pol   => '0',
        tmp_width   => (others => '0'),
        tmp_height  => (others => '0'),
        width       => (others => '0'),
        height      => (others => '0'),
        valid       => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal pos_vsync    : std_ulogic := '0';
    signal pos_hsync    : std_ulogic := '0';
    
begin
    
    POSITIVE_VSYNC  <= pos_vsync;
    POSITIVE_HSYNC  <= pos_hsync;
    WIDTH           <= stdulv(cur_reg.width);
    HEIGHT          <= stdulv(cur_reg.height);
    VALID           <= cur_reg.valid;
    
    pos_vsync   <= VSYNC xor cur_reg.vsync_pol;
    pos_hsync   <= HSYNC xor cur_reg.hsync_pol;
    
    stm_proc : process(RST, cur_reg, START, VSYNC, HSYNC, RGB_VALID, pos_vsync)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cr;
        
        case cr.state is
            
            when WAIT_FOR_START =>
                if START='1' then
                    r.state := WAIT_FOR_RGB_VALID;
                end if;
            
            when WAIT_FOR_RGB_VALID =>
                r.tmp_width     := (others => '0');
                r.tmp_height    := (others => '0');
                if RGB_VALID='1' then
                    r.vsync_pol := VSYNC;
                    r.hsync_pol := HSYNC;
                    r.state     := WAIT_FOR_FRAME_END;
                end if;
            
            when WAIT_FOR_FRAME_END =>
                if pos_vsync='1' then
                    r.state := WAIT_FOR_FRAME_BEGINNING;
                end if;
            
            when WAIT_FOR_FRAME_BEGINNING =>
                if pos_vsync='0' then
                    -- falling edge of positive VSYNC
                    r.state := WAIT_FOR_FIRST_LINE_BEGINNING;
                end if;
            
            when WAIT_FOR_FIRST_LINE_BEGINNING =>
                if RGB_VALID='1' then
                    r.state := COUNT_PIXELS_IN_LINE;
                end if;
            
            when COUNT_PIXELS_IN_LINE =>
                r.tmp_width := cr.tmp_width+1;
                if RGB_VALID='0' then
                    -- falling edge of RGB_VALID
                    r.state := INCREMENT_HEIGHT;
                end if;
            
            when INCREMENT_HEIGHT =>
                r.tmp_height    := cr.tmp_height+1;
                r.state         := WAIT_FOR_LINE_END;
            
            when WAIT_FOR_LINE_END =>
                if RGB_VALID='0' then
                    -- falling edge of RGB_VALID
                    r.state := WAIT_FOR_LINE_BEGINNING;
                end if;
            
            when WAIT_FOR_LINE_BEGINNING =>
                if RGB_VALID='1' then
                    -- rising edge of RGB_VALID
                    r.state := INCREMENT_HEIGHT;
                end if;
                if pos_vsync='1' then
                    -- rising edge of positive VSYNC
                    r.state := FINISHED;
                    if cr.valid='1' then
                        r.state := REVALIDATE;
                    end if;
                end if;
            
            when FINISHED =>
                r.width     := cr.tmp_width;
                r.height    := cr.tmp_height;
                r.valid     := '1';
                r.state     := WAIT_FOR_RGB_VALID;
            
            when REVALIDATE =>
                if
                    cr.tmp_width/=cr.width or
                    cr.tmp_height/=cr.height
                then
                    -- try again next frame
                    r.valid := '0';
                end if;
                r.state := WAIT_FOR_RGB_VALID;
            
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

