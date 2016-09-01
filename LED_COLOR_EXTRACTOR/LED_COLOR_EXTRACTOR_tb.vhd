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
    
    signal CFG_ADDR     : std_ulogic_vector(4 downto 0) := "00000";
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
        
        type cfg_type is record
            HOR_LED_CNT                                                             : std_ulogic_vector(7 downto 0);
            HOR_LED_WIDTH, HOR_LED_HEIGHT, HOR_LED_STEP, HOR_LED_PAD, HOR_LED_OFFS  : std_ulogic_vector(15 downto 0);
            VER_LED_CNT                                                             : std_ulogic_vector(7 downto 0);
            VER_LED_WIDTH, VER_LED_HEIGHT, VER_LED_STEP, VER_LED_PAD, VER_LED_OFFS  : std_ulogic_vector(15 downto 0);
            FRAME_WIDTH, FRAME_HEIGHT                                               : std_ulogic_vector(15 downto 0);
        end record;
        
        variable cfg    : cfg_type;
        
        procedure write_config (cfg : in cfg_type) is
        begin
            CFG_WR_EN   <= '1';
            RST         <= '1';
            for settings_i in 0 to 255 loop
                CFG_ADDR    <= stdulv(settings_i, 5);
                case settings_i is
                    when 0      =>  CFG_DATA    <= cfg.HOR_LED_CNT;
                    when 1      =>  CFG_DATA    <= cfg.HOR_LED_WIDTH(15 downto 8);
                    when 2      =>  CFG_DATA    <= cfg.HOR_LED_WIDTH(7 downto 0);
                    when 3      =>  CFG_DATA    <= cfg.HOR_LED_HEIGHT(15 downto 8);
                    when 4      =>  CFG_DATA    <= cfg.HOR_LED_HEIGHT(7 downto 0);
                    when 5      =>  CFG_DATA    <= cfg.HOR_LED_STEP(15 downto 8);
                    when 6      =>  CFG_DATA    <= cfg.HOR_LED_STEP(7 downto 0);
                    when 7      =>  CFG_DATA    <= cfg.HOR_LED_PAD(15 downto 8);
                    when 8      =>  CFG_DATA    <= cfg.HOR_LED_PAD(7 downto 0);
                    when 9      =>  CFG_DATA    <= cfg.HOR_LED_OFFS(15 downto 8);
                    when 10     =>  CFG_DATA    <= cfg.HOR_LED_OFFS(7 downto 0);
                    when 11     =>  CFG_DATA    <= cfg.VER_LED_CNT;
                    when 12     =>  CFG_DATA    <= cfg.VER_LED_WIDTH(15 downto 8);
                    when 13     =>  CFG_DATA    <= cfg.VER_LED_WIDTH(7 downto 0);
                    when 14     =>  CFG_DATA    <= cfg.VER_LED_HEIGHT(15 downto 8);
                    when 15     =>  CFG_DATA    <= cfg.VER_LED_HEIGHT(7 downto 0);
                    when 16     =>  CFG_DATA    <= cfg.VER_LED_STEP(15 downto 8);
                    when 17     =>  CFG_DATA    <= cfg.VER_LED_STEP(7 downto 0);
                    when 18     =>  CFG_DATA    <= cfg.VER_LED_PAD(15 downto 8);
                    when 19     =>  CFG_DATA    <= cfg.VER_LED_PAD(7 downto 0);
                    when 20     =>  CFG_DATA    <= cfg.VER_LED_OFFS(15 downto 8);
                    when 21     =>  CFG_DATA    <= cfg.VER_LED_OFFS(7 downto 0);
                    when 22     =>  CFG_DATA    <= cfg.FRAME_WIDTH(15 downto 8);
                    when 23     =>  CFG_DATA    <= cfg.FRAME_WIDTH(7 downto 0);
                    when 24     =>  CFG_DATA    <= cfg.FRAME_HEIGHT(15 downto 8);
                    when 25     =>  CFG_DATA    <= cfg.FRAME_HEIGHT(7 downto 0);
                    when others =>  CFG_DATA    <= x"00";
                end case;
                wait until rising_edge(CLK);
            end loop;
            CFG_WR_EN   <= '0';
            RST         <= '0';
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
            HOR_LED_CNT         => stdulv( 16,  8),
            HOR_LED_WIDTH       => stdulv( 60, 16),
            HOR_LED_HEIGHT      => stdulv( 80, 16),
            HOR_LED_STEP        => stdulv( 80, 16),
            HOR_LED_PAD         => stdulv(  5, 16),
            HOR_LED_OFFS        => stdulv( 10, 16),
            VER_LED_CNT         => stdulv(  9,  8),
            VER_LED_WIDTH       => stdulv( 80, 16),
            VER_LED_HEIGHT      => stdulv( 60, 16),
            VER_LED_STEP        => stdulv( 80, 16),
            VER_LED_PAD         => stdulv(  5, 16),
            VER_LED_OFFS        => stdulv( 10, 16),
            FRAME_WIDTH         => frame_width,
            FRAME_HEIGHT        => frame_height
        );
        write_config(cfg);
        
        for i in 1 to 5 loop
            wait until rising_edge(FRAME_VSYNC);
        end loop;
        
        -- Test 1 finished
        -- Test 2: Standard 50 LED configuration, overlaps, edges
        
        cfg := (
            HOR_LED_CNT         => stdulv( 16,  8),
            HOR_LED_WIDTH       => stdulv(145, 16),
            HOR_LED_HEIGHT      => stdulv( 80, 16),
            HOR_LED_STEP        => stdulv( 65, 16),
            HOR_LED_PAD         => stdulv(  5, 16),
            HOR_LED_OFFS        => stdulv( 80, 16),
            VER_LED_CNT         => stdulv(  9,  8),
            VER_LED_WIDTH       => stdulv( 80, 16),
            VER_LED_HEIGHT      => stdulv(140, 16),
            VER_LED_STEP        => stdulv( 70, 16),
            VER_LED_PAD         => stdulv(  5, 16),
            VER_LED_OFFS        => stdulv( 10, 16),
            FRAME_WIDTH         => frame_width,
            FRAME_HEIGHT        => frame_height
        );
        write_config(cfg);
        
        wait;
    end process;

END;
