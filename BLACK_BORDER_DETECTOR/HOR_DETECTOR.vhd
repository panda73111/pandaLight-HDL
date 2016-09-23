----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    16:48:52 09/22/2016
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

entity HOR_DETECTOR is
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
end HOR_DETECTOR;

architecture rtl of HOR_DETECTOR is
    
    type state_type is (
        WAITING_FOR_SCANLINE,
        SCANNING_LEFT,
        WAITING_FOR_RIGHT_SCAN,
        SCANNING_RIGHT,
        SWITCHING_LINE,
        COMPARING_BORDER_SIZES
    );
    
    type reg_type is record
        state           : state_type;
        border_valid    : std_ulogic;
        border_size     : unsigned(15 downto 0);
        buf_wr_en       : std_ulogic;
        buf_p           : natural range 0 to 2;
        buf_di          : std_ulogic_vector(15 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => WAITING_FOR_SCANLINE,
        border_valid    => '0',
        border_size     => x"0000",
        buf_wr_en       => '0',
        buf_p           => 0,
        buf_di          => x"0000"
    );
    
    type buf_type       is array(0 to 2) of std_ulogic_vector(15 downto 0);
    type scanlines_type is array(0 to 2) of std_ulogic_vector(15 downto 0);
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal right_scan_start     : unsigned(15 downto 0) := (others => '0');
    
    signal qu_frame_height          : std_ulogic_vector(15 downto 0) := x"0000";
    signal half_frame_height        : std_ulogic_vector(15 downto 0) := x"0000";
    signal three_qu_frame_height    : std_ulogic_vector(15 downto 0) := x"0000";
    signal scanlines                : scanlines_type := (others => x"0000");
    signal scanline                 : std_ulogic_vector(15 downto 0) := x"0000";
    
    signal buf      : buf_type := (others => x"0000");
    signal buf_do   : std_ulogic_vector(15 downto 0) := x"0000";
    
    -- configuration registers
    signal threshold    : std_ulogic_vector(7 downto 0) := x"00";
    signal scan_width   : std_ulogic_vector(15 downto 0) := x"0000";
    signal frame_width  : std_ulogic_vector(15 downto 0) := x"0000";
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
    
    BORDER_VALID    <= cur_reg.border_valid;
    BORDER_SIZE     <= stdulv(cur_reg.border_size);
    
    qu_frame_height         <= "00" & frame_height(15 downto 2);
    half_frame_height       <= "0" & frame_height(15 downto 1);
    three_qu_frame_height   <= half_frame_height+qu_frame_height;
    
    scanlines(0)        <= qu_frame_height;
    scanlines(1)        <= half_frame_height;
    scanlines(2)        <= three_qu_frame_height;
    scanline            <= scanlines(cur_reg.buf_p);
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "0001" => threshold                    <= CFG_DATA;
                    when "0101" => scan_width  (15 downto 8)    <= CFG_DATA;
                    when "0110" => scan_width  ( 7 downto 0)    <= CFG_DATA;
                    when "1001" => frame_width (15 downto 8)    <= CFG_DATA;
                    when "1010" => frame_width ( 7 downto 0)    <= CFG_DATA;
                    when "1011" => frame_height(15 downto 8)    <= CFG_DATA;
                    when "1100" => frame_height( 7 downto 0)    <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    buf_proc : process(CLK)
        alias wr_en is next_reg.buf_wr_en;
        alias p     is next_reg.buf_p;
        alias di    is next_reg.buf_di;
        alias do    is buf_do;
    begin
        if rising_edge(CLK) then
            if wr_en='1' then
                buf(p)  <= di;
                do      <= di;
            else
                do  <= buf(p);
            end if;
        end process;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_VSYNC, FRAME_RGB_WR_EN, FRAME_RGB,
        FRAME_X, FRAME_Y, threshold, frame_width, scan_width, scanline, buf_do)
        alias cr    is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cur_reg;
        
        r.border_valid  := '0';
        r.buf_wr_en     := '0';
        
        case cur_reg.state is
            
            when WAITING_FOR_SCANLINE =>
                r.border_size   := scan_width;
                
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=frame_width-1 and
                    FRAME_Y=scanline-1
                then
                    r.state := SCANNING_LEFT;
                end if;
            
            when SCANNING_LEFT =>
                r.buf_di    := FRAME_X+1;
                
                if FRAME_RGB_WR_EN='1' then
                    r.buf_wr_en := '1';
                    
                    if
                        FRAME_X=scan_width-1 or
                        not is_black(FRAME_RGB, threshold)
                    then
                        r.state := WAITING_FOR_RIGHT_SCAN;
                    end if;
                end if;
            
            when WAITING_FOR_RIGHT_SCAN =>
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=frame_width-buf_do-1
                then
                    r.state := SCANNING_RIGHT;
                end if;
            
            when SCANNING_RIGHT =>
                r.buf_di    := frame_width-FRAME_X-1;
                
                if FRAME_RGB_WR_EN='1' then
                    
                    if not is_black(FRAME_RGB, threshold) then
                        -- the right border is smaller than the left one
                        r.buf_wr_en := '1';
                    end if;
                    
                    if FRAME_X=frame_width-1 then
                        r.state := SWITCHING_LINE;
                    end if;
                    
                end if;
            
            when SWITCHING_LINE =>
                r.buf_p := cr.buf_p+1;
                r.state := WAITING_FOR_SCANLINE;
                
                if cr.buf_p=2 then
                    r.buf_p := 0;
                    r.state := COMPARING_BORDER_SIZES;
                end if;
            
            when COMPARING_BORDER_SIZES =>
                r.buf_p := cr.buf_p+1;
                
                -- search the smallest border of the three scanlines
                if buf_do<cr.border_size then
                    r.border_size   := buf_do;
                end if;
                
                if cr.buf_p=2 then
                    r.buf_p         := 0;
                    r.border_valid  := '1';
                    r.state         := WAITING_FOR_SCANLINE;
                end if;
            
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
