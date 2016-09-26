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
        R_BITS      : positive range 5 to 12;
        G_BITS      : positive range 6 to 12;
        B_BITS      : positive range 5 to 12;
        DIM_BITS    : positive range 9 to 16
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
        
        FRAME_X : in std_ulogic_vector(DIM_BITS-1 downto 0);
        FRAME_Y : in std_ulogic_vector(DIM_BITS-1 downto 0);
        
        BORDER_VALID    : out std_ulogic := '0';
        BORDER_SIZE     : out std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0')
    );
end VER_DETECTOR;

architecture rtl of VER_DETECTOR is
    
    constant RGB_BITS   : natural := R_BITS+G_BITS+B_BITS;
    
    type state_type is (
        SCANNING_TOP,
        WAITING_FOR_BOTTOM_SCAN,
        SCANNING_BOTTOM,
        COMPARING_BORDER_SIZES
    );
    
    type columnflags_type is
        array(0 to 2) of
        boolean;
    
    type reg_type is record
        state           : state_type;
        border_valid    : std_ulogic;
        border_size     : unsigned(DIM_BITS-1 downto 0);
        got_non_black   : columnflags_type;
        buf_wr_en       : std_ulogic;
        buf_rd_p        : natural range 0 to 2;
        buf_wr_p        : natural range 0 to 2;
        buf_di          : std_ulogic_vector(DIM_BITS-1 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => SCANNING_TOP,
        border_valid    => '0',
        border_size     => (others => '0'),
        got_non_black   => (others => false),
        buf_wr_en       => '0',
        buf_rd_p        => 0,
        buf_wr_p        => 0,
        buf_di          => (others => '0')
    );
    
    type buf_type           is array(0 to 2) of std_ulogic_vector(DIM_BITS-1 downto 0);
    type scancolumns_type   is array(0 to 2) of std_ulogic_vector(DIM_BITS-1 downto 0);
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal right_scan_start     : unsigned(DIM_BITS-1 downto 0) := (others => '0');
    
    signal qu_frame_width       : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal half_frame_width     : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal three_qu_frame_width : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal scancolumns          : scancolumns_type := (others => (others => '0'));
    signal scancolumn           : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    signal buf      : buf_type := (others => (others => '0'));
    signal buf_do   : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    -- configuration registers
    signal threshold    : std_ulogic_vector(7 downto 0) := x"00";
    signal scan_height  : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal frame_width  : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal frame_height : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    function is_black(
        pixel       : std_ulogic_vector(RGB_BITS-1 downto 0);
        threshold   : std_ulogic_vector
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
    
    qu_frame_width          <= "00" & frame_width(DIM_BITS-1 downto 2);
    half_frame_width        <= "0" & frame_width(DIM_BITS-1 downto 1);
    three_qu_frame_width    <= half_frame_width+qu_frame_width;
    
    scancolumns(0)  <= qu_frame_width;
    scancolumns(1)  <= half_frame_width;
    scancolumns(2)  <= three_qu_frame_width;
    scancolumn      <= scancolumns(cur_reg.buf_rd_p);
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "0001" => threshold                            <= CFG_DATA;
                    when "0111" => scan_height (DIM_BITS-1 downto 8)    <= CFG_DATA(DIM_BITS-9 downto 0);
                    when "1000" => scan_height (         7 downto 0)    <= CFG_DATA;
                    when "1001" => frame_width (DIM_BITS-1 downto 8)    <= CFG_DATA(DIM_BITS-9 downto 0);
                    when "1010" => frame_width (         7 downto 0)    <= CFG_DATA;
                    when "1011" => frame_height(DIM_BITS-1 downto 8)    <= CFG_DATA(DIM_BITS-9 downto 0);
                    when "1100" => frame_height(         7 downto 0)    <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    buf_proc : process(CLK)
        alias wr_en is next_reg.buf_wr_en;
        alias rd_p  is next_reg.buf_rd_p;
        alias wr_p  is next_reg.buf_wr_p;
        alias di    is next_reg.buf_di;
        alias do    is buf_do;
    begin
        if rising_edge(CLK) then
            do  <= buf(rd_p);
            
            if wr_en='1' then
                buf(wr_p)   <= di;
                
                if wr_p=rd_p then
                    do  <= di;
                end if;
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_VSYNC, FRAME_RGB_WR_EN, FRAME_RGB,
        FRAME_X, FRAME_Y, threshold, frame_height, scan_height, scancolumn, buf_do)
        alias cr    is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cur_reg;
        
        r.border_valid  := '0';
        r.buf_wr_en     := '0';
        
        case cur_reg.state is
            
            when SCANNING_TOP =>
                r.border_size   := uns(scan_height);
                r.buf_wr_p      := cr.buf_rd_p;
                r.buf_di        := FRAME_Y+1;
                
                if FRAME_RGB_WR_EN='1' then
                    
                    if FRAME_X=scancolumn-1 then
                    
                        if not is_black(FRAME_RGB, threshold) then
                            r.got_non_black(cr.buf_rd_p)    := true;
                        elsif not cr.got_non_black(cr.buf_rd_p) then
                            r.buf_wr_en := '1';
                        end if;
                        
                        r.buf_rd_p  := cr.buf_rd_p+1;
                        if cr.buf_rd_p=2 then
                            r.buf_rd_p  := 0;
                        end if;
                        
                    end if;
                    
                    if FRAME_Y=scan_height then
                        r.state := WAITING_FOR_BOTTOM_SCAN;
                    end if;
                    
                end if;
            
            when WAITING_FOR_BOTTOM_SCAN =>
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_Y=frame_height-scan_height-1
                then
                    r.state := SCANNING_BOTTOM;
                end if;
            
            when SCANNING_BOTTOM =>
                r.buf_wr_p  := cr.buf_rd_p;
                r.buf_di    := frame_height-FRAME_Y-1;
                
                if FRAME_RGB_WR_EN='1' then
                    
                    if FRAME_X=scancolumn-1 then
                        
                        if not is_black(FRAME_RGB, threshold) then
                        
                            r.got_non_black(cr.buf_rd_p)    := true;
                        
                            if
                                not cr.got_non_black(cr.buf_rd_p) or
                                frame_height-FRAME_X-1<buf_do
                            then
                                r.buf_wr_en := '1';
                            end if;
                            
                        end if;
                        
                        r.buf_rd_p  := cr.buf_rd_p+1;
                        if cr.buf_rd_p=2 then
                            r.buf_rd_p  := 0;
                            
                            if FRAME_Y=frame_height-1 then
                                r.state := COMPARING_BORDER_SIZES;
                            end if;
                        end if;
                        
                    end if;
                    
                end if;
            
            when COMPARING_BORDER_SIZES =>
                r.buf_rd_p  := cr.buf_rd_p+1;
                
                -- search the smallest border of the three scancolumns
                if buf_do<cr.border_size then
                    r.border_size   := uns(buf_do);
                end if;
                
                if cr.buf_rd_p=2 then
                    r.buf_rd_p      := 0;
                    r.border_valid  := '1';
                    r.state         := SCANNING_TOP;
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
