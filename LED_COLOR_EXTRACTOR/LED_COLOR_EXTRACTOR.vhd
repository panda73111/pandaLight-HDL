----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:30:22 06/29/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    LED_COLOR_EXTRACTOR - rtl
-- Tool versions: Xilinx ISE 14.7
-- Description:
--   Component that extracts a variable number of averaged pixel groups
--   from an incoming video stream for the purpose of sending these colors
--   to a LED stripe around a TV
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments:
--   All the settings inputs (LED count, area size, padding, step and frame dimensions)
--   should not be changed during a FRAME_VSYNC=HIGH period, as this leads to incorrect
--   LED color data!
--   
--   Generic:
--     FRAME_SIZE_BITS : Number of bits for each dimension of the incoming video frame
--     LED_CNT_BITS    : Number of bits for the number of all LEDs
--     LED_SIZE_BITS   : Number of bits for each dimension of the pixel area per LED
--     LED_OFFS_BITS    : Number of bits for the padding pixel count per side
--     LED_STEP_BITS   : Number of bits for the pixel count LED center to LED center
--     R_BITS          : Number of bits for the 'red' value in both frame and LED data
--     G_BITS          : Number of bits for the 'green' value in both frame and LED data
--     B_BITS          : Number of bits for the 'blue' value in both frame and LED data
--   Port:
--     CLK : clock input
--     RST : active high reset, aborts and resets calculation until released
--     
--     HOR_LED_CNT     : number of LEDs at each top and bottom side of the TV screen
--     HOR_LED_WIDTH   : width of one LED area of each of these horizontal LEDs
--     HOR_LED_HEIGHT  : height of one LED area of each of these horizontal LEDs
--     VER_LED_CNT     : number of LEDs at each left and right side of the TV screen
--     VER_LED_WIDTH   : width of one LED area of each of these vertical LEDs
--     VER_LED_HEIGHT  : height of one LED area of each of these vertical LEDs
--     
--     LED_PAD_TOP_LEFT        : spacing pixel count between left frame edge and top LEDs
--     LED_PAD_TOP_TOP         : spacing pixel count between top frame edge and top LEDs
--     LED_PAD_RIGHT_TOP       : spacing pixel count between top frame edge and right LEDs
--     LED_PAD_RIGHT_RIGHT     : spacing pixel count between right frame edge and right LEDs
--     LED_PAD_BOTTOM_LEFT     : spacing pixel count between left frame edge and bottom LEDs
--     LED_PAD_BOTTOM_BOTTOM   : spacing pixel count between bottom frame edge and bottom LEDs
--     LED_PAD_LEFT_TOP        : spacing pixel count between top frame edge and left LEDs
--     LED_PAD_LEFT_LEFT       : spacing pixel count between left frame edge and left LEDs
--     LED_STEP_TOP            : number of pixels from a top LED to the next one, center to center
--     LED_STEP_RIGHT          : number of pixels from a right LED to the next one, center to center
--     LED_STEP_BOTTOM         : number of pixels from a bottom LED to the next one, center to center
--     LED_STEP_LEFT           : number of pixels from a left LED to the next one, center to center
--     
--     FRAME_VSYNC : active high vertical sync of the incoming frame data
--     FRAME_HSYNC : active high horizontal sync of the incoming frame data
--     
--     FRAME_WIDTH     : the frame width, in pixel
--     FRAME_HEIGHT    : the frame height, in pixel
--     
--     FRAME_R : the 'red' value of the current pixel
--     FRAME_G : the 'green' value of the current pixel
--     FRAME_B : the 'blue' value of the current pixel
--     
--     LED_VALID   : 
--     LED_NUM     : 
--     LED_R       : 
--     LED_G       : 
--     LED_B       : 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity LED_COLOR_EXTRACTOR is
    generic (
        FRAME_SIZE_BITS : natural := 11;
        LED_CNT_BITS    : natural := 7;
        LED_SIZE_BITS   : natural := 7;
        LED_PAD_BITS    : natural := 7;
        LED_STEP_BITS   : natural := 7;
        R_BITS          : natural range 1 to 12 := 8;
        G_BITS          : natural range 1 to 12 := 8;
        B_BITS          : natural range 1 to 12 := 8
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        HOR_LED_CNT     : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        VER_LED_CNT     : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        
        HOR_LED_WIDTH   : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        HOR_LED_HEIGHT  : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        HOR_LED_STEP    : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        HOR_LED_PAD     : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        VER_LED_WIDTH   : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        VER_LED_HEIGHT  : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        VER_LED_STEP    : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        VER_LED_PAD     : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        
        FRAME_VSYNC : in std_ulogic;
        FRAME_HSYNC : in std_ulogic;
        
        FRAME_WIDTH     : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        
        FRAME_R : in std_ulogic_vector(R_BITS-1 downto 0);
        FRAME_G : in std_ulogic_vector(G_BITS-1 downto 0);
        FRAME_B : in std_ulogic_vector(B_BITS-1 downto 0);
        
        LED_VSYNC   : out std_ulogic := '0';
        LED_VALID   : out std_ulogic := '0';
        LED_NUM     : out std_ulogic_vector(LED_CNT_BITS-1 downto 0) := (others => '0');
        LED_R       : out std_ulogic_vector(R_BITS-1 downto 0) := (others => '0');
        LED_G       : out std_ulogic_vector(G_BITS-1 downto 0) := (others => '0');
        LED_B       : out std_ulogic_vector(B_BITS-1 downto 0) := (others => '0')
    );
