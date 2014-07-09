----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:00:46 07/03/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    HOR_SCANNER - rtl 
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--   Any LED area must be within the FRAME!
--   The minimum LED area is 1x3 pixel in size!
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity HOR_SCANNER is
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
        
        FRAME_HEIGHT    : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        
        FRAME_R : in std_ulogic_vector(R_BITS-1 downto 0);
        FRAME_G : in std_ulogic_vector(G_BITS-1 downto 0);
        FRAME_B : in std_ulogic_vector(B_BITS-1 downto 0);
        
        LED_VALID   : out std_ulogic := '0';
        LED_NUM     : out std_ulogic_vector(LED_CNT_BITS-1 downto 0) := (others => '0');
        LED_SIDE    : out std_ulogic := '0';
        LED_COLOR   : out std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0')
    );
end HOR_SCANNER;

architecture rtl of HOR_SCANNER is
    
    constant RGB_BITS   : natural := R_BITS+G_BITS+B_BITS;
    
    -----------------------------
    --- array element aliases ---
    -----------------------------
    
    constant T  : natural := 0; -- top
    constant B  : natural := 1; -- bottom
    
    constant X  : natural := 0;
    constant Y  : natural := 1;
    
    -------------
    --- types ---
    -------------
    
    -- horizontal buffer: used by the top LED row and the bottom LED row, one frame row
    -- contains one row of each LED, so we need a buffer for all those LEDs
    type led_buf_type is
        array(0 to (2**LED_CNT_BITS)-1) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    type inner_coords_type is
        array(0 to 1) of
        unsigned(LED_SIZE_BITS-1 downto 0);
    
    type led_pos_type is
        array(0 to 1) of
        unsigned(FRAME_SIZE_BITS-1 downto 0);
    
    type leds_pos_type is
        array(0 to 1) of
        led_pos_type;
    
    type state_type is (
        FIRST_LED_FIRST_PIXEL,
        LEFT_BORDER_PIXEL,
        MAIN_PIXEL,
        RIGHT_BORDER_PIXEL,
        LINE_SWITCH,
        LAST_PIXEL,
        SIDE_SWITCH
    );
    
    type reg_type is record
        state               : state_type;
        side                : natural range T to B;
        buf_p               : natural range 0 to (2**LED_CNT_BITS)-1;
        buf_di              : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_ov_di           : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_wr_en           : std_ulogic;
        buf_ov_wr_en        : std_ulogic;
        inner_coords        : inner_coords_type;
        led_pos             : led_pos_type;
        led_valid           : std_ulogic;
        led_num             : std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        led_color           : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state               => FIRST_LED_FIRST_PIXEL,
        side                => T,
        buf_p               => 0,
        buf_di              => (others => '0'),
        buf_ov_di           => (others => '0'),
        buf_wr_en           => '0',
        buf_ov_wr_en        => '0',
        inner_coords        => (others => (others => '0')),
        led_pos             => (others => (others => '0')),
        led_valid           => '0',
        led_num             => (others => '0'),
        led_color           => (others => '0')
    );
    
    signal next_inner_x         : unsigned(LED_SIZE_BITS-1 downto 0) := (others => '0');
    signal first_leds_pos       : leds_pos_type;
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal overlaps             : boolean := false;
    signal abs_overlap          : unsigned(LED_SIZE_BITS-1 downto 0) := (others => '0');
    signal led_buf              : led_buf_type;
    signal buf_do               : std_ulogic_vector(RGB_BITS-1 downto 0);
    signal buf_ov_do            : std_ulogic_vector(RGB_BITS-1 downto 0);
    signal frame_rgb            : std_ulogic_vector(RGB_BITS-1 downto 0);
    
    function led_arith_mean(vl, vr : std_ulogic_vector) return std_ulogic_vector is
        variable rl, rr : std_ulogic_vector(R_BITS-1 downto 0);
        variable gl, gr : std_ulogic_vector(G_BITS-1 downto 0);
        variable bl, br : std_ulogic_vector(B_BITS-1 downto 0);
    begin
        -- computes the arithmetic means of each R, G and B component
        rl  := vl(RGB_BITS-1 downto G_BITS+B_BITS);
        gl  := vl(G_BITS+B_BITS-1 downto B_BITS);
        bl  := vl(B_BITS-1 downto 0);
        rr  := vr(RGB_BITS-1 downto G_BITS+B_BITS);
        gr  := vr(G_BITS+B_BITS-1 downto B_BITS);
        br  := vr(B_BITS-1 downto 0);
        return
            arith_mean(rl, rr) &
            arith_mean(gl, gr) &
            arith_mean(bl, br);
    end function;
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    LED_VALID   <= cur_reg.led_valid;
    LED_NUM     <= cur_reg.led_num;
    LED_SIDE    <= '0' when cur_reg.side=T else '1';
    LED_COLOR   <= cur_reg.led_color;
    
    frame_rgb   <= FRAME_R & FRAME_G & FRAME_B;
    
    -- the position of the first top/bottom LED
    first_leds_pos(T)(X)    <= resize(uns(LED_OFFS), FRAME_SIZE_BITS);
    first_leds_pos(T)(Y)    <= resize(uns(LED_PAD), FRAME_SIZE_BITS);
    first_leds_pos(B)(X)    <= resize(uns(LED_OFFS), FRAME_SIZE_BITS);
    first_leds_pos(B)(Y)    <= uns(FRAME_HEIGHT-LED_HEIGHT-LED_PAD);
    
    -- in case of overlapping LEDs, the position of the next LED's pixel area is needed
    next_inner_x    <= cur_reg.inner_coords(X)-uns(LED_STEP);
    
    -- is there any overlap?
    overlaps    <= LED_STEP<LED_WIDTH;
    
    -- the amount of overlapping pixels (in one dimension)
    abs_overlap <= uns(LED_WIDTH-LED_STEP);
    
    
    -----------------
    --- processes ---
    -----------------
    
    -- ensure block RAM usage
    led_buf_proc : process(CLK)
        alias p         is next_reg.buf_p;
        alias di        is next_reg.buf_di;
        alias ov_di     is next_reg.buf_ov_di;
        alias do        is buf_do;
        alias ov_do     is buf_ov_do;
        alias wr_en     is next_reg.buf_wr_en;
        alias ov_wr_en  is next_reg.buf_ov_wr_en;
        variable ov_p   : natural range 0 to (2**LED_CNT_BITS)-1;
    begin
        if rising_edge(CLK) then
            -- write first mode
            if wr_en='1' then
                led_buf(p)      <= di;
                do              <= di;
            else
                do  <= led_buf(p);
            end if;
            
            ov_p    := (p+1) mod 2**LED_CNT_BITS;
            if ov_wr_en='1' then
                led_buf(ov_p)   <= ov_di;
                ov_do           <= ov_di;
            else
                ov_do   <= led_buf(ov_p);
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_HEIGHT, FRAME_VSYNC, FRAME_HSYNC, FRAME_X, FRAME_Y,
        LED_CNT, LED_WIDTH, LED_HEIGHT, LED_STEP, LED_OFFS, frame_rgb, buf_do, buf_ov_do,
        overlaps, abs_overlap, next_inner_x, first_leds_pos
    )
        alias cr        : reg_type is cur_reg;
        variable r      : reg_type;
    begin
        r   := cr;
        
        r.led_valid     := '0';
        r.buf_wr_en     := '0';
        
        case cr.state is
            
            when FIRST_LED_FIRST_PIXEL =>
                r.buf_p             := 0;
                r.buf_ov_wr_en      := '0';
                r.led_pos           := first_leds_pos(cr.side);
                r.inner_coords(X)   := uns(1, LED_SIZE_BITS);
                r.inner_coords(Y)   := (others => '0');
                r.buf_di            := frame_rgb;
                if
                    FRAME_HSYNC='1' and
                    FRAME_X=stdulv(first_leds_pos(cr.side)(X)) and
                    FRAME_Y=stdulv(first_leds_pos(cr.side)(Y))
                then
                    r.buf_wr_en         := '1';
                    r.state             := MAIN_PIXEL;
                end if;
            
            when LEFT_BORDER_PIXEL =>
                r.inner_coords(X)   := uns(1, LED_SIZE_BITS);
                r.buf_di            := frame_rgb;
                r.buf_ov_wr_en      := '0';
                if
                    FRAME_HSYNC='1' and
                    FRAME_X=stdulv(cr.led_pos(X))
                then
                    r.buf_wr_en := '1';
                    r.state     := MAIN_PIXEL;
                end if;
            
            when MAIN_PIXEL =>
                r.buf_di    := led_arith_mean(frame_rgb, buf_do);
                if FRAME_HSYNC='1' then
                    r.buf_wr_en         := '1';
                    r.inner_coords(X)   := cr.inner_coords(X)+1;
                    if overlaps and next_inner_x=0 then
                        -- begin processing the next overlapping LED
                        r.buf_ov_wr_en  := '1';
                    end if;
                    if cr.inner_coords(X)=LED_WIDTH-2 then
                        r.state := RIGHT_BORDER_PIXEL;
                        if cr.inner_coords(Y)=LED_HEIGHT-1 then
                            r.state := LAST_PIXEL;
                        end if;
                    end if;
                end if;
            
            when RIGHT_BORDER_PIXEL =>
                r.inner_coords(X)   := (others => '0');
                r.buf_di            := led_arith_mean(frame_rgb, buf_do);
                if overlaps then
                    r.inner_coords(X)   := abs_overlap;
                end if;
                if FRAME_HSYNC='1' then
                    r.buf_wr_en     := '1';
                    r.led_pos(X)    := uns(cr.led_pos(X)+LED_STEP);
                    r.state         := LEFT_BORDER_PIXEL;
                    r.buf_p         := cr.buf_p+1;
                    if cr.buf_p=LED_CNT-1 then
                        r.buf_p := 0;
                    end if;
                    if overlaps then
                        if next_inner_x=0 then
                            -- begin processing the next overlapping LED
                            r.buf_ov_wr_en  := '1';
                        end if;
                        r.state         := MAIN_PIXEL;
                    end if;
                    if cr.buf_p=LED_CNT-1 then
                        -- finished one line of all LED areas
                        r.state := LINE_SWITCH;
                    end if;
                end if;
            
            when LINE_SWITCH =>
                r.inner_coords(Y)   := cr.inner_coords(Y)+1;
                r.led_pos           := first_leds_pos(cr.side);
                r.buf_ov_wr_en      := '0';
                r.state             := LEFT_BORDER_PIXEL;
            
            when LAST_PIXEL =>
                r.inner_coords(X)   := (others => '0');
                if overlaps then
                    r.inner_coords(X)   := abs_overlap;
                end if;
                if FRAME_HSYNC='1' then
                    -- give out the LED color
                    r.led_valid     := '1';
                    r.led_color     := led_arith_mean(frame_rgb, buf_do);
                    r.led_num       := stdulv(cr.buf_p, LED_CNT_BITS);
                    
                    r.led_pos(X)    := uns(cr.led_pos(X)+LED_STEP);
                    r.buf_p         := cr.buf_p+1;
                    r.state         := LEFT_BORDER_PIXEL;
                    if overlaps then
                        r.state := MAIN_PIXEL;
                    end if;
                    if cr.buf_p=LED_CNT-1 then
                        r.buf_p := 0;
                        r.state := SIDE_SWITCH;
                    end if;
                end if;
            
            when SIDE_SWITCH =>
                r.side  := (cr.side+1) mod 2;
                r.state := FIRST_LED_FIRST_PIXEL;
            
        end case;
        
        -- in case there's an overlap,
        -- buffer the average color for the next LED
        r.buf_ov_di := led_arith_mean(frame_rgb, buf_ov_do);
        if
            next_inner_x=0 and
            cr.inner_coords(Y)=0
        then
            -- first pixel of the following LED,
            -- reset the buffer with the current color
            r.buf_ov_di := frame_rgb;
        end if;
        
        if RST='1' or FRAME_VSYNC='0' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;
    
    stm_sync_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;

