----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    15:19:05 07/03/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    VER_SCANNER - rtl 
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
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

entity VER_SCANNER is
    generic (
        FRAME_SIZE_BITS : natural := 11;
        LED_CNT_BITS    : natural := 7;
        LED_SIZE_BITS   : natural := 7;
        LED_PAD_BITS    : natural := 7;
        LED_OFFS_BITS   : natural := 7;
        LED_STEP_BITS   : natural := 7;
        R_BITS          : natural range 1 to 12 := 8;
        G_BITS          : natural range 1 to 12 := 8;
        B_BITS          : natural range 1 to 12 := 8
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        LED_CNT : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        
        LED_WIDTH   : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        LED_HEIGHT  : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        LED_STEP    : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        
        LED_PAD     : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_OFFS    : in std_ulogic_vector(LED_OFFS_BITS-1 downto 0);
        
        FRAME_VSYNC : in std_ulogic;
        FRAME_HSYNC : in std_ulogic;
        
        FRAME_X : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        FRAME_Y : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        
        FRAME_WIDTH     : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        
        FRAME_R : in std_ulogic_vector(R_BITS-1 downto 0);
        FRAME_G : in std_ulogic_vector(G_BITS-1 downto 0);
        FRAME_B : in std_ulogic_vector(B_BITS-1 downto 0);
        
        LED_VALID   : out std_ulogic := '0';
        LED_NUM     : out std_ulogic_vector(LED_CNT_BITS-1 downto 0) := (others => '0');
        LED_SIDE    : out std_ulogic := '0';
        LED_COLOR   : out std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0')
    );
end VER_SCANNER;

