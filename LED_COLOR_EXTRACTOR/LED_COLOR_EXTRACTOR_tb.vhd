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
    
    constant R_BITS          : natural range 1 to 12 := 8;
    constant G_BITS          : natural range 1 to 12 := 8;
    constant B_BITS          : natural range 1 to 12 := 8;
    
    -- Inputs
    signal clk, rst : std_ulogic := '0';
    
    signal cfg_addr     : std_ulogic_vector(3 downto 0) := "0000";
    signal cfg_wr_en    : std_ulogic := '0';
    signal cfg_data     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal frame_vsync, frame_hsync     : std_ulogic := '0';
    
    signal frame_r  : std_ulogic_vector(R_BITS-1 downto 0) := (others => '0');
    signal frame_g  : std_ulogic_vector(G_BITS-1 downto 0) := (others => '0');
    signal frame_b  : std_ulogic_vector(B_BITS-1 downto 0) := (others => '0');

    --Outputs
    signal led_vsync    : std_ulogic := '0';
    signal led_valid    : std_ulogic := '0';
    signal led_num      : std_ulogic_vector(7 downto 0) := (others => '0');
    signal led_r        : std_ulogic_vector(R_BITS-1 downto 0) := (others => '0');
    signal led_g        : std_ulogic_vector(G_BITS-1 downto 0) := (others => '0');
    signal led_b        : std_ulogic_vector(B_BITS-1 downto 0) := (others => '0');

    -- Clock period definitions
    constant clk_period : time := 10 ns; -- 100 MHz
    
    signal frame_width, frame_height    : std_ulogic_vector(15 downto 0) := x"0000";
    
BEGIN
    
    test_frame_gen_inst : entity work.test_camera
    generic map (
        FRAME_STEP      => 0,
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
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK => clk,
        RST => rst,
        
        CFG_ADDR    => cfg_addr,
        CFG_WR_EN   => cfg_wr_en,
        CFG_DATA    => cfg_data,
        
        LED_VSYNC   => led_vsync,
        LED_VALID   => led_valid,
        LED_NUM     => led_num,
        LED_R       => led_r,
        LED_G       => led_g,
        LED_B       => led_b
    );
    
    LED_COLOR_EXTRACTOR_inst : entity work.LED_COLOR_EXTRACTOR
    generic map (
        R_BITS          => R_BITS,
        G_BITS          => G_BITS,
        B_BITS          => B_BITS
    )
    port map (
        CLK => clk,
        RST => rst,
        
        CFG_ADDR    => cfg_addr,
        CFG_WR_EN   => cfg_wr_en,
        CFG_DATA    => cfg_data,
        
        FRAME_VSYNC     => frame_vsync,
        FRAME_HSYNC     => frame_hsync,
        
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
        
        type cfg_type is
            array(0 to 15) of
            std_ulogic_vector(7 downto 0);
        
        variable cfg    : cfg_type;
        
        procedure write_config (cfg : in cfg_type) is
        begin
            cfg_wr_en   <= '1';
            for i in 0 to 15 loop
                cfg_addr    <= stdulv(i, 4);
                cfg_data    <= cfg(i);
                wait until rising_edge(clk);
            end loop;
            cfg_wr_en   <= '0';
            wait until rising_edge(clk);
        end procedure;
        
    begin
        
        frame_width     <= stdulv(1280, 16);
        frame_height    <= stdulv(720,  16);
        
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait until rising_edge(clk);
        
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
            wait until rising_edge(clk) and frame_vsync='1';
            wait until rising_edge(clk) and frame_vsync='0';
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
