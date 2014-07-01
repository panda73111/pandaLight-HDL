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

use work.help_funcs.all;

entity LED_COLOR_EXTRACTOR is
    generic (
        FRAME_SIZE_BITS : integer := 11;
        LED_CNT_BITS    : integer := 8;
        LED_SIZE_BITS   : integer := 8;
        LED_PAD_BITS    : integer := 8;
        LED_STEP_BITS   : integer := 8;
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
        
        LED_PAD_TOP_LEFT        : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_TOP_TOP         : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_RIGHT_TOP       : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_RIGHT_RIGHT     : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_BOTTOM_LEFT     : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_BOTTOM_BOTTOM   : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_LEFT_TOP        : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_LEFT_LEFT       : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_STEP_TOP            : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        LED_STEP_RIGHT          : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        LED_STEP_BOTTOM         : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        LED_STEP_LEFT           : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        
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
    
    -----------------------------
    --- array element aliases ---
    -----------------------------
    
    constant T  : natural := 0; -- top
    constant B  : natural := 1; -- bottom
    constant L  : natural := 2; -- right
    constant R  : natural := 3; -- left
    
    constant X  : natural := 0;
    constant Y  : natural := 1;
    
    -------------
    --- types ---
    -------------
    
    type led_color_type is record
        R   : std_ulogic_vector(R_BITS-1 downto 0);
        G   : std_ulogic_vector(G_BITS-1 downto 0);
        B   : std_ulogic_vector(B_BITS-1 downto 0);
    end record;
    
    -- the following buffers contain LED colors which are refreshed every
    -- time a new frame pixel comes in
    
    type led_nums_type is
        array(0 to 3) of
        unsigned(LED_CNT_BITS-1 downto 0);
    
    type inner_coords_type is
        array(0 to 1) of
        unsigned(LED_SIZE_BITS-1 downto 0);
    
    type led_inner_coords_type is
        array(0 to 3) of
        inner_coords_type;
    
    type overlaps_type is
        array(0 to 3) of
        boolean;
    
    type abs_overlaps_type is
        array(0 to 3) of
        unsigned(LED_SIZE_BITS-1 downto 0);
    
    type led_pos_type is
        array(0 to 1) of
        unsigned(FRAME_SIZE_BITS-1 downto 0);
    
    type first_leds_pos_type is
        array(0 to 3) of
        led_pos_type;
    
    ----------------------
    --- default values ---
    ----------------------
    
    constant led_nums_type_def
        : led_nums_type
        := (others => (others => '0'));
    
    constant inner_coords_type_def
        : inner_coords_type
        := (others => (others => '0'));
    
    constant led_inner_coords_type_def
        : led_inner_coords_type
        := (others => inner_coords_type_def);
    
    constant overlaps_type_def
        : overlaps_type
        := (others => false);
    
    constant abs_overlaps_type_def
        : abs_overlaps_type
        := (others => (others => '0'));
    
    constant led_pos_type_def
        : led_pos_type
        := (others => (others => '0'));
    
    constant first_leds_pos_type_def
        : first_leds_pos_type
        := (others => led_pos_type_def);
    
    ---------------
    --- signals ---
    ---------------
    
    signal led_nums
        : led_nums_type
        := led_nums_type_def;
    
    signal leds_inner_coords, next_leds_inner_coords
        : led_inner_coords_type
        := led_inner_coords_type_def;
    
    signal overlaps
        : overlaps_type
        := overlaps_type_def;
    
    signal abs_overlaps
        : abs_overlaps_type
        := abs_overlaps_type_def;
    
    signal first_leds_pos
        : first_leds_pos_type
        := first_leds_pos_type_def;
    
    signal frame_x, frame_y
        : unsigned(FRAME_SIZE_BITS-1 downto 0)
        := (others => '0');
    
    
    -----------------
    --- functions ---
    -----------------
    
    function arithMean(vl, vr : std_ulogic_vector) return std_ulogic_vector is
        constant bits   : integer := max(vl'length, vr'length);
        variable ul, ur : unsigned(bits downto 0);
        variable sum    : std_ulogic_vector(bits downto 0);
    begin
        ul  := resize(uns(vl), bits+1);
        ur  := resize(uns(vr), bits+1);
        sum := stdulv(ul+ur);
        return sum(bits downto 1); -- divide by 2
    end arithMean;
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    overlaps(T) <= LED_STEP_TOP<HOR_LED_WIDTH;
    overlaps(R) <= LED_STEP_RIGHT<VER_LED_HEIGHT;
    overlaps(B) <= LED_STEP_BOTTOM<HOR_LED_WIDTH;
    overlaps(L) <= LED_STEP_LEFT<VER_LED_HEIGHT;
    
    abs_overlaps(T) <= uns(HOR_LED_HEIGHT-LED_STEP_TOP);
    abs_overlaps(R) <= uns(VER_LED_HEIGHT-LED_STEP_RIGHT);
    abs_overlaps(B) <= uns(HOR_LED_HEIGHT-LED_STEP_BOTTOM);
    abs_overlaps(L) <= uns(VER_LED_HEIGHT-LED_STEP_LEFT);
    
    next_leds_inner_coords(T)(X)    <= leds_inner_coords(T)(X)+uns(LED_STEP_TOP);
    next_leds_inner_coords(T)(Y)    <= leds_inner_coords(T)(Y);
    next_leds_inner_coords(R)(X)    <= leds_inner_coords(R)(X);
    next_leds_inner_coords(R)(Y)    <= leds_inner_coords(R)(Y)+uns(LED_STEP_RIGHT);
    next_leds_inner_coords(B)(X)    <= leds_inner_coords(B)(X)+uns(LED_STEP_BOTTOM);
    next_leds_inner_coords(B)(Y)    <= leds_inner_coords(B)(Y);
    next_leds_inner_coords(L)(X)    <= leds_inner_coords(L)(X);
    next_leds_inner_coords(L)(Y)    <= leds_inner_coords(L)(Y)+uns(LED_STEP_LEFT);
    
    first_leds_pos(T)(X)    <= resize(  uns(LED_PAD_TOP_LEFT),      FRAME_SIZE_BITS);
    first_leds_pos(T)(Y)    <= resize(  uns(LED_PAD_TOP_TOP),       FRAME_SIZE_BITS);
    first_leds_pos(R)(X)    <=          uns(FRAME_WIDTH-VER_LED_WIDTH-LED_PAD_RIGHT_RIGHT);
    first_leds_pos(R)(Y)    <= resize(  uns(LED_PAD_RIGHT_TOP),     FRAME_SIZE_BITS);
    first_leds_pos(B)(X)    <= resize(  uns(LED_PAD_BOTTOM_LEFT),   FRAME_SIZE_BITS);
    first_leds_pos(B)(Y)    <=          uns(FRAME_HEIGHT-HOR_LED_HEIGHT-LED_PAD_BOTTOM_BOTTOM);
    first_leds_pos(L)(X)    <= resize(  uns(LED_PAD_LEFT_LEFT),     FRAME_SIZE_BITS);
    first_leds_pos(L)(Y)    <= resize(  uns(LED_PAD_LEFT_TOP),      FRAME_SIZE_BITS);
    
    -----------------
    --- processes ---
    -----------------
    
    pixel_cnt_proc : process(RST, CLK)
    begin
        if RST='1' then
            frame_x <= (others => '0');
            frame_y <= (others => '0');
        elsif rising_edge(CLK) then
            if FRAME_VSYNC='0' then
                frame_x <= (others => '0');
                frame_y <= (others => '0');
            end if;
            if FRAME_HSYNC='1' then
                frame_x <= frame_x+1;
                if frame_x=FRAME_WIDTH-1 then
                    frame_x <= (others => '0');
                    frame_y <= frame_y+1;
                end if;
            end if;
        end if;
    end process;
    
    side_scan_proc_gen : for side in 0 to 3 generate
        constant HOR    : boolean := side=T or side=B;
        constant VER    : boolean := side=L or side=R;
        
        -- horizontal buffer: used by the top LED row and the bottom LED row;
        -- vertical buffer: used by the left LED column and the right LED column,
        -- because two LEDs can overlap, two LEDs are needed
        constant BUF_SIZE   : natural := sel(HOR, 2**LED_CNT_BITS, 2);
        
        type buf_type is
            array(0 to BUF_SIZE-1) of
            led_color_type;
        
        alias overlap
            : boolean is
            overlaps(side);
        
        alias abs_overlap
            : unsigned(LED_SIZE_BITS-1 downto 0) is
            abs_overlaps(side);
        
        alias inner_coords
            : inner_coords_type is
            leds_inner_coords(side);
        
        alias next_inner_coords
            : inner_coords_type is
            next_leds_inner_coords(side);
        
        alias first_led_pos
            : led_pos_type is
            first_leds_pos(side);
        
        alias led_num
            : unsigned(LED_CNT_BITS-1 downto 0) is
            led_nums(side);
        
        signal led_cnt
            : unsigned(LED_CNT_BITS-1 downto 0)
            := (others => '0');
        
        signal led_width, led_height
            : unsigned(LED_SIZE_BITS-1 downto 0)
            := (others => '0');
        
        signal cur_led_p    : natural := 0;
        
        signal side_buf : buf_type;
    begin
        
        hor_param_gen : if hor generate
            led_cnt     <= uns(HOR_LED_CNT);
            led_width   <= uns(HOR_LED_WIDTH);
            led_height  <= uns(HOR_LED_HEIGHT);
            cur_led_p   <= int(led_num);
        end generate;
        
        ver_param_gen : if ver generate
            led_cnt     <= uns(VER_LED_CNT);
            led_width   <= uns(VER_LED_WIDTH);
            led_height  <= uns(VER_LED_HEIGHT);
            cur_led_p   <= 0;
        end generate;
        
        side_scan_proc : process(RST, CLK)
        begin
            if RST='1' then
                inner_coords    <= inner_coords_type_def;
                led_num         <= (others => '0');
            elsif rising_edge(CLK) then
                if FRAME_HSYNC='1' then
                    if
                        frame_x>=first_led_pos(X) and
                        led_num<led_cnt and
                        frame_y>=first_led_pos(Y)
                    then
                        if inner_coords(X)=0 and inner_coords(Y)=0 then
                            -- first pixel of a LED area
                            side_buf(cur_led_p).R   <= FRAME_R;
                            side_buf(cur_led_p).G   <= FRAME_G;
                            side_buf(cur_led_p).B   <= FRAME_B;
                        else
                            -- any other pixel of the LED area
                            side_buf(cur_led_p).R   <= arithMean(FRAME_R, side_buf(cur_led_p).R);
                            side_buf(cur_led_p).G   <= arithMean(FRAME_G, side_buf(cur_led_p).G);
                            side_buf(cur_led_p).B   <= arithMean(FRAME_B, side_buf(cur_led_p).B);
                        end if;
                        
                        if overlap then
                            if
                                (ver and inner_coords(X)=0 and next_inner_coords(Y)=0)
                                or
                                (hor and inner_coords(Y)=0 and next_inner_coords(X)=0)
                            then
                                -- first pixel of the next (overlapping) LED area
                                side_buf(cur_led_p+1).R <= FRAME_R;
                                side_buf(cur_led_p+1).G <= FRAME_G;
                                side_buf(cur_led_p+1).B <= FRAME_B;
                            else
                                -- any other pixel of the next (overlapping) LED area
                                side_buf(cur_led_p+1).R <= arithMean(FRAME_R, side_buf(cur_led_p+1).R);
                                side_buf(cur_led_p+1).G <= arithMean(FRAME_G, side_buf(cur_led_p+1).G);
                                side_buf(cur_led_p+1).B <= arithMean(FRAME_B, side_buf(cur_led_p+1).B);
                            end if;
                        end if;
                        
                        -- left led x & y increment
                        if ver then
                            
                            -- L and R: the LED is changed after one LED is completed
                            inner_coords(X) <= inner_coords(X)+1;
                            if inner_coords(X)=led_width-1 or frame_x=FRAME_WIDTH-1 then
                                inner_coords(X) <= (others => '0');
                                inner_coords(Y) <= inner_coords(Y)+1;
                                if inner_coords(Y)=led_height-1 or frame_y=FRAME_HEIGHT-1 then
                                    led_num <= led_num+1;
                                    if overlap then
                                        -- the first part of the now 'current LED' is in the
                                        -- previously 'next LED' register
                                        side_buf(cur_led_p) <= side_buf(cur_led_p+1);
                                        inner_coords(Y)     <= abs_overlap;
                                    else
                                        inner_coords(Y)     <= (others => '0');
                                    end if;
                                end if;
                            end if;
                            
                        elsif hor then
                            
                            -- T and B: the LED is changed after one row of pixels is completed
                            inner_coords(X) <= inner_coords(X)+1;
                            if inner_coords(X)=led_width-1 or frame_x=FRAME_WIDTH-1 then
                                inner_coords(X) <= (others => '0');
                                led_num         <= led_num+1;
                                if led_num=led_cnt then
                                    -- frame row chaning, jump to the first LED
                                    inner_coords(Y) <= inner_coords(Y)+1;
                                    led_num         <= (others => '0');
                                elsif overlap then
                                    inner_coords(X) <= abs_overlap;
                                end if;
                            end if;
                            
                        end if;
                    end if;
                end if;
                if FRAME_VSYNC='0' then
                    inner_coords    <= inner_coords_type_def;
                end if;
            end if;
        end process;
        
    end generate;
    
end rtl;