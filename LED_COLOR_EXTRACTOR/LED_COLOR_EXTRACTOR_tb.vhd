--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   08:45:27 07/02/2014
-- Module Name:   LED_COLOR_EXTRACTOR_tb
-- Project Name:  LED_COLOR_EXTRACTOR
-- Tool versions: Xilinx ISE 14.7
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: LED_COLOR_EXTRACTOR
-- 
-- Additional Comments:
--
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;
use work.txt_util.all;
use work.video_profiles.all;

ENTITY LED_COLOR_EXTRACTOR_tb IS
    generic (
        R_BITS  : natural range 1 to 12 := 8;
        G_BITS  : natural range 1 to 12 := 8;
        B_BITS  : natural range 1 to 12 := 8
    );
END LED_COLOR_EXTRACTOR_tb;

ARCHITECTURE behavior OF LED_COLOR_EXTRACTOR_tb IS 
    
    -- Inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal CFG_ADDR     : std_ulogic_vector(3 downto 0) := "0000";
    signal CFG_WR_EN    : std_ulogic := '0';
    signal CFG_DATA     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal FRAME_VSYNC      : std_ulogic := '0';
    signal FRAME_RGB_WR_EN  : std_ulogic := '0';
    signal FRAME_RGB        : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');

    --Outputs
    signal LED_VSYNC        : std_ulogic := '0';
    signal LED_RGB_VALID    : std_ulogic := '0';
    signal LED_NUM          : std_ulogic_vector(7 downto 0) := (others => '0');
    signal LED_RGB          : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');


    -- Clock period definitions
    constant G_CLK_PERIOD       : time := 10 ns; -- 100 MHz
    constant G_CLK_PERIOD_REAL  : real := real(G_CLK_PERIOD / 1 ps) / real(1 ns / 1 ps);
    
    signal g_clk            : std_ulogic := '0';
    signal rst_extr         : std_ulogic := '0';
    signal pix_clk          : std_ulogic := '0';
    signal pix_clk_locked   : std_ulogic := '0';
    
    signal frame_width, frame_height    : std_ulogic_vector(15 downto 0) := x"0000";
    
    signal vp       : video_profile_type;
    signal profile  : std_ulogic_vector(log2(VIDEO_PROFILE_COUNT)-1 downto 0) := (others => '0');
    
BEGIN
    
    CLK         <= pix_clk;
    rst_extr    <= RST or not pix_clk_locked;
    
    vp  <= VIDEO_PROFILES(nat(profile));
    
    frame_width     <= stdulv( vp.width, 16);
    frame_height    <= stdulv(vp.height, 16);
    
    TEST_FRAME_GEN_inst : entity work.TEST_FRAME_GEN
    generic map (
        CLK_IN_PERIOD   => G_CLK_PERIOD_REAL,
        FRAME_STEP      => 0,
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK_IN  => g_clk,
        RST     => '0',
        
        PROFILE => profile,
        
        CLK_OUT         => pix_clk,
        CLK_OUT_LOCKED  => pix_clk_locked,
        
        POSITIVE_VSYNC  => frame_vsync,
        
        RGB_ENABLE  => FRAME_RGB_WR_EN,
        RGB         => FRAME_RGB
    );
    
    led_ppm_visualizer_inst : entity work.led_ppm_visualizer
    generic map (
        FILENAME_BASE   => "frame",
        FRAMES_TO_SAVE  => 10,
        STOP_SIM        => true,
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK => CLK,
        RST => rst_extr,
        
        CFG_ADDR    => CFG_ADDR,
        CFG_WR_EN   => CFG_WR_EN,
        CFG_DATA    => CFG_DATA,
        
        FRAME_VSYNC     => FRAME_VSYNC,
        FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
        FRAME_RGB       => FRAME_RGB,
        
        LED_VSYNC       => LED_VSYNC,
        LED_RGB_VALID   => LED_RGB_VALID,
        LED_RGB         => LED_RGB,
        LED_NUM         => LED_NUM
    );
    
    LED_COLOR_EXTRACTOR_inst : entity work.LED_COLOR_EXTRACTOR
    generic map (
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK => CLK,
        RST => rst_extr,
        
        CFG_ADDR    => CFG_ADDR,
        CFG_WR_EN   => CFG_WR_EN,
        CFG_DATA    => CFG_DATA,
        
        FRAME_VSYNC     => FRAME_VSYNC,
        FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
        FRAME_RGB       => FRAME_RGB,
        
        LED_VSYNC       => LED_VSYNC,
        LED_RGB_VALID   => LED_RGB_VALID,
        LED_RGB         => LED_RGB,
        LED_NUM         => LED_NUM
    );

    -- clock generation
    g_clk   <= not g_clk after G_CLK_PERIOD / 2;
    
    
    -- Stimulus process
    stim_proc: process
        
        type cfg_type is
            array(0 to 15) of
            std_ulogic_vector(7 downto 0);
        
        variable cfg    : cfg_type;
        
        procedure write_config (cfg : in cfg_type) is
        begin
            rst         <= '1';
            cfg_wr_en   <= '1';
            for i in cfg_type'range loop
                cfg_addr    <= stdulv(i, 4);
                cfg_data    <= cfg(i);
                wait until rising_edge(CLK);
            end loop;
            rst         <= '0';
            cfg_wr_en   <= '0';
            wait until rising_edge(CLK);
        end procedure;
        
    begin
        
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 200 ns;
        rst <= '0';
        wait until rising_edge(pix_clk_locked);
        
        profile <= stdulv(VIDEO_PROFILE_1280_720p_60, profile'length);
        wait until rising_edge(pix_clk_locked);
        
        wait until rising_edge(FRAME_VSYNC);
        
        -- Test 1: Standard 50 LED configuration, no overlap, no edges
        
        cfg := (
            stdulv(16,   8), -- hor_led_cnt
            stdulv(60,   8), -- hor_led_width
            stdulv(80,   8), -- hor_led_height
            stdulv(80,   8), -- hor_led_step
            stdulv(5,    8), -- hor_led_pad
            stdulv(10,   8), -- hor_led_offs
            stdulv(9,    8), -- ver_led_cnt
            stdulv(80,   8), -- ver_led_width
            stdulv(60,   8), -- ver_led_height
            stdulv(80,   8), -- ver_led_step
            stdulv(5,    8), -- ver_led_pad
            stdulv(10,   8), -- ver_led_offs
            frame_width (15 downto 8),
            frame_width ( 7 downto 0),
            frame_height(15 downto 8),
            frame_height( 7 downto 0)
            );
        write_config(cfg);
        
        for i in 1 to 5 loop
            wait until rising_edge(FRAME_VSYNC);
        end loop;
        
        -- Test 1 finished
        -- Test 2: Standard 50 LED configuration, overlaps, edges
        
        cfg := (
            stdulv(16,   8), -- hor_led_cnt
            stdulv(145,  8), -- hor_led_width
            stdulv(80,   8), -- hor_led_height
            stdulv(65,   8), -- hor_led_step
            stdulv(5,    8), -- hor_led_pad
            stdulv(80,   8), -- hor_led_offs
            stdulv(9,    8), -- ver_led_cnt
            stdulv(80,   8), -- ver_led_width
            stdulv(140,  8), -- ver_led_height
            stdulv(70,   8), -- ver_led_step
            stdulv(5,    8), -- ver_led_pad
            stdulv(10,   8), -- ver_led_offs
            frame_width (15 downto 8),
            frame_width ( 7 downto 0),
            frame_height(15 downto 8),
            frame_height( 7 downto 0)
            );
        write_config(cfg);
        
        wait;
    end process;

END;
