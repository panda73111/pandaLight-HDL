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
-- Revision: 0
-- Revision 0.01 - File Created
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

ENTITY LED_COLOR_EXTRACTOR_tb IS
END LED_COLOR_EXTRACTOR_tb;

ARCHITECTURE behavior OF LED_COLOR_EXTRACTOR_tb IS 
    
    constant FRAME_SIZE_BITS : natural := 11;
    constant LED_CNT_BITS    : natural := 7;
    constant LED_SIZE_BITS   : natural := 8;
    constant LED_PAD_BITS    : natural := 5;
    constant LED_OFFS_BITS   : natural := 7;
    constant LED_STEP_BITS   : natural := 7;
    constant R_BITS          : natural range 1 to 12 := 8;
    constant G_BITS          : natural range 1 to 12 := 8;
    constant B_BITS          : natural range 1 to 12 := 8;
    
    -- Inputs
    signal clk, rst : std_ulogic := '0';
    
    signal
        hor_led_cnt,
        ver_led_cnt
        : std_ulogic_vector(LED_CNT_BITS-1 downto 0) := (others => '0');
    
    signal
        hor_led_width,
        hor_led_height,
        ver_led_width,
        ver_led_height
        : std_ulogic_vector(LED_SIZE_BITS-1 downto 0) := (others => '0');
    
    signal
        hor_led_pad,
        ver_led_pad
        : std_ulogic_vector(LED_PAD_BITS-1 downto 0) := (others => '0');
    
    signal
        hor_led_offs,
        ver_led_offs
        : std_ulogic_vector(LED_OFFS_BITS-1 downto 0) := (others => '0');
    
    signal
        
        hor_led_step,
        ver_led_step
        : std_ulogic_vector(LED_STEP_BITS-1 downto 0) := (others => '0');
    
    signal
        frame_vsync,
        frame_hsync
        : std_ulogic := '0';
    
    signal
        frame_width,
        frame_height
        : std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0) := (others => '0');
    
    signal frame_r  : std_ulogic_vector(R_BITS-1 downto 0) := (others => '0');
    signal frame_g  : std_ulogic_vector(G_BITS-1 downto 0) := (others => '0');
    signal frame_b  : std_ulogic_vector(B_BITS-1 downto 0) := (others => '0');

    --Outputs
    signal led_vsync    : std_ulogic := '0';
    signal led_valid    : std_ulogic := '0';
    signal led_num      : std_ulogic_vector(LED_CNT_BITS-1 downto 0) := (others => '0');
    signal led_r        : std_ulogic_vector(R_BITS-1 downto 0) := (others => '0');
    signal led_g        : std_ulogic_vector(G_BITS-1 downto 0) := (others => '0');
    signal led_b        : std_ulogic_vector(B_BITS-1 downto 0) := (others => '0');

    -- Clock period definitions
    constant clk_period : time := 10 ns; -- 100 MHz

