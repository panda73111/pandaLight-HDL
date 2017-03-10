--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   21:47:05 12/31/2014
-- Module Name:   CONFIGURATOR_tb
-- Project Name:  pandaLight-Tests
-- Tool versions: Xilinx ISE 14.7
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: CONFIGURATOR
-- 
-- Additional Comments:
--  
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;

ENTITY CONFIGURATOR_tb IS
    generic (
        DIM_BITS    : positive range 9 to 16 := 11
    );
END CONFIGURATOR_tb;

ARCHITECTURE behavior OF CONFIGURATOR_tb IS 
    
    -- Inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal CALCULATE        : std_ulogic := '0';
    signal CONFIGURE_LEDEX  : std_ulogic := '0';
    signal CONFIGURE_LEDCOR : std_ulogic := '0';
    signal CONFIGURE_BBD    : std_ulogic := '0';
    
    signal FRAME_WIDTH  : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    signal FRAME_HEIGHT : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    signal SETTINGS_ADDR    : std_ulogic_vector(9 downto 0) := (others => '0');
    signal SETTINGS_WR_EN   : std_ulogic := '0';
    signal SETTINGS_DIN     : std_ulogic_vector(7 downto 0) := x"00";
    signal SETTINGS_DOUT    : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal CFG_SEL_LEDEX    : std_ulogic;
    signal CFG_SEL_LEDCOR   : std_ulogic;
    signal CFG_SEL_BBD      : std_ulogic;
    
    signal CFG_ADDR     : std_ulogic_vector(9 downto 0);
    signal CFG_WR_EN    : std_ulogic;
    signal CFG_DATA     : std_ulogic_vector(7 downto 0);
    
    signal BUSY : std_ulogic;
    
    -- Clock period definitions
    constant CLK_PERIOD : time := 10 ns; -- 100 Mhz
    
