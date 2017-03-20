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
--    [0] = HOR_LED_COUNT    : number of LEDs at each top and bottom side of the TV screen
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
--   [11] = VER_LED_COUNT    : number of LEDs at each left and right side of the TV screen
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
        DIM_BITS        : positive range 9 to 16 := 11;
        ACCU_BITS       : positive range 8 to 40 := 30
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CFG_CLK     : in std_ulogic;
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
    
    constant X  : natural := 0;
    constant Y  : natural := 1;
    
    
    -------------
    --- types ---
    -------------
    
    type led_num_2_type is
        array(0 to 1) of
        std_ulogic_vector(7 downto 0);
    
    type led_rgb_2_type is
        array(0 to 1) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    type accu_channel_2_type is
        array(0 to 1) of
        std_ulogic_vector(ACCU_BITS-1 downto 0);
    
    type pixel_count_2_type is
        array(0 to 1) of
        std_ulogic_vector(2*DIM_BITS-1 downto 0);
    
    
    ---------------
    --- signals ---
    ---------------
    
    signal accu_r_2         : accu_channel_2_type := (others => (others => '0'));
    signal accu_g_2         : accu_channel_2_type := (others => (others => '0'));
    signal accu_b_2         : accu_channel_2_type := (others => (others => '0'));
    signal pixel_count_2    : pixel_count_2_type := (others => (others => '0'));
    
    signal accu_wr_en   : std_ulogic := '0';
    signal accu_r       : std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
    signal accu_g       : std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
    signal accu_b       : std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
    
    signal queue_led_num_in     : std_ulogic_vector(7 downto 0) := x"00";
    signal queue_led_num_out    : std_ulogic_vector(7 downto 0) := x"00";
    signal queue_dimension_in   : std_ulogic := '0';
    signal queue_dimension_out  : std_ulogic := '0';
    signal queue_side_in        : std_ulogic := '0';
    signal queue_side_out       : std_ulogic := '0';
    
    signal queue_led_rgb_valid  : std_ulogic := '0';
    signal queue_led_rgb        : std_ulogic_vector(RGB_BITS-1 downto 0) := (others => '0');
    
    signal led_num_2        : led_num_2_type := (others => (others => '0'));
    signal frame_x          : unsigned(DIM_BITS-1 downto 0) := (others => '0');
    signal frame_y          : unsigned(DIM_BITS-1 downto 0) := (others => '0');
    signal led_rgb_valid_2  : std_ulogic_vector(0 to 1) := (others => '0');
    signal led_side_2       : std_ulogic_vector(0 to 1) := (others => '0');
    signal led_rgb_2        : led_rgb_2_type := (others => (others => '0'));
    signal ver_queued       : boolean := false;
    
    -- configuration registers
    signal hor_led_count    : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_count    : std_ulogic_vector(7 downto 0) := x"00";
    
    signal frame_width  : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
