----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    13:59:28 09/22/2016
-- Design Name:    BLACK_BORDER_DETECTOR
-- Module Name:    BLACK_BORDER_DETECTOR - rtl
-- Tool versions:  Xilinx ISE 14.7
-- Description:
--  
-- Additional Comments:
--   
--   These configuration registers can only be set while RST is high, using the CFG_* inputs:
--   
--    [0] = ENABLE              : 0=disables black border detection; 1=enables it
--    [1] = THRESHOLD           : if all channels are below this value, this pixel is considered black
--    [2] = CONSISTENT_FRAMES   : number of frames to occur in a row, for the border detection to trigger
--    [3] = INCONSISTENT_FRAMES : number of frames to occur in a row, for the border detection to reset
--    [4] = REMOVE_BIAS         : number of pixels to also remove from a frame, additional to the border
--    [5] = SCAN_WIDTH_H        : pixels to scan in horizontal direction
--    [6] = SCAN_WIDTH_L
--    [7] = SCAN_HEIGHT_H       : pixels to scan in vertical direction
--    [8] = SCAN_HEIGHT_L
--    [9] = FRAME_WIDTH_H       : frame width in pixels
--   [10] = FRAME_WIDTH_L
--   [11] = FRAME_HEIGHT_H      : frame height in pixels
--   [12] = FRAME_HEIGHT_L
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity BLACK_BORDER_DETECTOR is
    generic (
        R_BITS      : positive range 5 to 12;
        G_BITS      : positive range 6 to 12;
        B_BITS      : positive range 5 to 12;
        DIM_BITS    : positive range 9 to 16
    );
    port (
        CLK : std_ulogic;
        RST : std_ulogic;
        
        CFG_CLK     : in std_ulogic;
        CFG_ADDR    : in std_ulogic_vector(3 downto 0);
        CFG_WR_EN   : in std_ulogic;
        CFG_DATA    : in std_ulogic_vector(7 downto 0);
        
        FRAME_VSYNC     : in std_ulogic;
        FRAME_HSYNC     : in std_ulogic;
        FRAME_RGB_WR_EN : in std_ulogic;
        FRAME_RGB       : in std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        
        BORDER_VALID    : out std_ulogic := '0';
        HOR_BORDER_SIZE : out std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
        VER_BORDER_SIZE : out std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0')
    );
end BLACK_BORDER_DETECTOR;

architecture rtl of BLACK_BORDER_DETECTOR is
    
    constant RGB_BITS   : positive := R_BITS+G_BITS+B_BITS;
    constant HOR        : natural := 0;
    constant VER        : natural := 1;
    
    type state_type is (
        WAITING_FOR_BORDER_SIZES,
        COMPARING_BORDER_SIZES,
        INCREMENTING_CONSISTENT_COUNTER,
        INCREMENTING_INCONSISTENT_COUNTER
    );
    
    type borders_size_type is
        array(0 to 1) of
        std_ulogic_vector(DIM_BITS-1 downto 0);
    
    type reg_type is record
        state                   : state_type;
        consistent_counter      : natural range 0 to 255;
        inconsistent_counter    : natural range 0 to 255;
        got_border_sizes        : std_ulogic_vector(0 to 1);
        border_sizes            : borders_size_type;
        current_border_sizes    : borders_size_type;
        border_valid            : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state                   => WAITING_FOR_BORDER_SIZES,
        consistent_counter      => 0,
        inconsistent_counter    => 0,
        got_border_sizes        => "00",
        border_sizes            => (others => (others => '0')),
        current_border_sizes    => (others => (others => '0')),
        border_valid            => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal frame_x              : unsigned(DIM_BITS-1 downto 0) := (others => '1');
    signal frame_y              : unsigned(DIM_BITS-1 downto 0) := (others => '0');
    signal frame_valid_line     : boolean := false;
    signal frame_vsync_q        : std_ulogic := '1';
    
    signal is_black : std_ulogic := '0';
    
    signal borders_valid    : std_ulogic_vector(0 to 1) := "00";
    signal borders_size     : borders_size_type := (others => (others => '0'));
    
    -- configuration registers
    signal enable               : std_ulogic := '0';
    signal threshold            : std_ulogic_vector(7 downto 0) := x"00";
    signal consistent_frames    : std_ulogic_vector(7 downto 0) := x"00";
    signal inconsistent_frames  : std_ulogic_vector(7 downto 0) := x"00";
    
