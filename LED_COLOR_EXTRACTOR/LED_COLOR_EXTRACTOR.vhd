----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:30:22 06/29/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    LED_COLOR_EXTRACTOR - rtl
-- Tool versions: Xilinx ISE 14.7
-- Description:
--   Component that extracts a variable number of averaged pixel groups
--   from an incoming video stream for the purpose of sending these colours
--   to a LED stripe around a TV
-- Additional Comments:
--   Generic:
--     R_BITS   : (5 to 12) Number of bits for the 'red' value in both frame and LED data
--     G_BITS   : (6 to 12) Number of bits for the 'green' value in both frame and LED data
--     B_BITS   : (5 to 12) Number of bits for the 'blue' value in both frame and LED data
--   Port:
--     CLK : clock input
--     RST : active high reset, aborts and resets calculation until released
--     
--     CFG_ADDR     : address of the configuration register to be written
--     CFG_WR_EN    : active high write enable of the configuration data
--     CFG_DATA     : configuration data to be written
--     
--     FRAME_VSYNC      : positive vsync of the incoming frame data
--     FRAME_RGB_WR_EN  : active high write indication of the incoming frame data
--     FRAME_RGB        : the RGB value of the current pixel
--     
--     LED_VSYNC    : positive vsync of the outgoing LED data
--     LED_VALID    : high while the LED colour components are valid
--     LED_NUM      : number of the current LED, from the first top left LED clockwise
--     LED_RGB      : LED RGB color
--   
--   These configuration registers can only be set while RST is high, using the CFG_* inputs:
--     Except for the LED counts, all values are 16 Bit in size, separated into high and low byte
--   
--    [0] = HOR_LED_CNT      : number of LEDs at each top and bottom side of the TV screen
--    [1] = HOR_LED_WIDTH_H  : width of one LED area of each of these horizontal LEDs
--    [2] = HOR_LED_WIDTH_L
--    [3] = HOR_LED_HEIGHT_H : height of one LED area of each of these horizontal LEDs
--    [4] = HOR_LED_HEIGHT_L
--    [5] = HOR_LED_STEP_H   : pixels between two horizontal LEDs, centre to centre
--    [6] = HOR_LED_STEP_L
--    [7] = HOR_LED_PAD_H    : gap between the top border and the the horizontal LEDs
--    [8] = HOR_LED_PAD_L
--    [9] = HOR_LED_OFFS_H   : gap between the left border and the the first horizontal LED
--   [10] = HOR_LED_OFFS_L
--   [11] = VER_LED_CNT      : number of LEDs at each left and right side of the TV screen
--   [12] = VER_LED_WIDTH_H  : width of one LED area of each of these vertical LEDs
--   [13] = VER_LED_WIDTH_L
--   [14] = VER_LED_HEIGHT_H : height of one LED area of each of these vertical LEDs
--   [15] = VER_LED_HEIGHT_L
--   [16] = VER_LED_STEP_H   : pixels between two vertical LEDs, centre to centre
--   [17] = VER_LED_STEP_L
--   [18] = VER_LED_PAD_H    : gap between the left border and the the vertical LEDs
--   [19] = VER_LED_PAD_L
--   [20] = VER_LED_OFFS_H   : gap between the top border and the the first vertical LED
--   [21] = VER_LED_OFFS_L
--   [22] = FRAME_WIDTH_H    : frame width in pixels
--   [23] = FRAME_WIDTH_L
--   [24] = FRAME_HEIGHT_H   : frame height in pixels
--   [25] = FRAME_HEIGHT_L
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity LED_COLOR_EXTRACTOR is
    generic (
        MAX_LED_COUNT   : positive;
        R_BITS          : positive range 5 to 12 := 8;
        G_BITS          : positive range 6 to 12 := 8;
        B_BITS          : positive range 5 to 12 := 8;
        ACCU_BITS       : positive range 8 to 40 := 40
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
        
        LED_VSYNC       : out std_ulogic := '0';
        LED_NUM         : out std_ulogic_vector(7 downto 0) := (others => '0');
        LED_RGB_VALID   : out std_ulogic := '0';
        LED_RGB         : out std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0')
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
        std_ulogic_vector(7 downto 0);
    
    type leds_rgb_type is
        array(0 to 1) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    
    ---------------
    --- signals ---
    ---------------
    
    signal leds_num         : leds_num_type := (others => (others => '0'));
    signal frame_x, frame_y : unsigned(15 downto 0) := (others => '0');
    signal leds_rgb_valid   : std_ulogic_vector(0 to 1) := (others => '0');
    signal leds_side        : std_ulogic_vector(0 to 1) := (others => '0');
    signal leds_rgb         : leds_rgb_type := (others => (others => '0'));
    signal ver_queued       : boolean := false;
    
    signal
        rev_hor_led_num,
        rev_ver_led_num
        : std_ulogic_vector(7 downto 0);
    
    -- configuration registers
    signal hor_led_cnt  : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_cnt  : std_ulogic_vector(7 downto 0) := x"00";
    
    signal frame_width  : std_ulogic_vector(15 downto 0) := x"0000";
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    rev_hor_led_num <= hor_led_cnt-leds_num(HOR)-1;
    rev_ver_led_num <= ver_led_cnt-leds_num(VER)-1;
    
    
    -----------------
    --- processes ---
    -----------------
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "00000" => hor_led_cnt                 <= CFG_DATA;
                    when "01011" => ver_led_cnt                 <= CFG_DATA;
                    when "10110" => frame_width(15 downto 8)    <= CFG_DATA;
                    when "10111" => frame_width(7 downto 0)     <= CFG_DATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    pixel_cnt_proc : process(RST, CLK)
    begin
        if RST='1' then
            frame_x <= (others => '0');
            frame_y <= (others => '0');
        elsif rising_edge(CLK) then
            if FRAME_VSYNC='1' then
                frame_x <= (others => '0');
                frame_y <= (others => '0');
            end if;
            if FRAME_RGB_WR_EN='1' then
                frame_x <= frame_x+1;
                if frame_x=frame_width-1 then
                    frame_x <= (others => '0');
                    frame_y <= frame_y+1;
                end if;
            end if;
        end if;
    end process;
    
    HOR_SCANNER_inst : entity work.hor_scanner
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS,
            ACCU_BITS       => ACCU_BITS
        )
        port map (
            CLK => clk,
            RST => rst,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            FRAME_VSYNC     => FRAME_VSYNC,
            FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
            FRAME_RGB       => FRAME_RGB,
            
            FRAME_X => stdulv(frame_x),
            FRAME_Y => stdulv(frame_y),
            
            LED_RGB_VALID   => leds_rgb_valid(HOR),
            LED_RGB         => leds_rgb(HOR),
            LED_NUM         => leds_num(HOR),
            LED_SIDE        => leds_side(HOR)
        );
    
    VER_SCANNER_inst : entity work.ver_scanner
        generic map (
            R_BITS      => R_BITS,
            G_BITS      => G_BITS,
            B_BITS      => B_BITS,
            ACCU_BITS   => ACCU_BITS
        )
        port map (
            CLK => clk,
            RST => rst,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            FRAME_VSYNC     => FRAME_VSYNC,
            FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
            FRAME_RGB       => FRAME_RGB,
            
            FRAME_X => stdulv(frame_x),
            FRAME_Y => stdulv(frame_y),
            
            LED_RGB_VALID   => leds_rgb_valid(VER),
            LED_RGB         => leds_rgb(VER),
            LED_NUM         => leds_num(VER),
            LED_SIDE        => leds_side(VER)
        );
    
    led_output_proc : process(RST, CLK)
    begin
        if RST='1' then
            ver_queued      <= false;
            LED_VSYNC       <= '0';
            LED_RGB_VALID   <= '0';
        elsif rising_edge(CLK) then
            if FRAME_VSYNC='0' then
                LED_VSYNC   <= '0';
            end if;
            LED_RGB_VALID   <= '0';
            if leds_rgb_valid(VER)='1' then
                -- if two edge LEDs are completed at the same time,
                -- queue the vertical one
                ver_queued  <= true;
            end if;
            for dim in HOR to VER loop
                if leds_rgb_valid(dim)='1' or ver_queued then
                    -- count the LEDs from top left clockwise
                    if dim=HOR then
                        if leds_side(dim)='0' then
                            -- top LED
                            LED_NUM <= leds_num(HOR);
                        else
                            -- bottom LED
                            LED_NUM  <= hor_led_cnt+ver_led_cnt+rev_hor_led_num;
                        end if;
                    else
                        if leds_side(dim)='0' then
                            -- left LED
                            LED_NUM <= hor_led_cnt+ver_led_cnt+hor_led_cnt+rev_ver_led_num;
                        else
                            -- right LED
                            LED_NUM <= hor_led_cnt+leds_num(VER);
                        end if;
                    end if;
                    LED_RGB         <= leds_rgb(dim)(RGB_BITS-1 downto 0);
                    LED_RGB_VALID   <= '1';
                    if dim=VER then
                        ver_queued  <= false;
                    end if;
                    exit;
                end if;
            end loop;
            if
                FRAME_VSYNC='1' and
                leds_rgb_valid="00" and
                not ver_queued
            then
                LED_VSYNC   <= '1';
            end if;
        end if;
    end process;
    
end rtl;