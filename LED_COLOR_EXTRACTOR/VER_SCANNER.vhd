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

library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity VER_SCANNER is
    generic (
        R_BITS          : natural range 1 to 12 := 8;
        G_BITS          : natural range 1 to 12 := 8;
        B_BITS          : natural range 1 to 12 := 8
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CFG_ADDR    : in std_ulogic_vector(3 downto 0);
        CFG_WR_EN   : in std_ulogic;
        CFG_DATA    : in std_ulogic_vector(7 downto 0);
        
        FRAME_VSYNC : in std_ulogic;
        FRAME_HSYNC : in std_ulogic;
        
        FRAME_X : in std_ulogic_vector(15 downto 0);
        FRAME_Y : in std_ulogic_vector(15 downto 0);
        
        FRAME_R : in std_ulogic_vector(R_BITS-1 downto 0);
        FRAME_G : in std_ulogic_vector(G_BITS-1 downto 0);
        FRAME_B : in std_ulogic_vector(B_BITS-1 downto 0);
        
        LED_VALID   : out std_ulogic := '0';
        LED_NUM     : out std_ulogic_vector(7 downto 0) := (others => '0');
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
    
    -- vertical buffer: used by the left LED column and the right LED column, one frame row
    -- contains one row of two LEDs, so we need a buffer for those two plus two overlapping LEDs
    type led_buf_type is
        array(0 to 3) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    type inner_coords_type is
        array(0 to 1) of
        unsigned(7 downto 0);
    
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
        state               : state_type;
        side                : natural range L to R;
        buf_p               : natural range 0 to 1;
        buf_di              : std_ulogic_vector(RGB_BITS-1 downto 0);
        ov_buf_di           : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_wr_en           : std_ulogic;
        inner_coords        : inner_coords_type;
        led_pos             : led_pos_type;
        led_valid           : std_ulogic;
        led_num             : std_ulogic_vector(7 downto 0);
        led_color           : std_ulogic_vector(RGB_BITS-1 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state               => FIRST_LED_FIRST_PIXEL,
        side                => L,
        buf_p               => 0,
        buf_di              => (others => '0'),
        ov_buf_di           => (others => '0'),
        buf_wr_en           => '0',
        inner_coords        => (others => (others => '0')),
        led_pos             => (others => (others => '0')),
        led_valid           => '0',
        led_num             => (others => '0'),
        led_color           => (others => '0')
    );
    
    signal next_inner_y         : unsigned(7 downto 0) := (others => '0');
    signal first_leds_pos       : leds_pos_type;
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal overlaps             : boolean := false;
    signal abs_overlap          : unsigned(7 downto 0) := (others => '0');
    signal led_buf              : led_buf_type;
    signal buf_do               : std_ulogic_vector(RGB_BITS-1 downto 0);
    signal ov_buf_do            : std_ulogic_vector(RGB_BITS-1 downto 0);
    signal frame_rgb            : std_ulogic_vector(RGB_BITS-1 downto 0);
    
    -- configuration registers
    signal led_cnt      : std_ulogic_vector(7 downto 0) := x"00";
    signal led_width    : std_ulogic_vector(7 downto 0) := x"00";
    signal led_height   : std_ulogic_vector(7 downto 0) := x"00";
    signal led_step     : std_ulogic_vector(7 downto 0) := x"00";
    signal led_pad      : std_ulogic_vector(7 downto 0) := x"00";
    signal led_offs     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal frame_width  : std_ulogic_vector(15 downto 0) := x"0000";
    
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
    LED_SIDE    <= '0' when cur_reg.side=L else '1';
    LED_COLOR   <= cur_reg.led_color;
    
    frame_rgb   <= FRAME_R & FRAME_G & FRAME_B;
    
    -- the position of the first left/right LED
    first_leds_pos(L)(X)    <= resize(uns(led_pad), 16);
    first_leds_pos(L)(Y)    <= resize(uns(led_offs), 16);
    first_leds_pos(R)(X)    <= uns(frame_width-led_width-led_pad);
    first_leds_pos(R)(Y)    <= resize(uns(led_offs), 16);
    
    -- in case of overlapping LEDs, the position of the next LED's pixel area is needed
    next_inner_y    <= cur_reg.inner_coords(Y)-uns(led_step);
    
    -- is there any overlap?
    overlaps    <= led_step<led_height;
    
    -- the amount of overlapping pixels (in one dimension)
    abs_overlap <= uns(led_height-led_step);
    
    
    -----------------
    --- processes ---
    -----------------
    
    cfg_proc : process(RST, CLK)
    begin
        if RST='1' then
            led_cnt     <= x"00";
            led_width   <= x"00";
            led_height  <= x"00";
            led_step    <= x"00";
            led_pad     <= x"00";
            led_offs    <= x"00";
            frame_width <= x"0000";
        elsif rising_edge(CLK) then
            if CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "0110" => led_cnt                  <= CFG_DATA;
                    when "0111" => led_width                <= CFG_DATA;
                    when "1000" => led_height               <= CFG_DATA;
                    when "1001" => led_step                 <= CFG_DATA;
                    when "1010" => led_pad                  <= CFG_DATA;
                    when "1011" => led_offs                 <= CFG_DATA;
                    when "1100" => frame_width(15 downto 8) <= CFG_DATA;
                    when "1101" => frame_width(7 downto 0)  <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    -- ensure block RAM usage
    led_buf_proc : process(CLK)
        alias p     is next_reg.buf_p;
        alias di    is next_reg.buf_di;
        alias ov_di is next_reg.ov_buf_di;
        alias do    is buf_do;
        alias ov_do is ov_buf_do;
        alias wr_en is next_reg.buf_wr_en;
    begin
        if rising_edge(CLK) then
            -- write first mode
            if wr_en='1' then
                led_buf(p)      <= di;
                led_buf(p+2)    <= ov_di;
                do              <= di;
                ov_do           <= ov_di;
            else
                do      <= led_buf(p);
                ov_do   <= led_buf(p+2);
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_WIDTH, FRAME_VSYNC, FRAME_HSYNC, FRAME_X, FRAME_Y,
        LED_WIDTH, LED_HEIGHT, LED_STEP, LED_OFFS, frame_rgb, buf_do, ov_buf_do, overlaps,
        abs_overlap, next_inner_y, first_leds_pos
    )
        alias cr        : reg_type is cur_reg; -- current registers
        variable tr     : reg_type;            -- temporary registers
    begin
        tr  := cr;
        
        tr.led_valid    := '0';
        tr.buf_wr_en    := '0';
        
        tr.ov_buf_di    := led_arith_mean(frame_rgb, ov_buf_do);
        
        case cr.state is
            
            when FIRST_LED_FIRST_PIXEL =>
                tr.led_pos          := first_leds_pos(cr.side);
                tr.inner_coords(X)  := x"01";
                tr.inner_coords(Y)  := (others => '0');
                tr.buf_di           := frame_rgb;
                if
                    FRAME_HSYNC='1' and
                    FRAME_X=stdulv(first_leds_pos(cr.side)(X)) and
                    FRAME_Y=stdulv(first_leds_pos(cr.side)(Y))
                then
                    tr.buf_wr_en    := '1';
                    tr.state        := MAIN_PIXEL;
                end if;
            
            when LEFT_BORDER_PIXEL =>
                tr.inner_coords(X)  := x"01";
                tr.buf_di           := frame_rgb;
                if
                    overlaps and
                    cr.led_num/=0 and
                    cr.inner_coords(Y)=abs_overlap
                then
                    -- not the first LED and there's an overlap,
                    -- use the buffered color average for the first pixel
                    tr.buf_di   := led_arith_mean(frame_rgb, ov_buf_do);
                end if;
                if next_inner_y=0 then
                    -- first pixel of the following LED,
                    -- reset the buffer with the current color
                    tr.ov_buf_di    := frame_rgb;
                end if;
                if
                    FRAME_HSYNC='1' and
                    FRAME_X=stdulv(cr.led_pos(X)) and
                    FRAME_Y>=stdulv(cr.led_pos(Y))
                then
                    tr.buf_wr_en    := '1';
                    tr.state        := MAIN_PIXEL;
                end if;
            
            when MAIN_PIXEL =>
                tr.buf_di   := led_arith_mean(frame_rgb, buf_do);
                if
                    cr.led_num/=0 and
                    overlaps
                then
                    -- not the first LED and there's an overlap,
                    -- use the buffered color average
                    tr.buf_di   := led_arith_mean(frame_rgb, ov_buf_do);
                end if;
                if FRAME_HSYNC='1' then
                    tr.buf_wr_en        := '1';
                    tr.inner_coords(X)  := cr.inner_coords(X)+1;
                    if cr.inner_coords(X)=LED_WIDTH-2 then
                        tr.state    := RIGHT_BORDER_PIXEL;
                        if cr.inner_coords(Y)=LED_HEIGHT-1 then
                            tr.state    := LAST_PIXEL;
                        end if;
                    end if;
                end if;
            
            when RIGHT_BORDER_PIXEL =>
                tr.inner_coords(X)  := (others => '0');
                tr.buf_di           := led_arith_mean(frame_rgb, buf_do);
                if FRAME_HSYNC='1' then
                    tr.buf_wr_en    := '1';
                    tr.state        := SIDE_SWITCH;
                    if cr.side=R then
                        tr.state    := LINE_SWITCH;
                    end if;
                end if;
            
            when LINE_SWITCH =>
                tr.side             := L;
                tr.buf_p            := 0;
                tr.inner_coords(Y)  := cr.inner_coords(Y)+1;
                tr.led_pos(X)       := first_leds_pos(L)(X);
                if cr.inner_coords(Y)=LED_HEIGHT-1 then
                    tr.led_num          := cr.led_num+1;
                    tr.inner_coords(Y)  := (others => '0');
                    if overlaps then
                        tr.inner_coords(Y)  := abs_overlap;
                    end if;
                end if;
                tr.state    := LEFT_BORDER_PIXEL;
            
            when LAST_PIXEL =>
                tr.inner_coords(X)  := (others => '0');
                if FRAME_HSYNC='1' then
                    -- give out the LED color
                    tr.led_valid    := '1';
                    tr.led_color    := led_arith_mean(frame_rgb, buf_do);
                    
                    tr.state         := SIDE_SWITCH;
                    if cr.side=R then
                        tr.led_pos(Y)   := cr.led_pos(Y)+uns(LED_STEP);
                        tr.state        := LINE_SWITCH;
                    end if;
                end if;
            
            when SIDE_SWITCH =>
                tr.side         := R;
                tr.buf_p        := 1;
                tr.led_pos(X)   := first_leds_pos(R)(X);
                tr.state        := LEFT_BORDER_PIXEL;
                if cr.led_num=0 and cr.inner_coords(Y)=0 then
                    tr.state    := FIRST_LED_FIRST_PIXEL;
                end if;
            
        end case;
        
        if RST='1' or FRAME_VSYNC='0' then
            tr  := reg_type_def;
        end if;
        
        next_reg    <= tr;
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