end LED_COLOR_EXTRACTOR;

architecture rtl of LED_COLOR_EXTRACTOR is
    
    constant RGB_BITS   : natural := R_BITS+G_BITS+B_BITS;
    
    -----------------------------
    --- array element aliases ---
    -----------------------------
    
    constant HOR    : natural := 0;
    constant VER    : natural := 1;
    
    constant T  : natural := 0; -- top
    constant B  : natural := 1; -- bottom
    constant L  : natural := 2; -- right
    constant R  : natural := 3; -- left
    
    constant X  : natural := 0;
    constant Y  : natural := 1;
    
    
    -------------
    --- types ---
    -------------
    
    type leds_num_type is
        array(0 to 1) of
        std_ulogic_vector(LED_CNT_BITS-1 downto 0);
    
    type side_flag_type is
        array(0 to 1) of
        boolean;
    
    type leds_color_type is
        array(0 to 1) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    type leds_output_queue_type is
        array(0 to 1) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    ---------------
    --- signals ---
    ---------------
    
    signal leds_num
        : leds_num_type
        := (others => (others => '0'));
    
    signal
        frame_x,
        frame_y
        : unsigned(FRAME_SIZE_BITS-1 downto 0)
        := (others => '0');
    
    signal leds_queued
        : side_flag_type
        := (others => false);
    
    signal leds_valid
        : std_ulogic_vector(0 to 1)
        := (others => '0');
    
    signal leds_side
        : std_ulogic_vector(0 to 1)
        := (others => '0');
    
    signal leds_color
        : leds_color_type
        := (others => (others => '0'));
    
    signal leds_output_queue
        : leds_output_queue_type
        := (others => (others => '0'));
    
    signal
        rev_hor_led_num,
        rev_ver_led_num
        : std_ulogic_vector(LED_CNT_BITS-1 downto 0);
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    rev_hor_led_num <= HOR_LED_CNT-leds_num(HOR);
    rev_ver_led_num <= VER_LED_CNT-leds_num(VER);
    
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
    
    hor_scanner_inst : entity work.hor_scanner
        generic map (
            FRAME_SIZE_BITS => FRAME_SIZE_BITS,
            LED_CNT_BITS    => LED_CNT_BITS,
            LED_SIZE_BITS   => LED_SIZE_BITS,
            LED_PAD_BITS    => LED_PAD_BITS,
            LED_STEP_BITS   => LED_STEP_BITS,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS
        )
        port map (
            CLK => clk,
            RST => rst,
            
            LED_CNT     => hor_led_cnt,
            LED_WIDTH   => hor_led_width,
            LED_HEIGHT  => hor_led_height,
            LED_STEP    => hor_led_step,
            
            HOR_LED_PAD => hor_led_pad,
            VER_LED_PAD => ver_led_pad,
            
            FRAME_VSYNC => FRAME_VSYNC,
            FRAME_HSYNC => FRAME_HSYNC,
            
            FRAME_X => stdulv(frame_x),
            FRAME_Y => stdulv(frame_y),
            
            FRAME_WIDTH     => FRAME_WIDTH,
            FRAME_HEIGHT    => FRAME_HEIGHT,
            
            FRAME_R => frame_r,
            FRAME_G => frame_g,
            FRAME_B => frame_b,
            
            LED_VALID   => leds_valid(HOR),
            LED_NUM     => leds_num(HOR),
            LED_SIDE    => leds_side(HOR),
            LED_COLOR   => leds_color(HOR)
        );
    
    ver_scanner_inst : entity work.ver_scanner
        generic map (
            FRAME_SIZE_BITS => FRAME_SIZE_BITS,
            LED_CNT_BITS    => LED_CNT_BITS,
            LED_SIZE_BITS   => LED_SIZE_BITS,
            LED_PAD_BITS    => LED_PAD_BITS,
            LED_STEP_BITS   => LED_STEP_BITS,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS
        )
        port map (
            CLK => clk,
            RST => rst,
            
            LED_CNT     => ver_led_cnt,
            LED_WIDTH   => ver_led_width,
            LED_HEIGHT  => ver_led_height,
            LED_STEP    => ver_led_step,
            
            HOR_LED_PAD => hor_led_pad,
            VER_LED_PAD => ver_led_pad,
            
            FRAME_VSYNC => FRAME_VSYNC,
            FRAME_HSYNC => FRAME_HSYNC,
            
            FRAME_X => stdulv(frame_x),
            FRAME_Y => stdulv(frame_y),
            
            FRAME_WIDTH     => FRAME_WIDTH,
            FRAME_HEIGHT    => FRAME_HEIGHT,
            
            FRAME_R => frame_r,
            FRAME_G => frame_g,
            FRAME_B => frame_b,
            
            LED_VALID   => leds_valid(VER),
            LED_NUM     => leds_num(VER),
            LED_SIDE    => leds_side(VER),
            LED_COLOR   => leds_color(VER)
        );
    
    led_output_proc : process(RST, CLK)
    begin
        if RST='1' then
            leds_queued <= (others => false);
            LED_VSYNC   <= '0';
            LED_VALID   <= '0';
        elsif rising_edge(CLK) then
            if FRAME_VSYNC='1' then
                LED_VSYNC   <= '1';
            end if;
            LED_VALID   <= '0';
            for dim in 0 to 1 loop
                if leds_valid(dim) then
                    leds_queued(dim)    <= true;
                end if;
            end loop;
            for side in 0 to 3 loop
                if leds_completed(side) or leds_queued(side) then
                    -- count the LEDs from top left clockwise
                    case side is
                        when T  => LED_NUM  <= leds_num(HOR);
                        when R  => LED_NUM  <= leds_num(HOR)+leds_num(VER);
                        when B  => LED_NUM  <= leds_num(HOR)+leds_num(VER)+rev_hor_led_num;
                        when L  => LED_NUM  <= leds_num(HOR)+leds_num(VER)+rev_hor_led_num+rev_ver_led_num;
                    end case;
                    LED_R               <= leds_output_queue(side)(RGB_BITS-1 downto G_BITS+B_BITS);
                    LED_G               <= leds_output_queue(side)(G_BITS+B_BITS-1 downto B_BITS);
                    LED_B               <= leds_output_queue(side)(B_BITS-1 downto 0);
                    LED_VALID           <= '1';
                    leds_queued(side)   <= false;
                    exit;
                end if;
            end loop;
            if
                FRAME_VSYNC='0' and
                leds_completed=(0 to 3 => false) and
                leds_queued=(0 to 3 => false)
            then
                LED_VSYNC   <= '0';
            end if;
        end if;
    end process;
    
end rtl;