BEGIN
    
    test_frame_gen_inst : entity work.test_camera
    generic map (
        FRAME_STEP      => 0,
        FRAME_SIZE_BITS => FRAME_SIZE_BITS,
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK => clk,
        RST => rst,
        
        WIDTH   => frame_width,
        HEIGHT  => frame_height,
        HSYNC   => frame_hsync,
        VSYNC   => frame_vsync,
        R       => frame_r,
        G       => frame_g,
        B       => frame_b
    );
    
    led_ppm_visualizer_inst : entity work.led_ppm_visualizer
    generic map (
        FILENAME_BASE   => "frame",
        FRAMES_TO_SAVE  => 10,
        STOP_SIM        => true,
        FRAME_SIZE_BITS => FRAME_SIZE_BITS,
        LED_CNT_BITS    => LED_CNT_BITS,
        LED_SIZE_BITS   => LED_SIZE_BITS,
        LED_PAD_BITS    => LED_PAD_BITS,
        LED_OFFS_BITS   => LED_OFFS_BITS,
        LED_STEP_BITS   => LED_STEP_BITS,
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK => clk,
        
        HOR_LED_CNT     => hor_led_cnt,
        VER_LED_CNT     => ver_led_cnt,
        
        HOR_LED_WIDTH   => hor_led_width,
        HOR_LED_HEIGHT  => hor_led_height,
        HOR_LED_STEP    => hor_led_step,
        HOR_LED_PAD     => hor_led_pad,
        HOR_LED_OFFS    => hor_led_offs,
        VER_LED_WIDTH   => ver_led_width,
        VER_LED_HEIGHT  => ver_led_height,
        VER_LED_STEP    => ver_led_step,
        VER_LED_PAD     => ver_led_pad,
        VER_LED_OFFS    => ver_led_offs,
        
        FRAME_WIDTH     => frame_width,
        FRAME_HEIGHT    => frame_height,
        
        LED_VSYNC   => led_vsync,
        LED_VALID   => led_valid,
        LED_NUM     => led_num,
        LED_R       => led_r,
        LED_G       => led_g,
        LED_B       => led_b
    );
    
    LED_COLOR_EXTRACTOR_inst : entity work.LED_COLOR_EXTRACTOR
    generic map (
        FRAME_SIZE_BITS => FRAME_SIZE_BITS,
        LED_CNT_BITS    => LED_CNT_BITS,
        LED_SIZE_BITS   => LED_SIZE_BITS,
        LED_PAD_BITS    => LED_PAD_BITS,
        LED_OFFS_BITS   => LED_OFFS_BITS,
        LED_STEP_BITS   => LED_STEP_BITS,
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK => clk,
        RST => rst,
        
        HOR_LED_CNT     => hor_led_cnt,
        VER_LED_CNT     => ver_led_cnt,
        
        HOR_LED_WIDTH   => hor_led_width,
        HOR_LED_HEIGHT  => hor_led_height,
        HOR_LED_STEP    => hor_led_step,
        HOR_LED_PAD     => hor_led_pad,
        HOR_LED_OFFS    => hor_led_offs,
        VER_LED_WIDTH   => ver_led_width,
        VER_LED_HEIGHT  => ver_led_height,
        VER_LED_STEP    => ver_led_step,
        VER_LED_PAD     => ver_led_pad,
        VER_LED_OFFS    => ver_led_offs,
        
        FRAME_VSYNC     => frame_vsync,
        FRAME_HSYNC     => frame_hsync,
        FRAME_WIDTH     => frame_width,
        FRAME_HEIGHT    => frame_height,
        
        FRAME_R => frame_r,
        FRAME_G => frame_g,
        FRAME_B => frame_b,
        
        LED_VSYNC   => led_vsync,
        LED_VALID   => led_valid,
        LED_NUM     => led_num,
        LED_R       => led_r,
        LED_G       => led_g,
        LED_B       => led_b
    );

    -- clock generation
    clk <= not clk after clk_period / 2;
    
    
    -- Stimulus process
    stim_proc: process
    begin
        frame_width     <= stdulv(1280, FRAME_SIZE_BITS);
        frame_height    <= stdulv(720,  FRAME_SIZE_BITS);
        
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait until rising_edge(clk);
        
        hor_led_cnt     <= stdulv(16,   LED_CNT_BITS);
        ver_led_cnt     <= stdulv(9,    LED_CNT_BITS);
        
        -- Test 1: Standard 50 LED configuration, no overlap, no edges
        
        hor_led_width   <= stdulv(60,   LED_SIZE_BITS);
        hor_led_height  <= stdulv(80,   LED_SIZE_BITS);
        hor_led_step    <= stdulv(80,   LED_STEP_BITS);
        hor_led_pad     <= stdulv(5,    LED_PAD_BITS);
        hor_led_offs    <= stdulv(10,   LED_OFFS_BITS);
        ver_led_width   <= stdulv(80,   LED_SIZE_BITS);
        ver_led_height  <= stdulv(60,   LED_SIZE_BITS);
        ver_led_step    <= stdulv(80,   LED_STEP_BITS);
        ver_led_pad     <= stdulv(5,    LED_PAD_BITS);
        ver_led_offs    <= stdulv(10,   LED_OFFS_BITS);
        
        for i in 1 to 5 loop
            wait until rising_edge(clk) and frame_vsync='1';
            wait until rising_edge(clk) and frame_vsync='0';
        end loop;
        
        -- Test 1 finished
        -- Test 2: Standard 50 LED configuration, overlaps, edges
        
        hor_led_width   <= stdulv(160,  LED_SIZE_BITS);
        hor_led_height  <= stdulv(80,   LED_SIZE_BITS);
        hor_led_step    <= stdulv(65,   LED_STEP_BITS);
        hor_led_pad     <= stdulv(5,    LED_PAD_BITS);
        hor_led_offs    <= stdulv(80,   LED_OFFS_BITS);
        ver_led_width   <= stdulv(80,   LED_SIZE_BITS);
        ver_led_height  <= stdulv(160,  LED_SIZE_BITS);
        ver_led_step    <= stdulv(90,   LED_STEP_BITS);
        ver_led_pad     <= stdulv(5,    LED_PAD_BITS);
        ver_led_offs    <= stdulv(39,   LED_OFFS_BITS);
        
        wait;
    end process;

END;
