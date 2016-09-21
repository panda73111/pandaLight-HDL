----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    15:19:05 07/03/2014
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    HALF_VER_SCANNER - rtl
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

entity HALF_VER_SCANNER is
    generic (
        ODD_LEDS    : boolean;
        R_BITS      : positive range 5 to 12;
        G_BITS      : positive range 6 to 12;
        B_BITS      : positive range 5 to 12;
        ACCU_BITS   : positive range 8 to 40
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
end HALF_VER_SCANNER;

architecture rtl of HALF_VER_SCANNER is
    
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
        side            : natural range L to R;
        buf_p           : natural range 0 to 1;
        buf_di          : std_ulogic_vector(3*ACCU_BITS-1 downto 0);
        buf_wr_en       : std_ulogic;
        inner_coords    : inner_coords_type;
        led_pos         : led_pos_type;
        accu_valid      : std_ulogic;
        pixel_counter   : unsigned(ACCU_BITS-9 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => FIRST_LED_FIRST_PIXEL,
        side            => L,
        buf_p           => 0,
        buf_di          => (others => '0'),
        buf_wr_en       => '0',
        inner_coords    => (others => x"0000"),
        led_pos         => (others => x"0000"),
        accu_valid      => '0',
        pixel_counter   => (others => '0')
    );
    
    -- configuration registers
    signal led_width    : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_height   : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_step     : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_pad      : std_ulogic_vector(15 downto 0) := x"0000";
    signal led_offs     : std_ulogic_vector(15 downto 0) := x"0000";
    signal frame_width  : std_ulogic_vector(15 downto 0) := x"0000";
    
    signal first_leds_pos       : leds_pos_type := (others => (others => x"0000"));
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal led_buf              : led_buf_type := (others => (others => '0'));
    signal buf_do               : std_ulogic_vector(3*ACCU_BITS-1 downto 0) := (others => '0');
    
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
    ACCU_R      <= buf_do(3*ACCU_BITS-1 downto 2*ACCU_BITS);
    ACCU_G      <= buf_do(2*ACCU_BITS-1 downto   ACCU_BITS);
    ACCU_B      <= buf_do(  ACCU_BITS-1 downto           0);
    
    PIXEL_COUNT <= stdulv(int(cur_reg.pixel_counter), 32);
    
    -- the position of the first left/right LED
    first_leds_pos(L)(X)    <= uns(led_pad);
    first_leds_pos(L)(Y)    <= uns(led_offs)+uns(led_step) when ODD_LEDS else uns(led_offs);
    first_leds_pos(R)(X)    <= uns(frame_width-led_width-led_pad);
    first_leds_pos(R)(Y)    <= uns(led_offs)+uns(led_step) when ODD_LEDS else uns(led_offs);
    
    double_led_step <= uns(led_step(14 downto 0) & '0');
    
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
                led_buf(p)  <= di;
                do          <= di;
            else
                do  <= led_buf(p);
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, FRAME_WIDTH, FRAME_VSYNC, FRAME_RGB_WR_EN, FRAME_X, FRAME_Y,
        LED_WIDTH, LED_HEIGHT, double_led_step, LED_OFFS, padded_frame_rgb, buf_do, first_leds_pos
    )
        alias cr        : reg_type is cur_reg;      -- synchronous registers
        variable tr     : reg_type := reg_type_def; -- asynchronous combinational signals
    begin
        tr  := cr;
        
        tr.accu_valid   := '0';
        tr.buf_wr_en    := '0';
        
        case cr.state is
            
            when FIRST_LED_FIRST_PIXEL =>
                tr.led_pos          := first_leds_pos(cr.side);
                tr.inner_coords(X)  := x"0001";
                tr.inner_coords(Y)  := (others => '0');
                tr.buf_di           := padded_frame_rgb;
                tr.pixel_counter    := uns(1, ACCU_BITS-8);
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
                tr.buf_di           := led_sum(padded_frame_rgb, buf_do);
                if
                    FRAME_RGB_WR_EN='1' and
                    FRAME_X=stdulv(cr.led_pos(X)) and
                    FRAME_Y>=stdulv(cr.led_pos(Y))
                then
                    if cr.buf_p=0 then
                        tr.pixel_counter    := cr.pixel_counter+1;
                    end if;
                    
                    tr.buf_wr_en    := '1';
                    tr.state        := MAIN_PIXEL;
                end if;
            
            when MAIN_PIXEL =>
                tr.buf_di   := led_sum(padded_frame_rgb, buf_do);
                if FRAME_RGB_WR_EN='1' then
                    tr.buf_wr_en        := '1';
                    tr.inner_coords(X)  := cr.inner_coords(X)+1;
                    
                    if cr.buf_p=0 then
                        tr.pixel_counter    := cr.pixel_counter+1;
                    end if;
                    
                    if cr.inner_coords(X)=LED_WIDTH-2 then
                        tr.state    := RIGHT_BORDER_PIXEL;
                        if cr.inner_coords(Y)=LED_HEIGHT-1 then
                            tr.state    := LAST_PIXEL;
                        end if;
                    end if;
                end if;
            
            when RIGHT_BORDER_PIXEL =>
                tr.inner_coords(X)  := (others => '0');
                tr.buf_di           := led_sum(padded_frame_rgb, buf_do);
                if FRAME_RGB_WR_EN='1' then
                    if cr.buf_p=0 then
                        tr.pixel_counter    := cr.pixel_counter+1;
                    end if;
                    
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
                    tr.inner_coords(Y)  := (others => '0');
                end if;
            
            when LAST_PIXEL =>
                tr.inner_coords(X)  := (others => '0');
                tr.buf_di           := led_sum(padded_frame_rgb, buf_do);
                if FRAME_RGB_WR_EN='1' then
                    tr.buf_wr_en    := '1';
                    tr.accu_valid   := '1';
                    
                    if cr.buf_p=0 then
                        tr.pixel_counter    := cr.pixel_counter+1;
                    end if;
                    
                    tr.state    := SIDE_SWITCH;
                    if cr.side=R then
                        tr.led_pos(Y)   := cr.led_pos(Y)+double_led_step;
                        tr.state        := LINE_SWITCH;
                    end if;
                end if;
            
            when SIDE_SWITCH =>
                tr.side         := R;
                tr.buf_p        := 1;
                tr.led_pos(X)   := first_leds_pos(R)(X);
                tr.state        := LEFT_BORDER_PIXEL;
            
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
