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
--
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
    
    type state_type is (INIT, SCAN_TOP, SCAN_BOTTOM);
    
    type reg_type is record
        state               : state_type;
        overlap_buf         : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_rd_p, buf_wr_p  : natural range 0 to (2**LED_CNT_BITS)-1;
        buf_do, buf_di      : std_ulogic_vector(RGB_BITS-1 downto 0);
        buf_wr_en           : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => INIT,
        overlap_buf => (others => '0'),
        buf_rd_p    => 0,
        buf_wr_p    => 0,
        buf_di      => (others => '0'),
        buf_do      => (others => '0'),
        buf_wr_en   => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
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
    
    signal side     : natural range T to B := T;
    signal led_buf  : led_buf_type;
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    -- in case of overlapping LEDs, the position of the next LED's pixel area is needed
    next_inner_coords(X)    <= inner_coords(X)+uns(LED_STEP);
    next_inner_coords(Y)    <= inner_coords(Y);
    
    -- is there any overlap?
    overlaps    <= LED_STEP<LED_WIDTH;
    
    -- the amount of overlapping pixels (in one dimension)
    abs_overlap <= uns(LED_HEIGHT-LED_STEP);
    
    -- point of the first pixel of the first LED on each side (the most top left pixel)
    first_led_pos(X)    <= resize(uns(LED_OFFS), FRAME_SIZE_BITS);
    first_led_pos(Y)    <=
        resize( uns(LED_PAD),                           FRAME_SIZE_BITS) when side=T else
                uns(FRAME_HEIGHT-LED_HEIGHT-LED_PAD);
    
    
    -----------------
    --- processes ---
    -----------------
    
    -- ensure block RAM usage
    led_buf_proc : process(CLK)
        alias rd_p  is cur_reg.buf_rd_p;
        alias wr_p  is cur_reg.buf_rd_p;
        alias di    is cur_reg.buf_di;
        alias do    is cur_reg.buf_do;
        alias wr_en is cur_reg.buf_wr_en;
    begin
        if rising_edge(CLK) then
            -- read first mode
            do  <= led_buf(rd_p);
            if wr_en='1' then
                led_buf(wr_p)   <= di;
            end if;
        end if;
    end process;
    
    stm_proc : process(cur_reg)
        variable
            old_led_color,
            new_led_color
        : std_ulogic_vector(RGB_BITS-1 downto 0);
    begin
        if RST='1' then
            inner_coords    <= (others => (others => '0'));
            led_num_reg     <= (others => '0');
            LED_VALID       <= '0';
            side            <= T;
        elsif rising_edge(CLK) then
            LED_VALID   <= '0';
            
            if led_num_reg=0 then
                led_pos <= first_led_pos;
            end if;
            
            if FRAME_HSYNC='1' then
                if
                    led_num_reg<LED_CNT and
                    FRAME_X>=led_pos(X) and
                    FRAME_X<led_pos(X)+LED_WIDTH and
                    FRAME_Y>=led_pos(Y) and
                    FRAME_Y<led_pos(Y)+LED_HEIGHT
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
                            next_inner_coords(Y)=0 and
                            next_inner_coords(X)=0
                        then
                            -- first pixel of the next (overlapping) LED area
                            led_buf(led_num_p+1)    <= FRAME_R & FRAME_G & FRAME_G;
                        else
                            -- any other pixel of the next (overlapping) LED area
                            old_led_color   := led_buf(led_num_p+1);
                            new_led_color   :=
                                arith_mean(FRAME_R, old_led_color(RGB_BITS-1 downto G_BITS+B_BITS)) &
                                arith_mean(FRAME_G, old_led_color(G_BITS+B_BITS-1 downto B_BITS)) &
                                arith_mean(FRAME_B, old_led_color(B_BITS-1 downto 0));
                            led_buf(led_num_p+1)    <= new_led_color;
                        end if;
                    end if;
                        
                    -- left led x & y increment;
                    -- the LED is changed after one row of pixels is completed
                    inner_coords(X) <= inner_coords(X)+1;
                    if inner_coords(X)=LED_WIDTH-1 or FRAME_X=FRAME_WIDTH-1 then
                        inner_coords(X) <= (others => '0');
                        led_num_reg     <= led_num_reg+1;
                        led_pos(X)      <= uns(led_pos(X)+LED_STEP);
                        if led_num_reg=LED_CNT-1 or frame_x=FRAME_WIDTH-1 then
                            -- frame row chaning, jump to the first LED
                            inner_coords(Y) <= inner_coords(Y)+1;
                            led_num_reg     <= (others => '0');
                        end if;
                        if overlaps and led_num_reg<LED_CNT-1 then
                            inner_coords(X) <= abs_overlap;
                        end if;
                        if inner_coords(Y)=LED_HEIGHT-1 or FRAME_Y=FRAME_HEIGHT-1 then
                            -- this was the last pixel of the LED area
                            led_num_reg <= led_num_reg+1;
                            LED_VALID   <= '1';
                            LED_COLOR   <= led_buf(led_num_p);
                            LED_NUM     <= stdulv(led_num_reg);
                            if side=T then
                                LED_SIDE    <= '0';
                            else
                                LED_SIDE    <= '1';
                            end if;
                            if led_num_reg=LED_CNT-1 then
                                -- this was the last top LED
                                inner_coords(Y) <= (others => '0');
                                side            <= B;
                                led_num_reg     <= (others => '0');
                            end if;
                        end if;
                    end if;
                end if;
            end if;
            
            if FRAME_VSYNC='0' then
                inner_coords    <= (others => (others => '0'));
                led_num_reg     <= (others => '0');
                side            <= T;
            end if;
        end if;
    end process;
    
end rtl;

