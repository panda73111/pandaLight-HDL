----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    15:19:05 07/03/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    VER_SCANNER - rtl 
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

entity VER_SCANNER is
    generic (
        ODD_LEDS    : boolean;
        R_BITS      : natural range 1 to 12 := 8;
        G_BITS      : natural range 1 to 12 := 8;
        B_BITS      : natural range 1 to 12 := 8
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
        LED_NUM         : out std_ulogic_vector(7 downto 0) := (others => '0');
        LED_SIDE        : out std_ulogic := '0'
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
    -- contains one row of two LEDs, so we need a buffer for those two
    type led_buf_type is
        array(0 to 1) of
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
        side            : natural range L to R;
        buf_p           : natural range 0 to 1;
        buf_di          : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_wr_en       : std_ulogic;
        inner_coords    : inner_coords_type;
        led_pos         : led_pos_type;
        led_rgb_valid   : std_ulogic;
        led_rgb         : std_ulogic_vector(RGB_BITS-1 downto 0);
        led_num         : std_ulogic_vector(7 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => FIRST_LED_FIRST_PIXEL,
        side            => L,
        buf_p           => 0,
        buf_di          => (others => '0'),
        buf_wr_en       => '0',
        inner_coords    => (others => x"0000"),
        led_pos         => (others => x"0000"),
        led_rgb_valid   => '0',
        led_rgb         => (others => '0'),
        led_num         => x"00"
    );
    
    signal first_leds_pos       : leds_pos_type := (others => (others => x"0000"));
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal led_buf              : led_buf_type := (others => (others => '0'));
    signal buf_do               : std_ulogic_vector(RGB_BITS-1 downto 0) := (others => '0');
    
    -- configuration registers
    signal led_width    : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_height   : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_step     : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_pad      : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_offs     : std_ulogic_vector(15 downto 0) := x"0000";
    signal frame_width  : std_ulogic_vector(15 downto 0) := x"0000";
    
    signal double_led_step  : unsigned(15 downto 0) := x"0000";
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    LED_RGB_VALID   <= cur_reg.led_rgb_valid;
    LED_RGB         <= cur_reg.led_rgb;
    LED_NUM         <= cur_reg.led_num;
    LED_SIDE        <= '0' when cur_reg.side=L else '1';
    
    -- the position of the first left/right LED
    first_leds_pos(L)(X)    <= uns(led_pad);
    first_leds_pos(L)(Y)    <= uns(led_offs)+uns(led_step) when ODD_LEDS else uns(led_offs);
    first_leds_pos(R)(X)    <= uns(frame_width-led_width-led_pad);
    first_leds_pos(R)(Y)    <= uns(led_offs)+uns(led_step) when ODD_LEDS else uns(led_offs);
    
    double_led_step <= led_step(14 downto 0) & '0';
    
    
    -----------------
    --- processes ---
    -----------------
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "01100" => led_width(15 downto 8)      <= CFG_DATA;
                    when "01101" => led_width(7 downto 0)       <= CFG_DATA;
                    when "01110" => led_height(15 downto 8)     <= CFG_DATA;
                    when "01111" => led_height(7 downto 0)      <= CFG_DATA;
                    when "10000" => led_step(15 downto 8)       <= CFG_DATA;
                    when "10001" => led_step(7 downto 0)        <= CFG_DATA;
                    when "10010" => led_pad(15 downto 8)        <= CFG_DATA;
                    when "10011" => led_pad(7 downto 0)         <= CFG_DATA;
                    when "10100" => led_offs(15 downto 8)       <= CFG_DATA;
                    when "10101" => led_offs(7 downto 0)        <= CFG_DATA;
                    when "10110" => frame_width(15 downto 8)    <= CFG_DATA;
                    when "10111" => frame_width(7 downto 0)     <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    -- ensure block RAM usage
    led_buf_proc : process(CLK)
        alias p     is next_reg.buf_p;
        alias di    is next_reg.buf_di;
        alias do    is buf_do;
        alias wr_en is next_reg.buf_wr_en;
    begin
        if rising_edge(CLK) then
            -- write first mode
            if wr_en='1' then
                led_buf(p)      <= di;
                do              <= di;
            else
                do      <= led_buf(p);
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_WIDTH, FRAME_VSYNC, FRAME_RGB_WR_EN, FRAME_X, FRAME_Y,
        LED_WIDTH, LED_HEIGHT, double_led_step, LED_OFFS, FRAME_RGB, buf_do, first_leds_pos
    )
        alias cr        : reg_type is cur_reg;      -- synchronous registers
        variable tr     : reg_type := reg_type_def; -- asynchronous combinational signals
    begin
        tr  := cr;
        
        tr.led_rgb_valid    := '0';
        tr.buf_wr_en        := '0';
        
        case cr.state is
            
            when FIRST_LED_FIRST_PIXEL =>
                tr.led_pos          := first_leds_pos(cr.side);
                tr.inner_coords(X)  := x"0001";
                tr.inner_coords(Y)  := (others => '0');
                tr.buf_di           := FRAME_RGB;
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=stdulv(first_leds_pos(cr.side)(X)) and
                    FRAME_Y=stdulv(first_leds_pos(cr.side)(Y))
                then
                    tr.buf_wr_en    := '1';
                    tr.state        := MAIN_PIXEL;
                end if;
            
            when LEFT_BORDER_PIXEL =>
                tr.inner_coords(X)  := x"0001";
                tr.buf_di           := led_arith_mean(FRAME_RGB, buf_do);
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=stdulv(cr.led_pos(X)) and
                    FRAME_Y>=stdulv(cr.led_pos(Y))
                then
                    tr.buf_wr_en    := '1';
                    tr.state        := MAIN_PIXEL;
                end if;
            
            when MAIN_PIXEL =>
                tr.buf_di   := led_arith_mean(FRAME_RGB, buf_do);
                if FRAME_RGB_WR_EN='1' then
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
                tr.buf_di           := led_arith_mean(FRAME_RGB, buf_do);
                if FRAME_RGB_WR_EN='1' then
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
                tr.state            := LEFT_BORDER_PIXEL;
                if cr.inner_coords(Y)=LED_HEIGHT-1 then
                    tr.led_num          := cr.led_num+1;
                    tr.inner_coords(Y)  := (others => '0');
                end if;
            
            when LAST_PIXEL =>
                tr.inner_coords(X)  := (others => '0');
                if FRAME_RGB_WR_EN='1' then
                    -- give out the LED color
                    tr.led_rgb_valid    := '1';
                    tr.led_rgb          := led_arith_mean(FRAME_RGB, buf_do);
                    
                    tr.state    := SIDE_SWITCH;
                    if cr.side=R then
                        tr.led_pos(Y)   := cr.led_pos(Y)+uns(double_led_step);
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
        
        if RST='1' or FRAME_VSYNC='1' then
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