begin
    
    BORDER_VALID    <= cur_reg.border_valid;
    HOR_BORDER_SIZE <= cur_reg.current_border_sizes(HOR);
    VER_BORDER_SIZE <= cur_reg.current_border_sizes(VER);
    
    is_black    <= '1' when
            FRAME_RGB(     RGB_BITS-1 downto G_BITS+B_BITS) < threshold and
            FRAME_RGB(G_BITS+B_BITS-1 downto        B_BITS) < threshold and
            FRAME_RGB(       B_BITS-1 downto             0) < threshold
        else '0';
    
    cfg_proc : process(CFG_CLK)
    begin
        if rising_edge(CFG_CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "0000" => enable               <= CFG_DATA(0);
                    when "0001" => threshold            <= CFG_DATA;
                    when "0010" => consistent_frames    <= CFG_DATA;
                    when "0011" => inconsistent_frames  <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    pixel_cnt_proc : process(RST, CLK)
    begin
        if RST='1' then
            frame_x             <= (others => '1');
            frame_y             <= (others => '0');
            frame_vsync_q       <= '1';
            frame_valid_line    <= false;
        elsif rising_edge(CLK) then
            frame_vsync_q   <= FRAME_VSYNC;
            
            if FRAME_RGB_WR_EN='1' then
                frame_x             <= frame_x+1;
                frame_valid_line    <= true;
            end if;
            
            if FRAME_HSYNC='1' then
                frame_x             <= (others => '1');
                frame_valid_line    <= false;
                if frame_valid_line then
                    frame_y <= frame_y+1;
                end if;
            end if;
            
            if FRAME_VSYNC='1' then
                frame_x <= (others => '1');
                frame_y <= (others => '0');
            end if;
        end if;
    end process;
    
    HOR_DETECTOR_inst : entity work.HOR_DETECTOR
        generic map (
            R_BITS      => R_BITS,
            G_BITS      => G_BITS,
            B_BITS      => B_BITS,
            DIM_BITS    => DIM_BITS
        )
        port map (
            RST => RST,
            CLK => CLK,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            FRAME_VSYNC     => frame_vsync_q,
            FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
            
            FRAME_X => stdulv(frame_x),
            FRAME_Y => stdulv(frame_y),
            
            IS_BLACK    => is_black,
            
            BORDER_VALID    => borders_valid(HOR),
            BORDER_SIZE     => borders_size(HOR)
        );
    
    VER_DETECTOR_inst : entity work.VER_DETECTOR
        generic map (
            R_BITS      => R_BITS,
            G_BITS      => G_BITS,
            B_BITS      => B_BITS,
            DIM_BITS    => DIM_BITS
        )
        port map (
            RST => RST,
            CLK => CLK,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            FRAME_VSYNC     => FRAME_VSYNC,
            FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
            
            FRAME_X => stdulv(frame_x),
            FRAME_Y => stdulv(frame_y),
            
            IS_BLACK    => is_black,
            
            BORDER_VALID    => borders_valid(VER),
            BORDER_SIZE     => borders_size(VER)
        );
    
    stm_proc : process(RST, cur_reg, enable, borders_valid,
        borders_size, consistent_frames, inconsistent_frames)
        alias cr    : reg_type is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cur_reg;
        
        case cur_reg.state is
            
            when WAITING_FOR_BORDER_SIZES =>
                r.got_border_sizes  := cr.got_border_sizes or borders_valid;
                
                for dim in HOR to VER loop
                    if borders_valid(dim)='1' then
                        r.border_sizes(dim) := borders_size(dim);
                    end if;
                end loop;
                
                if cr.got_border_sizes="11" then
                    r.state := COMPARING_BORDER_SIZES;
                end if;
            
            when COMPARING_BORDER_SIZES =>
                r.got_border_sizes  := "00";
                
                if cr.border_sizes=cr.current_border_sizes then
                    r.state := INCREMENTING_CONSISTENT_COUNTER;
                else
                    r.state := INCREMENTING_INCONSISTENT_COUNTER;
                end if;
            
            when INCREMENTING_CONSISTENT_COUNTER =>
                r.consistent_counter    := cr.consistent_counter+1;
                r.inconsistent_counter  := 0;
                r.state                 := WAITING_FOR_BORDER_SIZES;
                
                if cr.consistent_counter=consistent_frames-1 then
                    -- the current border sizes are stable enough
                    r.border_valid  := '1';
                end if;
            
            when INCREMENTING_INCONSISTENT_COUNTER =>
                r.consistent_counter    := 0;
                r.inconsistent_counter  := cr.inconsistent_counter+1;
                r.state                 := WAITING_FOR_BORDER_SIZES;
                
                if cr.inconsistent_counter=inconsistent_frames-1 then
                    -- the current border sizes are not valid anymore,
                    -- wait until the new ones are
                    r.border_valid          := '0';
                    r.current_border_sizes  := cr.border_sizes;
                end if;
            
        end case;
        
        if RST='1' or enable='0' then
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
