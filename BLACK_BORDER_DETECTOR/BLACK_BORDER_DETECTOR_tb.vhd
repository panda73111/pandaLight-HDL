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
use work.video_profiles.all;

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
    constant CLK_PERIOD             : time := 10 ns;
    constant G_CLK_PERIOD_REAL      : real := real(G_CLK_PERIOD / 1 ps) / real(1 ns / 1 ps);
    constant CLK_IN_TO_CLK10_MULT   : natural := 1;
    constant CLK_IN_TO_CLK10_DIV    : natural := 2;
    
    signal pix_clk          : std_ulogic := '0';
    signal pix_clk_locked   : std_ulogic := '0';
    signal vsync            : std_ulogic := '0';
    signal rgb_enable       : std_ulogic := '0';
    signal x, y             : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    constant VP         : video_profile_type := VIDEO_PROFILES(VIDEO_PROFILE_640_480p_60);
    constant PROFILE    :
        std_ulogic_vector(log2(VIDEO_PROFILE_COUNT)-1 downto 0) :=
        stdulv(VIDEO_PROFILE_640_480p_60, log2(VIDEO_PROFILE_COUNT));
    
    constant FRAME_WIDTH    : std_ulogic_vector(15 downto 0) := stdulv(VP.width, 16);
    constant FRAME_HEIGHT   : std_ulogic_vector(15 downto 0) := stdulv(VP.height, 16);
    
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
            CLK_IN_PERIOD           => G_CLK_PERIOD_REAL,
            CLK_IN_TO_CLK10_MULT    => CLK_IN_TO_CLK10_MULT,
            CLK_IN_TO_CLK10_DIV     => CLK_IN_TO_CLK10_DIV,
            DIM_BITS                => DIM_BITS
        )
        port map (
            CLK_IN  => CLK,
            RST     => RST,
            
            PROFILE => PROFILE,
            
            CLK_OUT         => pix_clk,
            CLK_OUT_LOCKED  => pix_clk_locked,
            
            POS_VSYNC   => vsync,
            RGB_ENABLE  => rgb_enable,
            RGB_X       => x,
            RGB_Y       => y
        );
    
    -- Stimulus process
    stim_proc: process
        
        type cfg_type is record
            enable              : std_ulogic;
            threshold           : std_ulogic_vector(7 downto 0);
            consistent_frames   : std_ulogic_vector(7 downto 0);
            inconsistent_frames : std_ulogic_vector(7 downto 0);
            remove_bias         : std_ulogic_vector(7 downto 0);
            scan_width          : std_ulogic_vector(15 downto 0);
            scan_height         : std_ulogic_vector(15 downto 0);
            frame_width         : std_ulogic_vector(15 downto 0);
            frame_height        : std_ulogic_vector(15 downto 0);
        end record;
        
        variable cfg    : cfg_type;
        
        procedure write_config (cfg : in cfg_type) is
        begin
            CFG_WR_EN   <= '1';
            RST         <= '1';
            for settings_i in 0 to 12 loop
                CFG_ADDR    <= stdulv(settings_i, 4);
                case settings_i is
                    when 0      =>  CFG_DATA    <= "0000000" & cfg.enable;
                    when 1      =>  CFG_DATA    <= cfg.threshold;
                    when 2      =>  CFG_DATA    <= cfg.consistent_frames;
                    when 3      =>  CFG_DATA    <= cfg.inconsistent_frames;
                    when 4      =>  CFG_DATA    <= cfg.remove_bias;
                    when 5      =>  CFG_DATA    <= cfg.scan_width  (15 downto 8);
                    when 6      =>  CFG_DATA    <= cfg.scan_width  ( 7 downto 0);
                    when 7      =>  CFG_DATA    <= cfg.scan_height (15 downto 8);
                    when 8      =>  CFG_DATA    <= cfg.scan_height ( 7 downto 0);
                    when 9      =>  CFG_DATA    <= cfg.frame_width (15 downto 8);
                    when 10     =>  CFG_DATA    <= cfg.frame_width ( 7 downto 0);
                    when 11     =>  CFG_DATA    <= cfg.frame_height(15 downto 8);
                    when 12     =>  CFG_DATA    <= cfg.frame_height( 7 downto 0);
                end case;
                wait until rising_edge(CLK);
            end loop;
            CFG_WR_EN   <= '0';
            RST         <= '0';
        end procedure;
        
    begin
        FRAME_VSYNC     <= '1';
        FRAME_RGB_WR_EN <= '0';
        
        -- hold reset state for 100 ns.
        RST <= '1';
        wait for 100 ns;
        RST <= '0';
        wait for CLK_PERIOD*10;
        wait until rising_edge(pix_clk) and pix_clk_locked='1';
        
        cfg := (
            enable              => '1',
            threshold           => stdulv( 50,  8),
            consistent_frames   => stdulv( 10,  8),
            inconsistent_frames => stdulv(  5,  8),
            remove_bias         => stdulv(  2,  8),
            scan_width          => stdulv(100, 16),
            scan_height         => stdulv( 80, 16),
            frame_width         => FRAME_WIDTH,
            frame_height        => FRAME_HEIGHT
        );
        write_config(cfg);
        
        -- Test 1: White frames
        
        FRAME_RGB   <= x"FF_FF_FF";
        
        if vsync='0' then
            wait until rising_edge(pix_clk) and vsync='1';
        end if;
        
        for frame_i in 1 to 20 loop
        
            wait until rising_edge(pix_clk) and vsync='0';
            FRAME_VSYNC <= '0';
            
            while vsync='0' loop
                FRAME_RGB_WR_EN <= rgb_enable;
                wait until rising_edge(pix_clk);
            end loop;
            
            wait until rising_edge(pix_clk) and vsync='1';
            FRAME_VSYNC <= '1';
            
        end loop;
        
        wait for 10 us;
        wait until rising_edge(pix_clk);
        
        -- Test 1 finished
        
        report "NONE. All tests successful, quitting"
            severity FAILURE;
    end process;
    
END;
