----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:30:22 06/29/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    LED_COLOR_EXTRACTOR - rtl
-- Project Name: 
-- Target Devices: 
-- Tool versions: Xilinx ISE 14.7
-- Description:
--   Component that extracts a variable number of averaged pixel groups
--   from an incoming video stream for the purpose of sending these colors
--   to a LED stripe around a TV
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;

library help_funcs;
use help_funcs.all;

entity LED_COLOR_EXTRACTOR is
    generic (
        FRAME_SIZE_BITS : integer := 11;
        LED_CNT_BITS    : integer := 8;
        LED_SIZE_BITS   : integer := 7;
        R_BITS          : integer := 8;
        G_BITS          : integer := 8;
        B_BITS          : integer := 8
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        HOR_LED_CNT     : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        HOR_LED_WIDTH   : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        HOR_LED_HEIGHT  : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        VER_LED_CNT     : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        VER_LED_WIDTH   : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        VER_LED_HEIGHT  : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        
        LED_PAD_TOP_LEFT        : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        LED_PAD_TOP_RIGHT       : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        LED_PAD_RIGHT_TOP       : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        LED_PAD_RIGHT_BOTTOM    : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        LED_PAD_BOTTOM_LEFT     : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        LED_PAD_BOTTOM_RIGHT    : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        LED_PAD_LEFT_TOP        : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        LED_PAD_LEFT_BOTTOM     : in std_ulogic_vector(FRAME_SIZE_BITS/2-1 downto 0);
        
        FRAME_VSYNC : in std_ulogic;
        FRAME_HSYNC : in std_ulogic;
        
        FRAME_WIDTH     : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        
        FRAME_R : in std_ulogic_vector(R_BITS-1 downto 0);
        FRAME_G : in std_ulogic_vector(G_BITS-1 downto 0);
        FRAME_B : in std_ulogic_vector(B_BITS-1 downto 0);
        
        LED_VALID   : out std_ulogic;
        LED_NUM     : out std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        LED_R       : out std_ulogic_vector(R_BITS-1 downto 0);
        LED_G       : out std_ulogic_vector(G_BITS-1 downto 0);
        LED_B       : out std_ulogic_vector(B_BITS-1 downto 0)
    );
end LED_COLOR_EXTRACTOR;

architecture rtl of LED_COLOR_EXTRACTOR is
    
    type pixel_type is record
        R   : std_ulogic_vector(R_BITS-1 downto 0);
        G   : std_ulogic_vector(G_BITS-1 downto 0);
        B   : std_ulogic_vector(B_BITS-1 downto 0);
    end record;
    
    -- the following buffers contain LED colors which are refreshed every
    -- time a new frame pixel comes in;
    -- horizontal RAM: used by the top LED row and the bottom LED row
    type hor_ram_type is array(0 to (2**LED_CNT_BITS)-1) of pixel_type;
    -- vertical RAM: used by the left LED column and the right LED column;
    -- because two LEDs can overlap, two LEDs for the left and two LEDs
    -- for the right column are needed
    type ver_ram_type is array(0 to 3) of pixel_type;
    
    signal hor_ram  : hor_ram_type;
    signal ver_ram  : ver_ram_type;
    
    signal total_top_led_width      : unsigned(LED_CNT_BITS+LED_SIZE_BITS-1 downto 0) := (others => '0');
    signal total_right_led_height   : unsigned(LED_CNT_BITS+LED_SIZE_BITS-1 downto 0) := (others => '0');
    signal total_bottom_led_width   : unsigned(LED_CNT_BITS+LED_SIZE_BITS-1 downto 0) := (others => '0');
    signal total_left_led_height    : unsigned(LED_CNT_BITS+LED_SIZE_BITS-1 downto 0) := (others => '0');
    
    signal frame_x  : unsigned(FRAME_SIZE_BITS-1 downto 0) := (others => '0');
    signal frame_y  : unsigned(FRAME_SIZE_BITS-1 downto 0) := (others => '0');
    
    signal hor_led_num  : unsigned(LED_CNT_BITS-1 downto 0) := (others => '0');
    signal ver_led_num  : unsigned(LED_CNT_BITS-1 downto 0) := (others => '0');
    
begin
    
    -- left border first LED to right border last LED
    total_top_led_width     <= FRAME_WIDTH-LED_PAD_TOP_LEFT-LED_PAD_TOP_RIGHT;
    total_bottom_led_width  <= FRAME_WIDTH-LED_PAD_BOTTOM_LEFT-LED_PAD_BOTTOM_RIGHT;
    -- top border first LED to bottom border last LED
    total_right_led_height  <= FRAME_HEIGHT-LED_PAD_RIGHT_TOP-LED_PAD_RIGHT_BOTTOM;
    total_left_led_height   <= FRAME_HEIGHT-LED_PAD_LEFT_TOP-LED_PAD_LEFT_BOTTOM;
    
    -- next step: calculate the center points of each LED
    -- (hor. center of top/bottom LEDs, ver. center of left/right LEDs)
    -- from which I can 'pad' using the LED width/height to get the first and last
    -- frame x value for hor. LEDs and frame y value for ver. LEDs.
    -- The problem with this approach is that this would need these divisions:
    --   total_top_led_width/HOR_LED_CNT
    --   total_bottom_led_width/HOR_LED_CNT
    --   total_right_led_height/VER_LED_CNT
    --   total_left_led_height/VER_LED_CNT
    -- And hardware divisions are bad and should be avoided.
    -- I need to think about this...
    
    --hor_led_num <= ;
    --ver_led_num <= ;
    
    pixel_cnt_proc : process(RST, CLK)
    begin
        if RST='1' then
            frame_x <= 0;
            frame_y <= 0;
        elsif rising_edge(CLK) then
            if FRAME_VSYNC='0' then
                frame_x <= (others => '0');
                frame_y <= (others => '0');
            end if;
            if FRAME_HSYNC='1' then
                frame_x <= frame_x+1;
                if frame_x=uns(FRAME_WIDTH)-1 then
                    frame_x <= (others => '0');
                    frame_y <= frame_y+1;
                end if;
            end if;
        end if;
    end process;
    
    ver_proc : process(CLK)
        variable first_right_led_x  : unsigned(frame_x'range);
    begin
        if rising_edge(CLK) then
            if FRAME_HSYNC='1' then
                first_right_led_x   := uns(FRAME_WIDTH)-uns(VER_LED_WIDTH)-1;
                if frame_x=0 then
                    -- first pixel of a left border LED
                elsif frame_x<=uns(VER_LED_WIDTH) then
                    -- left border LED
                elsif frame_x=first_right_led_x then
                    -- first pixel of a right border LED
                elsif frame_x>first_right_led_x then
                    -- right border LED
                end if;
            end if;
        end if;
    end process;
    
end rtl;