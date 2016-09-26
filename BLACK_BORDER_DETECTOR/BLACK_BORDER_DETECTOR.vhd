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
--    [0] = ENABLE            : 0=disables black border detection; 1=enables it
--    [1] = THRESHOLD         : if all channels are below this value, this pixel is considered black
--    [2] = BORDERED_FRAMES   : number of frames to occur in a row, for the border detection to trigger
--    [3] = UNBORDERED_FRAMES : number of frames to occur in a row, for the border detection to reset
--    [4] = REMOVE_BIAS       : number of pixels to also remove from a frame, additional to the border
--    [5] = SCAN_WIDTH_H      : pixels to scan in horizontal direction
--    [6] = SCAN_WIDTH_L
--    [7] = SCAN_HEIGHT_H     : pixels to scan in vertical direction
--    [8] = SCAN_HEIGHT_L
--    [9] = FRAME_WIDTH_H     : frame width in pixels
--   [10] = FRAME_WIDTH_L
--   [11] = FRAME_HEIGHT_H    : frame height in pixels
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
        
        CFG_ADDR    : in std_ulogic_vector(3 downto 0);
        CFG_WR_EN   : in std_ulogic;
        CFG_DATA    : in std_ulogic_vector(7 downto 0);
        
        FRAME_VSYNC     : in std_ulogic;
        FRAME_RGB_WR_EN : in std_ulogic;
        FRAME_RGB       : in std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        
        BORDER_VALID    : out std_ulogic := '0';
        HOR_BORDER_SIZE : out std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
        VER_BORDER_SIZE : out std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0')
    );
end BLACK_BORDER_DETECTOR;

architecture rtl of BLACK_BORDER_DETECTOR is
    
    constant RGB_BITS   : natural := R_BITS+G_BITS+B_BITS;
    constant HOR        : std_ulogic := '0'
    
    type state_type is (
        WAITING_FOR_ENABLE,
        WAITING_FOR_FRAME_START
    );
    
    type reg_type is record
        state                       : state_type;
        bordered_frame_counter      : unsigned(8 downto 0);
        unbordered_frame_counter    : unsigned(8 downto 0);
        border_width                : unsigned(DIM_BITS-1 downto 0);
        border_height               : unsigned(DIM_BITS-1 downto 0);
        border_type                 : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state                       => WAITING_FOR_ENABLE,
        bordered_frame_counter      => (others => '0'),
        unbordered_frame_counter    => (others => '0'),
        border_width                => (others => '0'),
        border_height               => (others => '0'),
        border_type                 => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal frame_x, frame_y     : unsigned(15 downto 0) := (others => '0');
    
    -- configuration registers
    signal enable               : std_ulogic;
    signal threshold            : std_ulogic_vector(7 downto 0) := x"00";
    signal bordered_frames      : std_ulogic_vector(7 downto 0) := x"00";
    signal unbordered_frames    : std_ulogic_vector(7 downto 0) := x"00";
    signal remove_bias          : std_ulogic_vector(7 downto 0) := x"00";
    signal scan_width           : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal scan_height          : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal frame_width          : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal frame_height         : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
begin
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "0000" => enable                               <= CFG_DATA(0);
                    when "0001" => threshold                            <= CFG_DATA;
                    when "0010" => bordered_frames                      <= CFG_DATA;
                    when "0011" => unbordered_frames                    <= CFG_DATA;
                    when "0100" => remove_bias                          <= CFG_DATA;
                    when "0101" => scan_width  (DIM_BITS-1 downto 8)    <= CFG_DATA(DIM_BITS-9 downto 0);
                    when "0110" => scan_width  (         7 downto 0)    <= CFG_DATA;
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
    
    pixel_cnt_proc : process(RST, CLK)
    begin
        if RST='1' then
            frame_x <= (others => '0');
            frame_y <= (others => '0');
        elsif rising_edge(CLK) then
            if FRAME_VSYNC='1' then
                frame_x <= (others => '0');
                frame_y <= (others => '0');
            end if;
            if FRAME_RGB_WR_EN='1' then
                frame_x <= frame_x+1;
                if frame_x=frame_width-1 then
                    frame_x <= (others => '0');
                    frame_y <= frame_y+1;
                end if;
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, enable, FRAME_VSYNC, FRAME_RGB_WR_EN)
        alias cr    : reg_type is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cur_reg;
        
        case cur_reg.state is
            
            when WAITING_FOR_FRAME_START =>
                if FRAME_VSYNC='0' then
                    r.state := COUNTING
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