architecture rtl of VER_SCANNER is
    
    constant RGB_BITS   : natural := R_BITS+G_BITS+B_BITS;
    
    -----------------------------
    --- array element aliases ---
    -----------------------------
    
    constant L  : natural := 0; -- left
    constant R  : natural := 1; -- right
    
    constant X  : natural := 0;
    constant Y  : natural := 1;
    
    -------------
    --- types ---
    -------------
    
    -- vertical buffer: used by the left LED column and the right LED column, the LEDs are
    -- completely computed one at a time (frame top to bottom), so we only need a buffer
    -- for four LEDs because of the possible overlap of two LEDs per side
    type led_buf_type is
        array(0 to 3) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    type inner_coords_type is
        array(0 to 1) of
        unsigned(LED_SIZE_BITS-1 downto 0);
    
    type led_pos_type is
        array(0 to 1) of
        unsigned(FRAME_SIZE_BITS-1 downto 0);
    
    signal led_num_reg  : unsigned(LED_CNT_BITS-1 downto 0) := (others => '0');
    signal overlaps     : boolean := false;
    signal abs_overlap  : unsigned(LED_SIZE_BITS-1 downto 0) := (others => '0');
    
    signal
        inner_coords,
        next_inner_coords
        : inner_coords_type
        := (others => (others => '0'));
    
    signal
        first_led_pos,
        led_pos
        : led_pos_type
        := (others => (others => '0'));
    
    signal side                 : natural range L to R := L;
    signal led_num_p            : natural range 0 to 3 := 0;
    signal led_buf              : led_buf_type;
    signal led_first_left_x     : unsigned(LED_PAD_BITS-1 downto 0);
    signal led_first_right_x    : unsigned(FRAME_SIZE_BITS-1 downto 0);
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    -- in case of overlapping LEDs, the position of the next LED's pixel area is needed
    next_inner_coords(X)    <= inner_coords(X);
    next_inner_coords(Y)    <= inner_coords(Y)+uns(LED_HEIGHT);
    
    -- is there any overlap?
    overlaps    <= LED_STEP<LED_HEIGHT;
    
    -- the amount of overlapping pixels (in one dimension)
    abs_overlap <= uns(LED_HEIGHT-LED_STEP);
    
    -- x coordinate of every left/right LED
    led_first_left_x    <= uns(LED_PAD);
    led_first_right_x   <= uns(FRAME_WIDTH-LED_WIDTH-LED_PAD);
    
    -- point of the first pixel of the first LED on each side (the most top left pixel)
    first_led_pos(X)    <=
        resize( led_first_left_x,   FRAME_SIZE_BITS) when side=L else
                led_first_right_x;
    first_led_pos(Y)    <=  resize(uns(LED_OFFS), FRAME_SIZE_BITS);
    
    -----------------
    --- processes ---
    -----------------
    
    ver_scan_proc : process(RST, CLK)
        variable
            old_led_color,
            new_led_color
        : std_ulogic_vector(RGB_BITS-1 downto 0);
    begin
        if RST='1' then
            inner_coords        <= (others => (others => '0'));
            led_num_reg         <= (others => '0');
            LED_VALID           <= '0';
            LED_SIDE            <= '0';
            side                <= L;
            led_num_p           <= 0;
        elsif rising_edge(CLK) then
            LED_VALID           <= '0';
            
            if led_num_reg=0 then
                led_pos <= first_led_pos;
            end if;
            
            if FRAME_HSYNC='1' then
                if
                    led_num_reg<led_cnt and
                    FRAME_X>=led_pos(X) and
                    FRAME_X<led_pos(X)+led_width and
                    FRAME_Y>=led_pos(Y) and
                    FRAME_Y<led_pos(Y)+led_height
                then
                    -- within an LED area
                    
                    if inner_coords(X)=0 and inner_coords(Y)=0 then
                        -- first pixel of a LED area
                        led_buf(led_num_p)  <= FRAME_R & FRAME_G & FRAME_G;
                    else
                        -- any other pixel of the LED area
                        old_led_color   := led_buf(led_num_p);
                        new_led_color   :=
                            arith_mean(FRAME_R, old_led_color(RGB_BITS-1 downto G_BITS+B_BITS)) &
                            arith_mean(FRAME_G, old_led_color(G_BITS+B_BITS-1 downto B_BITS)) &
                            arith_mean(FRAME_B, old_led_color(B_BITS-1 downto 0));
                        led_buf(led_num_p)  <= new_led_color;
                    end if;
                    
                    if
                        overlaps and
                        led_num_reg<LED_CNT-1
                    then
                        if
                            next_inner_coords(X)=0 and
                            next_inner_coords(Y)=0
                        then
                            -- first pixel of the next (overlapping) LED area
                            led_buf((led_num_p+1) mod 4)    <= FRAME_R & FRAME_G & FRAME_G;
                        else
                            -- any other pixel of the next (overlapping) LED area
                            old_led_color   := led_buf(led_num_p+1);
                            new_led_color   :=
                                arith_mean(FRAME_R, old_led_color(RGB_BITS-1 downto G_BITS+B_BITS)) &
                                arith_mean(FRAME_G, old_led_color(G_BITS+B_BITS-1 downto B_BITS)) &
                                arith_mean(FRAME_B, old_led_color(B_BITS-1 downto 0));
                            led_buf((led_num_p+1) mod 4)   <= new_led_color;
                        end if;
                    end if;
                    
                    -- left led x & y increment;
                    -- the LED is changed after one LED is completed
                    inner_coords(X) <= inner_coords(X)+1;
                    if inner_coords(X)=led_width-1 or FRAME_X=FRAME_WIDTH-1 then
                        inner_coords(X) <= (others => '0');
                        led_num_p       <= (led_num_p+2) mod 4;
                        if side=L then
                            side        <= R;
                            led_pos(X)  <= resize(led_first_right_x, FRAME_SIZE_BITS);
                        else
                            side        <= L;
                            led_pos(X)  <= resize(led_first_left_x, FRAME_SIZE_BITS);
                        end if;
                        if side=R or FRAME_X=FRAME_WIDTH-1 then
                            inner_coords(Y) <= inner_coords(Y)+1;
                        end if;
                        if inner_coords(Y)=led_height-1 or FRAME_Y=FRAME_HEIGHT-1 then
                            -- this was the last pixel of the LED area
                            LED_VALID   <= '1';
                            LED_COLOR   <= led_buf(led_num_p);
                            LED_NUM     <= stdulv(led_num_reg);
                            if side=L then
                                LED_SIDE    <= '0';
                            else
                                LED_SIDE    <= '1';
                            end if;
                            if side=R then
                                led_num_reg     <= led_num_reg+1;
                                led_pos(Y)      <= uns(led_pos(Y)+LED_STEP);
                                inner_coords(Y) <= (others => '0');
                                if overlaps and led_num_reg<LED_CNT-1 then
                                    -- the first part of the now 'current LED' is
                                    -- in the previously 'next LED' register,
                                    -- switch the two registers, continue after the overlap
                                    led_num_p       <= (led_num_p+3) mod 4;
                                    inner_coords(Y) <= abs_overlap;
                                end if;
                            end if;
                        end if;
                    end if;
                    
                end if;
            end if;
            if FRAME_VSYNC='0' then
                inner_coords    <= (others => (others => '0'));
                led_num_reg     <= (others => '0');
                side            <= L;
            end if;
        end if;
    end process;
    
end rtl;