BEGIN
    
    CONFIGURATOR_inst : entity work.CONFIGURATOR
        generic map (
            DIM_BITS    => DIM_BITS
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            CALCULATE           => CALCULATE,
            CONFIGURE_LEDEX     => CONFIGURE_LEDEX,
            CONFIGURE_LEDCOR    => CONFIGURE_LEDCOR,
            CONFIGURE_BBD       => CONFIGURE_BBD,
            
            FRAME_WIDTH     => FRAME_WIDTH,
            FRAME_HEIGHT    => FRAME_HEIGHT,
            
            SETTINGS_ADDR   => SETTINGS_ADDR,
            SETTINGS_WR_EN  => SETTINGS_WR_EN,
            SETTINGS_DIN    => SETTINGS_DIN,
            SETTINGS_DOUT   => SETTINGS_DOUT,
            
            CFG_SEL_LEDEX   => CFG_SEL_LEDEX,
            CFG_SEL_LEDCOR  => CFG_SEL_LEDCOR,
            CFG_SEL_BBD     => CFG_SEL_BBD,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            BUSY    => BUSY
        );
    
    CLK <= not CLK after CLK_PERIOD/2;
    
    -- Stimulus process
    stim_proc: process
        constant DIMENSION_MAX  : natural := 2**16-1;
        
        type channel_lookup_table_type is
            array(0 to 255) of
            std_ulogic_vector(7 downto 0);
        
        type settings_type is record
            hor_led_cnt                                                             : std_ulogic_vector(7 downto 0);
            hor_led_width, hor_led_height, hor_led_step, hor_led_pad, hor_led_offs  : std_ulogic_vector(15 downto 0);
            ver_led_cnt                                                             : std_ulogic_vector(7 downto 0);
            ver_led_width, ver_led_height, ver_led_step, ver_led_pad, ver_led_offs  : std_ulogic_vector(15 downto 0);
            start_led_num, frame_delay, rgb_mode, led_control_mode                  : std_ulogic_vector(7 downto 0);
            gamma_correction                                                        : std_ulogic_vector(15 downto 0); -- 4 + 12 Bit fixed point
            min_red, max_red, min_green, max_green, min_blue, max_blue              : std_ulogic_vector(7 downto 0);
            bbd_enable                                                              : std_ulogic;
            bbd_threshold                                                           : std_ulogic_vector(7 downto 0);
            bbd_consistent_frames, bbd_inconsistent_frames                          : std_ulogic_vector(7 downto 0);
            bbd_remove_bias                                                         : std_ulogic_vector(7 downto 0);
            bbd_scan_width, bbd_scan_height                                         : std_ulogic_vector(15 downto 0);
            r_lookup_table, g_lookup_table, b_lookup_table                          : channel_lookup_table_type;
        end record;
        variable settings1, settings2   : settings_type;
        
        procedure send_settings(s : in settings_type) is
        begin
            SETTINGS_WR_EN  <= '1';
            for settings_i in 0 to 255 loop
                SETTINGS_ADDR   <= stdulv(settings_i, 10);
                case settings_i is
                    when   0    =>  SETTINGS_DIN    <= s.hor_led_cnt;
                    when   1    =>  SETTINGS_DIN    <= s.hor_led_width(15 downto 8);
                    when   2    =>  SETTINGS_DIN    <= s.hor_led_width(7 downto 0);
                    when   3    =>  SETTINGS_DIN    <= s.hor_led_height(15 downto 8);
                    when   4    =>  SETTINGS_DIN    <= s.hor_led_height(7 downto 0);
                    when   5    =>  SETTINGS_DIN    <= s.hor_led_step(15 downto 8);
                    when   6    =>  SETTINGS_DIN    <= s.hor_led_step(7 downto 0);
                    when   7    =>  SETTINGS_DIN    <= s.hor_led_pad(15 downto 8);
                    when   8    =>  SETTINGS_DIN    <= s.hor_led_pad(7 downto 0);
                    when   9    =>  SETTINGS_DIN    <= s.hor_led_offs(15 downto 8);
                    when  10    =>  SETTINGS_DIN    <= s.hor_led_offs(7 downto 0);
                    when  11    =>  SETTINGS_DIN    <= s.ver_led_cnt;
                    when  12    =>  SETTINGS_DIN    <= s.ver_led_width(15 downto 8);
                    when  13    =>  SETTINGS_DIN    <= s.ver_led_width(7 downto 0);
                    when  14    =>  SETTINGS_DIN    <= s.ver_led_height(15 downto 8);
                    when  15    =>  SETTINGS_DIN    <= s.ver_led_height(7 downto 0);
                    when  16    =>  SETTINGS_DIN    <= s.ver_led_step(15 downto 8);
                    when  17    =>  SETTINGS_DIN    <= s.ver_led_step(7 downto 0);
                    when  18    =>  SETTINGS_DIN    <= s.ver_led_pad(15 downto 8);
                    when  19    =>  SETTINGS_DIN    <= s.ver_led_pad(7 downto 0);
                    when  20    =>  SETTINGS_DIN    <= s.ver_led_offs(15 downto 8);
                    when  21    =>  SETTINGS_DIN    <= s.ver_led_offs(7 downto 0);
                    when  64    =>  SETTINGS_DIN    <= s.start_led_num;
                    when  65    =>  SETTINGS_DIN    <= s.frame_delay;
                    when  66    =>  SETTINGS_DIN    <= s.rgb_mode;
                    when  67    =>  SETTINGS_DIN    <= s.led_control_mode;
                    when  68    =>  SETTINGS_DIN    <= s.gamma_correction(15 downto 8);
                    when  69    =>  SETTINGS_DIN    <= s.gamma_correction(7 downto 0);
                    when  70    =>  SETTINGS_DIN    <= s.min_red;
                    when  71    =>  SETTINGS_DIN    <= s.max_red;
                    when  72    =>  SETTINGS_DIN    <= s.min_green;
                    when  73    =>  SETTINGS_DIN    <= s.max_green;
                    when  74    =>  SETTINGS_DIN    <= s.min_blue;
                    when  75    =>  SETTINGS_DIN    <= s.max_blue;
                    when 128    =>  SETTINGS_DIN(0) <= s.bbd_enable;
                    when 129    =>  SETTINGS_DIN    <= s.bbd_threshold;
                    when 130    =>  SETTINGS_DIN    <= s.bbd_consistent_frames;
                    when 131    =>  SETTINGS_DIN    <= s.bbd_inconsistent_frames;
                    when 132    =>  SETTINGS_DIN    <= s.bbd_remove_bias;
                    when 133    =>  SETTINGS_DIN    <= s.bbd_scan_width(15 downto 8);
                    when 134    =>  SETTINGS_DIN    <= s.bbd_scan_width(7 downto 0);
                    when 135    =>  SETTINGS_DIN    <= s.bbd_scan_height(15 downto 8);
                    when 136    =>  SETTINGS_DIN    <= s.bbd_scan_height(7 downto 0);
                    when others =>  SETTINGS_DIN    <= x"00";
                end case;
                wait until rising_edge(CLK);
            end loop;
            for byte_i in 0 to 255 loop
                SETTINGS_ADDR   <= stdulv(byte_i+256, 10);
                SETTINGS_DIN    <= s.R_LOOKUP_TABLE(byte_i);
                wait until rising_edge(CLK);
            end loop;
            for byte_i in 0 to 255 loop
                SETTINGS_ADDR   <= stdulv(byte_i+2*256, 10);
                SETTINGS_DIN    <= s.G_LOOKUP_TABLE(byte_i);
                wait until rising_edge(CLK);
            end loop;
            for byte_i in 0 to 255 loop
                SETTINGS_ADDR   <= stdulv(byte_i+3*256, 10);
                SETTINGS_DIN    <= s.B_LOOKUP_TABLE(byte_i);
                wait until rising_edge(CLK);
            end loop;
            SETTINGS_WR_EN  <= '0';
        end procedure;
        
        procedure configure is
        begin
            CONFIGURE_LEDCOR    <= '1';
            wait until rising_edge(CLK);
            CONFIGURE_LEDCOR    <= '0';
            wait until BUSY='0';
            wait for 100 us;
            wait until rising_edge(CLK);
            
            CONFIGURE_LEDEX <= '1';
            wait until rising_edge(CLK);
            CONFIGURE_LEDEX <= '0';
            wait until BUSY='0';
            wait for 100 us;
            wait until rising_edge(CLK);
            
            CONFIGURE_BBD <= '1';
            wait until rising_edge(CLK);
            CONFIGURE_BBD <= '0';
            wait until BUSY='0';
            wait for 100 us;
            wait until rising_edge(CLK);
        end procedure;
    begin
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait until rising_edge(CLK);
        
        settings1    := (
            hor_led_cnt             => stdulv( 16, 8),
            hor_led_width           => stdulv( 60 * DIMENSION_MAX / 1280, 16),
            hor_led_height          => stdulv( 80 * DIMENSION_MAX /  720, 16),
            hor_led_step            => stdulv( 80 * DIMENSION_MAX / 1280, 16),
            hor_led_pad             => stdulv(  5 * DIMENSION_MAX /  720, 16),
            hor_led_offs            => stdulv( 10 * DIMENSION_MAX / 1280, 16),
            ver_led_cnt             => stdulv(  9, 8),
            ver_led_width           => stdulv( 80 * DIMENSION_MAX / 1280, 16),
            ver_led_height          => stdulv( 60 * DIMENSION_MAX /  720, 16),
            ver_led_step            => stdulv( 80 * DIMENSION_MAX /  720, 16),
            ver_led_pad             => stdulv(  5 * DIMENSION_MAX / 1280, 16),
            ver_led_offs            => stdulv( 10 * DIMENSION_MAX /  720, 16),
            start_led_num           => stdulv( 10, 8),
            frame_delay             => stdulv(120, 8),
            rgb_mode                => x"00",
            led_control_mode        => x"00",
            gamma_correction        => x"2000", -- 2.0
            min_red                 => x"00",
            max_red                 => x"FF",
            min_green               => x"00",
            max_green               => x"FF",
            min_blue                => x"00",
            max_blue                => x"FF",
            bbd_enable              => '1',
            bbd_threshold           => stdulv( 10,  8),
            bbd_consistent_frames   => stdulv( 10,  8),
            bbd_inconsistent_frames => stdulv( 10,  8),
            bbd_remove_bias         => stdulv(  2,  8),
            bbd_scan_width          => stdulv(400 * DIMENSION_MAX / 1280, 16),
            bbd_scan_height         => stdulv(400 * DIMENSION_MAX /  720, 16),
            r_lookup_table          => (others  => x"FF"),
            g_lookup_table          => (others  => x"FF"),
            b_lookup_table          => (others  => x"FF")
        );
        
        settings2    := (
            hor_led_cnt             => x"10",
            hor_led_width           => x"0000",
            hor_led_height          => x"0000",
            hor_led_step            => x"0000",
            hor_led_pad             => x"0000",
            hor_led_offs            => x"0000",
            ver_led_cnt             => x"09",
            ver_led_width           => x"0000",
            ver_led_height          => x"0000",
            ver_led_step            => x"0000",
            ver_led_pad             => x"0000",
            ver_led_offs            => x"0000",
            start_led_num           => x"00",
            frame_delay             => x"00",
            rgb_mode                => x"00",
            led_control_mode        => x"00",
            gamma_correction        => x"0000",
            min_red                 => x"00",
            max_red                 => x"00",
            min_green               => x"00",
            max_green               => x"00",
            min_blue                => x"00",
            max_blue                => x"00",
            bbd_enable              => '0',
            bbd_threshold           => x"00",
            bbd_consistent_frames   => x"00",
            bbd_inconsistent_frames => x"00",
            bbd_remove_bias         => x"00",
            bbd_scan_width          => x"0000",
            bbd_scan_height         => x"0000",
            r_lookup_table          => (others  => x"FF"),
            g_lookup_table          => (others  => x"FF"),
            b_lookup_table          => (others  => x"FF")
        );
        
        send_settings(settings1);
        
        for i in 0 to 1023 loop
            SETTINGS_ADDR   <= stdulv(i, 10);
            wait until rising_edge(CLK);
        end loop;
        
        FRAME_WIDTH     <= stdulv(1280, FRAME_WIDTH'length);
        FRAME_HEIGHT    <= stdulv( 720, FRAME_HEIGHT'length);
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until BUSY='0';
        wait until rising_edge(CLK);
        
        configure;
        
        FRAME_WIDTH     <= stdulv(640, FRAME_WIDTH'length);
        FRAME_HEIGHT    <= stdulv(480, FRAME_HEIGHT'length);
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until BUSY='0';
        wait until rising_edge(CLK);
        
        configure;
        
        send_settings(settings2);
        
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until BUSY='0';
        wait until rising_edge(CLK);
        
        configure;
        
        wait for 10 us;
        report "NONE. All tests finished successfully."
            severity FAILURE;
    end process;
    
END;
