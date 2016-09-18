----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:00:46 07/03/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    HOR_SCANNER - rtl 
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--   Any LED area must be within the FRAME!
--   The minimum LED area is 1x3 pixel in size!
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity HOR_SCANNER is
    generic (
        MAX_LED_COUNT   : positive;
        R_BITS          : natural range 1 to 12 := 8;
        G_BITS          : natural range 1 to 12 := 8;
        B_BITS          : natural range 1 to 12 := 8
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CFG_ADDR    : in std_ulogic_vector(4 downto 0);
        CFG_WR_EN   : in std_ulogic;
        CFG_DATA    : in std_ulogic_vector(7 downto 0);
        
        FRAME_VSYNC     : in std_ulogic;
        FRAME_RGB_WR_EN : in std_ulogic;
        FRAME_RGB       : in std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        
        FRAME_X : in std_ulogic_vector(15 downto 0);
        FRAME_Y : in std_ulogic_vector(15 downto 0);
        
        LED_RGB_VALID   : out std_ulogic := '0';
        LED_RGB         : out std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');
        LED_NUM         : out std_ulogic_vector(7 downto 0) := x"00";
        LED_SIDE        : out std_ulogic := '0'
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
    -- contains one pixel of each LED of one side, so we need a buffer for all those LEDs
    type led_buf_type is
        array(0 to MAX_LED_COUNT-1) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    type inner_coords_type is
        array(0 to 1) of
        unsigned(15 downto 0);
    
    type led_pos_type is
        array(0 to 1) of
        unsigned(15 downto 0);
    
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
        state           : state_type;
        side            : natural range T to B;
        buf_p           : natural range 0 to MAX_LED_COUNT;
        buf_di          : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_ov_di       : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_wr_en       : std_ulogic;
        buf_ov_wr_en    : std_ulogic;
        inner_coords    : inner_coords_type;
        led_pos         : led_pos_type;
        led_rgb_valid   : std_ulogic;
        led_rgb         : std_ulogic_vector(RGB_BITS-1 downto 0);
        led_num         : std_ulogic_vector(7 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => FIRST_LED_FIRST_PIXEL,
        side            => T,
        buf_p           => 0,
        buf_di          => (others => '0'),
        buf_ov_di       => (others => '0'),
        buf_wr_en       => '0',
        buf_ov_wr_en    => '0',
        inner_coords    => (others => x"0000"),
        led_pos         => (others => x"0000"),
        led_rgb_valid   => '0',
        led_rgb         => (others => '0'),
        led_num         => x"00"
    );
    
    signal next_inner_x         : unsigned(15 downto 0) := x"0000";
    signal first_leds_pos       : leds_pos_type := (others => (others => x"0000"));
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal overlaps             : boolean := false;
    signal abs_overlap          : unsigned(15 downto 0) := x"0000";
    signal led_buf              : led_buf_type := (others => (others => '0'));
    signal buf_do               : std_ulogic_vector(RGB_BITS-1 downto 0) := (others => '0');
    signal buf_ov_do            : std_ulogic_vector(RGB_BITS-1 downto 0) := (others => '0');
    
    -- configuration registers
    signal led_cnt      : std_ulogic_vector(7 downto 0) := x"00";
    signal led_width    : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_height   : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_step     : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_pad      : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_offs     : std_ulogic_vector(15 downto 0) := x"0000";
    
    signal frame_height : std_ulogic_vector(15 downto 0) := x"0000";
    
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
    
    LED_RGB_VALID   <= cur_reg.led_rgb_valid;
    LED_RGB         <= cur_reg.led_rgb;
    LED_NUM         <= cur_reg.led_num;
    LED_SIDE        <= '0' when cur_reg.side=T else '1';
    
    -- the position of the first top/bottom LED
    first_leds_pos(T)(X)    <= uns(led_offs);
    first_leds_pos(T)(Y)    <= uns(led_pad);
    first_leds_pos(B)(X)    <= uns(led_offs);
    first_leds_pos(B)(Y)    <= uns(frame_height-led_height-led_pad);
    
    -- in case of overlapping LEDs, the position of the next LED's pixel area is needed
    next_inner_x    <= cur_reg.inner_coords(X)-uns(led_step);
    
    -- is there any overlap?
    overlaps    <= led_step<led_width;
    
    -- the amount of overlapping pixels (in one dimension)
    abs_overlap <= uns(led_width-led_step);
    
    
    -----------------
    --- processes ---
    -----------------
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "00000" => led_cnt                     <= CFG_DATA;
                    when "00001" => led_width(15 downto 8)      <= CFG_DATA;
                    when "00010" => led_width(7 downto 0)       <= CFG_DATA;
                    when "00011" => led_height(15 downto 8)     <= CFG_DATA;
                    when "00100" => led_height(7 downto 0)      <= CFG_DATA;
                    when "00101" => led_step(15 downto 8)       <= CFG_DATA;
                    when "00110" => led_step(7 downto 0)        <= CFG_DATA;
                    when "00111" => led_pad(15 downto 8)        <= CFG_DATA;
                    when "01000" => led_pad(7 downto 0)         <= CFG_DATA;
                    when "01001" => led_offs(15 downto 8)       <= CFG_DATA;
                    when "01010" => led_offs(7 downto 0)        <= CFG_DATA;
                    when "11000" => frame_height(15 downto 8)   <= CFG_DATA;
                    when "11001" => frame_height(7 downto 0)    <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    -- ensure block RAM usage
    led_buf_proc : process(CLK)
        alias p         is next_reg.buf_p;
        alias di        is next_reg.buf_di;
        alias ov_di     is next_reg.buf_ov_di;
        alias do        is buf_do;
        alias ov_do     is buf_ov_do;
        alias wr_en     is next_reg.buf_wr_en;
        alias ov_wr_en  is next_reg.buf_ov_wr_en;
        variable ov_p   : natural range 0 to MAX_LED_COUNT;
    begin
        if rising_edge(CLK) then
            -- write first mode
            if wr_en='1' then
                led_buf(p)  <= di;
                do          <= di;
            else
                do  <= led_buf(p);
            end if;
            
            ov_p    := p+1 mod 256;
            if ov_wr_en='1' then
                led_buf(ov_p)   <= ov_di;
                ov_do           <= ov_di;
            else
                ov_do   <= led_buf(ov_p);
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, frame_height, FRAME_VSYNC, FRAME_RGB_WR_EN, FRAME_X, FRAME_Y,
        led_cnt, led_width, led_height, led_step, led_offs, FRAME_RGB, buf_do, buf_ov_do,
        overlaps, abs_overlap, next_inner_x, first_leds_pos
    )
        alias cr    : reg_type is cur_reg;      -- synchronous registers
        variable r  : reg_type := reg_type_def; -- asynchronous combinational signals
    begin
        r   := cr;
        
        r.led_rgb_valid     := '0';
        r.buf_wr_en         := '0';
        
        case cr.state is
            
            when FIRST_LED_FIRST_PIXEL =>
                r.buf_p             := 0;
                r.buf_ov_wr_en      := '0';
                r.led_pos           := first_leds_pos(cr.side);
                r.inner_coords(X)   := x"0001";
                r.inner_coords(Y)   := (others => '0');
                r.buf_di            := FRAME_RGB;
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=stdulv(first_leds_pos(cr.side)(X)) and
                    FRAME_Y=stdulv(first_leds_pos(cr.side)(Y))
                then
                    r.buf_wr_en         := '1';
                    r.state             := MAIN_PIXEL;
                end if;
            
            when LEFT_BORDER_PIXEL =>
                r.inner_coords(X)   := x"0001";
                r.buf_di            := led_arith_mean(FRAME_RGB, buf_do);
                r.buf_ov_wr_en      := '0';
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=stdulv(cr.led_pos(X))
                then
                    r.buf_wr_en := '1';
                    r.state     := MAIN_PIXEL;
                end if;
            
            when MAIN_PIXEL =>
                r.buf_di    := led_arith_mean(FRAME_RGB, buf_do);
                if FRAME_RGB_WR_EN='1' then
                    r.buf_wr_en         := '1';
                    r.inner_coords(X)   := cr.inner_coords(X)+1;
                    if overlaps and next_inner_x=0 then
                        -- begin processing the next overlapping LED
                        r.buf_ov_wr_en  := '1';
                    end if;
                    if cr.inner_coords(X)=led_width-2 then
                        r.state := RIGHT_BORDER_PIXEL;
                        if cr.inner_coords(Y)=led_height-1 then
                            r.state := LAST_PIXEL;
                        end if;
                    end if;
                end if;
            
            when RIGHT_BORDER_PIXEL =>
                r.inner_coords(X)   := x"0000";
                r.buf_di            := led_arith_mean(FRAME_RGB, buf_do);
                if overlaps then
                    r.inner_coords(X)   := abs_overlap;
                end if;
                if FRAME_RGB_WR_EN='1' then
                    r.buf_wr_en     := '1';
                    r.led_pos(X)    := cr.led_pos(X)+led_step;
                    r.state         := LEFT_BORDER_PIXEL;
                    r.buf_p         := cr.buf_p+1;
                    if cr.buf_p=led_cnt-1 then
                        r.buf_p := 0;
                    end if;
                    if overlaps then
                        if next_inner_x=0 then
                            -- begin processing the next overlapping LED
                            r.buf_ov_wr_en  := '1';
                        end if;
                        r.state := MAIN_PIXEL;
                    end if;
                    if cr.buf_p=led_cnt-1 then
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
                r.inner_coords(X)   := x"0000";
                if overlaps then
                    r.inner_coords(X)   := abs_overlap;
                end if;
                if FRAME_RGB_WR_EN='1' then
                    -- give out the LED color
                    -- (no need for buffering)
                    r.led_rgb_valid := '1';
                    r.led_rgb       := led_arith_mean(FRAME_RGB, buf_do);
                    r.led_num       := stdulv(cr.buf_p, 8);
                    
                    r.led_pos(X)    := cr.led_pos(X)+led_step;
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
                r.side  := B;
                r.state := FIRST_LED_FIRST_PIXEL;
            
        end case;
        
        -- in case there's an overlap,
        -- buffer the average color for the next LED
        r.buf_ov_di := led_arith_mean(FRAME_RGB, buf_ov_do);
        if
            next_inner_x=0 and
            cr.inner_coords(Y)=0
        then
            -- first pixel of the following LED,
            -- reset the buffer with the current color
            r.buf_ov_di := FRAME_RGB;
        end if;
        
        if RST='1' or FRAME_VSYNC='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;
    
    sync_stm_proc : process(RST, CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;

