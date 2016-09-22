----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:00:46 07/03/2014
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    HALF_HOR_SCANNER - rtl
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

entity HALF_HOR_SCANNER is
    generic (
        MAX_LED_COUNT   : positive;
        ODD_LEDS        : boolean;
        R_BITS          : positive range 5 to 12;
        G_BITS          : positive range 6 to 12;
        B_BITS          : positive range 5 to 12;
        ACCU_BITS       : positive range 8 to 40
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
        
        ACCU_VALID  : out std_ulogic := '0';
        ACCU_R      : out std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
        ACCU_G      : out std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
        ACCU_B      : out std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
        PIXEL_COUNT : out std_ulogic_vector(31 downto 0) := x"0000_0000"
    );
end HALF_HOR_SCANNER;

architecture rtl of HALF_HOR_SCANNER is
    
    constant RGB_BITS   : natural := R_BITS+G_BITS+B_BITS;
    
    -----------------------------
    --- array element aliases ---
    -----------------------------
    
    constant TOP    : natural := 0;
    constant BOTTOM : natural := 1;
    
    constant X  : natural := 0;
    constant Y  : natural := 1;
    
    
    -------------
    --- types ---
    -------------
    
    -- horizontal buffer: used by the top LED row and the bottom LED row, one frame row
    -- contains one pixel of each LED of one side, so we need a buffer for all those LEDs
    type led_buf_type is
        array(0 to MAX_LED_COUNT/2-1) of
        std_ulogic_vector(3*ACCU_BITS-1 downto 0);
    
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
        side            : natural range TOP to BOTTOM;
        buf_rd_p        : natural range 0 to MAX_LED_COUNT/2;
        buf_wr_p        : natural range 0 to MAX_LED_COUNT/2;
        buf_di          : std_ulogic_vector(3*ACCU_BITS-1 downto 0);
        buf_wr_en       : std_ulogic;
        inner_coords    : inner_coords_type;
        led_pos         : led_pos_type;
        accu_valid      : std_ulogic;
        pixel_counter   : unsigned(ACCU_BITS-9 downto 0);
        pixel_count     : std_ulogic_vector(ACCU_BITS-9 downto 0);
        got_pixel_count : boolean;
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => FIRST_LED_FIRST_PIXEL,
        side            => TOP,
        buf_rd_p        => 0,
        buf_wr_p        => 0,
        buf_di          => (others => '0'),
        buf_wr_en       => '0',
        inner_coords    => (others => x"0000"),
        led_pos         => (others => x"0000"),
        accu_valid      => '0',
        pixel_counter   => (others => '0'),
        pixel_count     => (others => '0'),
        got_pixel_count => false
    );
    
    -- configuration registers
    signal led_count    : std_ulogic_vector(7 downto 0) := x"00";
    signal led_width    : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_height   : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_step     : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_pad      : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_offs     : std_ulogic_vector(15 downto 0) := x"0000";
    signal frame_height : std_ulogic_vector(15 downto 0) := x"0000";
    
    signal first_leds_pos       : leds_pos_type := (others => (others => x"0000"));
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal led_buf              : led_buf_type := (others => (others => '0'));
    signal buf_do               : std_ulogic_vector(3*ACCU_BITS-1 downto 0) := (others => '0');
    signal switch               : boolean := false;
    
    signal half_led_count   : unsigned(6 downto 0) := "0000000";
    signal double_led_step  : unsigned(15 downto 0) := x"0000";
    signal padded_frame_rgb : std_ulogic_vector(3*ACCU_BITS-1 downto 0) := (others => '0');
    
    function led_sum(
        one, two    : std_ulogic_vector(3*ACCU_BITS-1 downto 0)
    ) return std_ulogic_vector is
        variable one_r, one_g, one_b    : std_ulogic_vector(ACCU_BITS-1 downto 0);
        variable two_r, two_g, two_b    : std_ulogic_vector(ACCU_BITS-1 downto 0);
    begin
        -- computes the sum of each R, G and B component
        one_r   := one(3*ACCU_BITS-1 downto 2*ACCU_BITS);
        one_g   := one(2*ACCU_BITS-1 downto   ACCU_BITS);
        one_b   := one(  ACCU_BITS-1 downto           0);
        two_r   := two(3*ACCU_BITS-1 downto 2*ACCU_BITS);
        two_g   := two(2*ACCU_BITS-1 downto   ACCU_BITS);
        two_b   := two(  ACCU_BITS-1 downto           0);
        
        return
            one_r + two_r &
            one_g + two_g &
            one_b + two_b;
    end function;
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    ACCU_VALID  <= cur_reg.accu_valid;
    ACCU_R      <= cur_reg.buf_di(3*ACCU_BITS-1 downto 2*ACCU_BITS);
    ACCU_G      <= cur_reg.buf_di(2*ACCU_BITS-1 downto   ACCU_BITS);
    ACCU_B      <= cur_reg.buf_di(  ACCU_BITS-1 downto           0);
    
    PIXEL_COUNT <= stdulv(int(cur_reg.pixel_count), 32);
    
    -- the position of the first top/bottom LED
    first_leds_pos(TOP)(X)      <= uns(led_offs)+uns(led_step) when ODD_LEDS else uns(led_offs);
    first_leds_pos(TOP)(Y)      <= uns(led_pad);
    first_leds_pos(BOTTOM)(X)   <= uns(led_offs)+uns(led_step) when ODD_LEDS else uns(led_offs);
    first_leds_pos(BOTTOM)(Y)   <= uns(frame_height-led_height-led_pad);
    
    half_led_count  <= uns(led_count(7 downto 1));
    double_led_step <= uns(led_step(14 downto 0) & '0');
    switch          <= cur_reg.buf_rd_p=half_led_count-1 or half_led_count=0;
    
    padded_frame_rgb(3*ACCU_BITS-1 downto 2*ACCU_BITS+R_BITS)   <= (others => '0');
    padded_frame_rgb(2*ACCU_BITS-1 downto   ACCU_BITS+G_BITS)   <= (others => '0');
    padded_frame_rgb(  ACCU_BITS-1 downto             B_BITS)   <= (others => '0');
    
    padded_frame_rgb(2*ACCU_BITS+R_BITS-1 downto 2*ACCU_BITS)   <= FRAME_RGB(     RGB_BITS-1 downto G_BITS+B_BITS);
    padded_frame_rgb(  ACCU_BITS+G_BITS-1 downto   ACCU_BITS)   <= FRAME_RGB(G_BITS+B_BITS-1 downto        B_BITS);
    padded_frame_rgb(            B_BITS-1 downto           0)   <= FRAME_RGB(       B_BITS-1 downto             0);
    
    
    -----------------
    --- processes ---
    -----------------
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "00000" => led_count                   <= CFG_DATA;
                    when "00001" => led_width   (15 downto 8)   <= CFG_DATA;
                    when "00010" => led_width   ( 7 downto 0)   <= CFG_DATA;
                    when "00011" => led_height  (15 downto 8)   <= CFG_DATA;
                    when "00100" => led_height  ( 7 downto 0)   <= CFG_DATA;
                    when "00101" => led_step    (15 downto 8)   <= CFG_DATA;
                    when "00110" => led_step    ( 7 downto 0)   <= CFG_DATA;
                    when "00111" => led_pad     (15 downto 8)   <= CFG_DATA;
                    when "01000" => led_pad     ( 7 downto 0)   <= CFG_DATA;
                    when "01001" => led_offs    (15 downto 8)   <= CFG_DATA;
                    when "01010" => led_offs    ( 7 downto 0)   <= CFG_DATA;
                    when "11000" => frame_height(15 downto 8)   <= CFG_DATA;
                    when "11001" => frame_height( 7 downto 0)   <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    -- ensure block RAM usage
    led_buf_proc : process(CLK)
        alias rd_p  is next_reg.buf_rd_p;
        alias wr_p  is next_reg.buf_wr_p;
        alias di    is next_reg.buf_di;
        alias do    is buf_do;
        alias wr_en is next_reg.buf_wr_en;
    begin
        if rising_edge(CLK) then
            -- write first mode
            if wr_en='1' then
                led_buf(wr_p)   <= di;
                do              <= di;
            else
                do  <= led_buf(rd_p);
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_VSYNC, FRAME_RGB_WR_EN, FRAME_X, FRAME_Y,
        led_width, led_height, double_led_step, padded_frame_rgb, buf_do, first_leds_pos, switch
    )
        alias cr    : reg_type is cur_reg;      -- synchronous registers
        variable r  : reg_type := reg_type_def; -- asynchronous combinational signals
    begin
        r   := cr;
        
        r.accu_valid    := '0';
        r.buf_wr_en     := '0';
        
        case cr.state is
            
            when FIRST_LED_FIRST_PIXEL =>
                r.buf_wr_p          := 0;
                r.led_pos           := first_leds_pos(cr.side);
                r.inner_coords(X)   := x"0001";
                r.inner_coords(Y)   := (others => '0');
                r.buf_di            := padded_frame_rgb;
                r.pixel_counter     := uns(1, ACCU_BITS-8);
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=stdulv(first_leds_pos(cr.side)(X)) and
                    FRAME_Y=stdulv(first_leds_pos(cr.side)(Y))
                then
                    r.buf_wr_en := '1';
                    r.state     := MAIN_PIXEL;
                end if;
            
            when LEFT_BORDER_PIXEL =>
                r.inner_coords(X)   := x"0001";
                r.buf_wr_p          := cr.buf_rd_p;
                r.buf_di            := led_sum(padded_frame_rgb, buf_do);
                if cr.inner_coords(Y)=0 then
                    -- first pixel after side switch
                    r.buf_di    := padded_frame_rgb;
                end if;
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=stdulv(cr.led_pos(X))
                then
                    if switch then
                        r.pixel_counter := cr.pixel_counter+1;
                    end if;
                    
                    r.buf_wr_en := '1';
                    r.state     := MAIN_PIXEL;
                end if;
            
            when MAIN_PIXEL =>
                r.buf_di    := led_sum(padded_frame_rgb, buf_do);
                if FRAME_RGB_WR_EN='1' then
                    r.buf_wr_en         := '1';
                    r.inner_coords(X)   := cr.inner_coords(X)+1;
                    
                    if cr.buf_wr_p=0 then
                        r.pixel_counter := cr.pixel_counter+1;
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
                r.buf_di            := led_sum(padded_frame_rgb, buf_do);
                if FRAME_RGB_WR_EN='1' then
                    r.buf_rd_p      := cr.buf_rd_p+1;
                    r.buf_wr_en     := '1';
                    r.led_pos(X)    := cr.led_pos(X)+double_led_step;
                    r.state         := LEFT_BORDER_PIXEL;
                    
                    if switch then
                        -- finished one line of all LED areas
                        r.state     := LINE_SWITCH;
                    end if;
                    
                    if cr.buf_wr_p=0 then
                        r.pixel_counter := cr.pixel_counter+1;
                    end if;
                end if;
            
            when LINE_SWITCH =>
                r.buf_rd_p          := 0;
                r.inner_coords(Y)   := cr.inner_coords(Y)+1;
                r.led_pos           := first_leds_pos(cr.side);
                r.state             := LEFT_BORDER_PIXEL;
            
            when LAST_PIXEL =>
                r.inner_coords(X)   := x"0000";
                r.buf_di            := led_sum(padded_frame_rgb, buf_do);
                if FRAME_RGB_WR_EN='1' then
                    r.buf_rd_p      := cr.buf_rd_p+1;
                    r.accu_valid    := '1';
                    
                    r.led_pos(X)    := cr.led_pos(X)+double_led_step;
                    r.state         := LEFT_BORDER_PIXEL;
                    
                    if switch then
                        r.state := SIDE_SWITCH;
                    end if;
                    
                    if not cr.got_pixel_count then
                        r.got_pixel_count   := true;
                        r.pixel_count       := stdulv(cr.pixel_counter+1);
                    end if;
                end if;
            
            when SIDE_SWITCH =>
                r.buf_rd_p  := 0;
                r.side      := BOTTOM;
                r.state     := FIRST_LED_FIRST_PIXEL;
            
        end case;
        
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
