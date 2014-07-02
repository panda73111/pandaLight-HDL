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

    -- Inputs
    signal clk  : std_ulogic := '0';
    signal rst  : std_ulogic := '0';
    
    signal hor_led_cnt      : std_ulogic_vector(5 downto 0) := (others => '0');
    signal hor_led_width    : std_ulogic_vector(7 downto 0) := (others => '0');
    signal hor_led_height   : std_ulogic_vector(7 downto 0) := (others => '0');
    signal ver_led_cnt      : std_ulogic_vector(5 downto 0) := (others => '0');
    signal ver_led_width    : std_ulogic_vector(7 downto 0) := (others => '0');
    signal ver_led_height   : std_ulogic_vector(7 downto 0) := (others => '0');
    
    signal led_pad_top_left         : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_pad_top_top          : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_pad_right_top        : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_pad_right_right      : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_pad_bottom_left      : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_pad_bottom_bottom    : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_pad_left_top         : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_pad_left_left        : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_step_top             : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_step_right           : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_step_bottom          : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_step_left            : std_ulogic_vector(7 downto 0) := (others => '0');
    
    signal frame_vsync  : std_ulogic := '0';
    signal frame_hsync  : std_ulogic := '0';
    signal frame_width  : std_ulogic_vector(10 downto 0) := (others => '0');
    signal frame_height : std_ulogic_vector(10 downto 0) := (others => '0');
    
    signal frame_r  : std_ulogic_vector(7 downto 0) := (others => '0');
    signal frame_g  : std_ulogic_vector(7 downto 0) := (others => '0');
    signal frame_b  : std_ulogic_vector(7 downto 0) := (others => '0');

    --Outputs
    signal led_valid    : std_ulogic;
    signal led_num      : std_ulogic_vector(5 downto 0);
    signal led_r        : std_ulogic_vector(7 downto 0);
    signal led_g        : std_ulogic_vector(7 downto 0);
    signal led_b        : std_ulogic_vector(7 downto 0);

    -- Clock period definitions
    constant clk_period : time := 10 ns; -- 100 MHz

BEGIN
    
    test_camera_inst : entity work.test_camera
    generic map (
        FRAME_STEP  => 0
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
    
    LED_COLOR_EXTRACTOR_inst : entity work.LED_COLOR_EXTRACTOR
    port map (
        CLK => clk,
        RST => rst,
        
        HOR_LED_CNT     => hor_led_cnt,
        HOR_LED_WIDTH   => hor_led_width,
        HOR_LED_HEIGHT  => hor_led_height,
        VER_LED_CNT     => ver_led_cnt,
        VER_LED_WIDTH   => ver_led_width,
        VER_LED_HEIGHT  => ver_led_height,
        
        LED_PAD_TOP_LEFT        => led_pad_top_left,
        LED_PAD_TOP_TOP         => led_pad_top_top,
        LED_PAD_RIGHT_TOP       => led_pad_right_top,
        LED_PAD_RIGHT_RIGHT     => led_pad_right_right,
        LED_PAD_BOTTOM_LEFT     => led_pad_bottom_left,
        LED_PAD_BOTTOM_BOTTOM   => led_pad_bottom_bottom,
        LED_PAD_LEFT_TOP        => led_pad_left_top,
        LED_PAD_LEFT_LEFT       => led_pad_left_left,
        LED_STEP_TOP            => led_step_top,
        LED_STEP_RIGHT          => led_step_right,
        LED_STEP_BOTTOM         => led_step_bottom,
        LED_STEP_LEFT           => led_step_left,
        
        FRAME_VSYNC     => frame_vsync,
        FRAME_HSYNC     => frame_hsync,
        FRAME_WIDTH     => frame_width,
        FRAME_HEIGHT    => frame_height,
        
        FRAME_R => frame_r,
        FRAME_G => frame_g,
        FRAME_B => frame_b,
        
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
        frame_width     <= stdulv(1280, 11);
        frame_height    <= stdulv(720, 11);
        
        hor_led_cnt     <= stdulv(16, 6);
        hor_led_width   <= stdulv(50, 8);
        hor_led_height  <= stdulv(100, 8);
        ver_led_cnt     <= stdulv(9, 6);
        ver_led_width   <= stdulv(100, 8);
        ver_led_height  <= stdulv(50, 8);
        
        led_step_top    <= stdulv(80, 8);
        led_step_right  <= stdulv(80, 8);
        led_step_bottom <= stdulv(80, 8);
        led_step_left   <= stdulv(80, 8);
        
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for clk_period*10;
        wait until rising_edge(clk);
        
        wait;
    end process;

END;
