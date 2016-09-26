--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   16:35:35 09/26/2016
-- Module Name:   BLACK_BORDER_DETECTOR_tb
-- Project Name:  BLACK_BORDER_DETECTOR
-- Tool versions: Xilinx ISE 14.7
-- Description:
--   
-- VHDL Test Bench Created by ISE for module: BLACK_BORDER_DETECTOR
--   
-- Dependencies:
-- 
-- Additional Comments:
--   
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;

ENTITY BLACK_BORDER_DETECTOR_tb IS
    generic (
        R_BITS      : positive range 5 to 12;
        G_BITS      : positive range 6 to 12;
        B_BITS      : positive range 5 to 12;
        DIM_BITS    : positive range 9 to 16
    )
END BLACK_BORDER_DETECTOR_tb;

ARCHITECTURE behavior OF LED_CONTROL_tb IS
    
    -- Inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal CFG_ADDR     : std_ulogic_vector(3 downto 0) := (others => '0');
    signal CFG_WR_EN    : std_ulogic := '0';
    signal CFG_DATA     : std_ulogic_vector(7 downto 0) := (others => '0');
    
    signal FRAME_VSYNC      : std_ulogic := '0';
    signal FRAME_RGB_WR_EN  : std_ulogic := '0';
    signal FRAME_RGB        : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');
    
    -- Outputs
    signal BORDER_VALID     : std_ulogic;
    signal HOR_BORDER_SIZE  : std_ulogic_vector(DIM_BITS-1 downto 0);
    signal VER_BORDER_SIZE  : std_ulogic_vector(DIM_BITS-1 downto 0);
    
    -- clock period definitions
    constant CLK_PERIOD : time := 10 ns;
    
    signal vp       : video_profile_type;
    signal profile  : std_ulogic_vector(log2(VIDEO_PROFILE_COUNT)-1 downto 0) := (others => '0');
    
BEGIN
    
    -- clock generation
    CLK <= not CLK after CLK_PERIOD / 2;
    
    BLACK_BORDER_DETECTOR_inst : entity work.BLACK_BORDER_DETECTOR
        generic map (
            R_BITS      => R_BITS,
            G_BITS      => G_BITS,
            B_BITS      => B_BITS,
            DIM_BITS    => DIM_BITS
        )
        port map (
            RST => RST,
            CLK => CLK,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            FRAME_VSYNC     => FRAME_VSYNC,
            FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
            FRAME_RGB       => FRAME_RGB,
            
            BORDER_VALID    => BORDER_VALID,
            HOR_BORDER_SIZE => HOR_BORDER_SIZE,
            VER_BORDER_SIZE => VER_BORDER_SIZE
        );
    
    VIDEO_TIMING_GEN_inst : entity work.VIDEO_TIMING_GEN
        generic map (
            CLK_IN_PERIOD           => CLK_IN_PERIOD,
            CLK_IN_TO_CLK10_MULT    => CLK_IN_TO_CLK10_MULT,
            CLK_IN_TO_CLK10_DIV     => CLK_IN_TO_CLK10_DIV,
            PROFILE_BITS            => PROFILE_BITS,
            X_BITS                  => X_BITS,
            Y_BITS                  => Y_BITS
        )
        port map (
            CLK_IN  => CLK_IN,
            RST     => RST,
            
            PROFILE => PROFILE,
            
            CLK_OUT         => pix_clk,
            CLK_OUT_LOCKED  => pix_clk_locked,
            
            POS_VSYNC   => pos_vsync,
            POS_HSYNC   => pos_hsync,
            VSYNC       => vsync_out,
            HSYNC       => hsync_out,
            RGB_ENABLE  => rgb_enable_out,
            RGB_X       => x,
            RGB_Y       => y
        );
    
    -- Stimulus process
    stim_proc: process
    begin
        -- hold reset state for 100 ns.
        RST <= '1';
        wait for 100 ns;
        RST <= '0';
        wait for CLK_PERIOD*10;
        wait until rising_edge(CLK);
        
        
        
        report "NONE. All tests successful, quitting"
            severity FAILURE;
    end process;
    
END;