begin
    
    -----------------
    --- processes ---
    -----------------
    
    cfg_proc : process(CFG_CLK)
    begin
        if rising_edge(CFG_CLK) then
            if RST='1' and CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "00000" => hor_led_count                       <= CFG_DATA;
                    when "01011" => ver_led_count                       <= CFG_DATA;
                    when "10110" => frame_width(DIM_BITS-1 downto 8)    <= CFG_DATA(DIM_BITS-9 downto 0);
                    when "10111" => frame_width(         7 downto 0)    <= CFG_DATA;
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
    
    scanner_mux_proc : process(RST, CLK)
    begin
        if RST='1' then
            accu_wr_en  <= '0';
        elsif rising_edge(CLK) then
            accu_wr_en          <= '0';
            queue_dimension_in  <= '0';
            
            for dim in HOR to VER loop
                accu_wr_en          <= accus_valid(dim);
                accu_r              <= accu_r_2(dim);
                accu_g              <= accu_g_2(dim);
                accu_b              <= accu_b_2(dim);
                pixel_count         <= pixel_count_2(dim);
                queue_led_num_in    <= led_num_2(dim)
                queue_side_in       <= led_side_2(dim);
                
                if dim=VER then
                    queue_dimension_in  <= '1';
                end if;
                
                exit when accus_valid(dim)='1';
            end loop;
        end if;
    end process;
    
    LED_OUT_QUEUE_inst : entity work.LED_OUT_QUEUE
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS,
            DIM_BITS        => DIM_BITS,
            ACCU_BITS       => ACCU_BITS
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            WR_EN       => accu_wr_en,
            ACCU_R      => accu_r,
            ACCU_G      => accu_g,
            ACCU_B      => accu_b,
            PIXEL_COUNT => pixel_count,
            
            LED_NUM_IN      => queue_led_num_in,
            DIMENSION_IN    => queue_dimension_in,
            SIDE_IN         => queue_side_in,
            
            LED_RGB_VALID   => queue_led_rgb_valid,
            LED_RGB         => queue_led_rgb,
            
            LED_NUM_OUT     => queue_led_num_out,
            DIMENSION_OUT   => queue_dimension_out,
            SIDE_OUT        => queue_side_out
        );
    
    HOR_SCANNER_inst : entity work.HOR_SCANNER
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS,
            DIM_BITS        => DIM_BITS,
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
            
            ACCU_VALID  => accus_valid(HOR),
            ACCU_R      => accu_r_2(HOR),
            ACCU_G      => accu_g_2(HOR),
            ACCU_B      => accu_b_2(HOR),
            PIXEL_COUNT => pixel_count_2(HOR),
            
            LED_NUM     => led_num_2(HOR),
            LED_SIDE    => led_side_2(HOR)
        );
    
    VER_SCANNER_inst : entity work.VER_SCANNER
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS,
            DIM_BITS        => DIM_BITS,
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
            
            ACCU_VALID  => accus_valid(VER),
            ACCU_R      => accu_r_2(VER),
            ACCU_G      => accu_g_2(VER),
            ACCU_B      => accu_b_2(VER),
            PIXEL_COUNT => pixel_count_2(VER),
            
            LED_NUM     => led_num_2(VER),
            LED_SIDE    => led_side_2(VER)
        );
    
    led_output_proc : process(RST, CLK)
        variable double_hor_led_count   : std_ulogic_vector(7 downto 0);
        variable rev_hor_led_num        : std_ulogic_vector(7 downto 0);
        variable rev_ver_led_num        : std_ulogic_vector(7 downto 0);
    begin
        if RST='1' then
            LED_VSYNC       <= '0';
            LED_RGB_VALID   <= '0';
        elsif rising_edge(CLK) then
            if FRAME_VSYNC='0' then
                LED_VSYNC   <= '0';
            end if;
            
            LED_RGB_VALID   <= '0';
            rev_hor_led_num := hor_led_count-queue_led_num_out-1;
            rev_ver_led_num := ver_led_count-queue_led_num_out-1;
            
            double_hor_led_count    := hor_led_count(6 downto 0) & '0';
                
                if queue_led_rgb_valid='1' then
                
                -- count the LEDs from top left clockwise
                if queue_dimension_out=HOR then
                    if queue_side_out='0' then
                        -- top LED
                        LED_NUM <= queue_led_num_out;
                    else
                        -- bottom LED
                        LED_NUM  <= hor_led_count+ver_led_count+rev_hor_led_num;
                    end if;
                else
                    if queue_side_out='0' then
                        -- left LED
                        LED_NUM <= double_hor_led_count+ver_led_count+rev_ver_led_num;
                    else
                        -- right LED
                        LED_NUM <= hor_led_count+queue_led_num_out;
                    end if;
                end if;
                
                LED_RGB         <= queue_led_rgb;
                LED_RGB_VALID   <= '1';
                
            end if;
            
            if
                FRAME_VSYNC='1' and
                led_rgb_valid_2="00"
            then
                LED_VSYNC   <= '1';
            end if;
        end if;
    end process;
    
end rtl;