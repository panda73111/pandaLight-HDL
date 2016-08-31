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
        DIMENSION_BITS  : positive := 11
    );
END CONFIGURATOR_tb;

ARCHITECTURE behavior OF CONFIGURATOR_tb IS 
    
    -- Inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal CALCULATE        : std_ulogic := '0';
    signal CONFIGURE_LEDEX  : std_ulogic := '0';
    signal CONFIGURE_LEDCOR : std_ulogic := '0';
    
    signal FRAME_WIDTH  : std_ulogic_vector(DIMENSION_BITS-1 downto 0) := (others => '0');
    signal FRAME_HEIGHT : std_ulogic_vector(DIMENSION_BITS-1 downto 0) := (others => '0');
    
    signal SETTINGS_ADDR    : std_ulogic_vector(9 downto 0) := (others => '0');
    signal SETTINGS_WR_EN   : std_ulogic := '0';
    signal SETTINGS_DIN     : std_ulogic_vector(7 downto 0) := x"00";
    signal SETTINGS_DOUT    : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal CFG_SEL_LEDEX    : std_ulogic;
    signal CFG_SEL_LEDCOR   : std_ulogic;
    
    signal CFG_ADDR     : std_ulogic_vector(9 downto 0);
    signal CFG_WR_EN    : std_ulogic;
    signal CFG_DATA     : std_ulogic_vector(DIMENSION_BITS-1 downto 0);
    
    signal BUSY : std_ulogic;
    
    -- Clock period definitions
    constant CLK_PERIOD : time := 10 ns; -- 100 Mhz
    
BEGIN
    
    CONFIGURATOR_inst : entity work.CONFIGURATOR
        generic map (
            DIMENSION_BITS  => DIMENSION_BITS
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            CALCULATE           => CALCULATE,
            CONFIGURE_LEDEX     => CONFIGURE_LEDEX,
            CONFIGURE_LEDCOR    => CONFIGURE_LEDCOR,
            
            FRAME_WIDTH     => FRAME_WIDTH,
            FRAME_HEIGHT    => FRAME_HEIGHT,
            
            SETTINGS_ADDR   => SETTINGS_ADDR,
            SETTINGS_WR_EN  => SETTINGS_WR_EN,
            SETTINGS_DIN    => SETTINGS_DIN,
            SETTINGS_DOUT   => SETTINGS_DOUT,
            
            CFG_SEL_LEDEX   => CFG_SEL_LEDEX,
            CFG_SEL_LEDCOR  => CFG_SEL_LEDCOR,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            BUSY    => BUSY
        );
    
    CLK <= not CLK after CLK_PERIOD/2;
    
    -- Stimulus process
    stim_proc: process
        type channel_lookup_table_type is
            array(0 to 255) of
            std_ulogic_vector(7 downto 0);
        
        type settings_type is record
            HOR_LED_CNT, HOR_LED_SCALED_WIDTH, HOR_LED_SCALED_HEIGHT,
            HOR_LED_SCALED_STEP, HOR_LED_SCALED_PAD, HOR_LED_SCALED_OFFS,
            VER_LED_CNT, VER_LED_SCALED_WIDTH, VER_LED_SCALED_HEIGHT,
            VER_LED_SCALED_STEP, VER_LED_SCALED_PAD, VER_LED_SCALED_OFFS,
            START_LED_NUM, FRAME_DELAY, RGB_MODE, LED_CONTROL_MODE
                : std_ulogic_vector(7 downto 0);
            GAMMA_CORRECTION    : std_ulogic_vector(15 downto 0); -- 4 + 12 Bit fixed point
            MIN_RED, MAX_RED, MIN_GREEN, MAX_GREEN, MIN_BLUE, MAX_BLUE
                : std_ulogic_vector(7 downto 0);
            R_LOOKUP_TABLE, G_LOOKUP_TABLE, B_LOOKUP_TABLE
                : channel_lookup_table_type;
        end record;
        variable settings1, settings2   : settings_type;
        
        procedure send_settings(s : in settings_type) is
        begin
            SETTINGS_WR_EN  <= '1';
            for settings_i in 0 to 255 loop
                SETTINGS_ADDR   <= stdulv(settings_i, 10);
                case settings_i is
                    when 0      =>  SETTINGS_DIN    <= s.HOR_LED_CNT;
                    when 1      =>  SETTINGS_DIN    <= s.HOR_LED_SCALED_WIDTH;
                    when 2      =>  SETTINGS_DIN    <= s.HOR_LED_SCALED_HEIGHT;
                    when 3      =>  SETTINGS_DIN    <= s.HOR_LED_SCALED_STEP;
                    when 4      =>  SETTINGS_DIN    <= s.HOR_LED_SCALED_PAD;
                    when 5      =>  SETTINGS_DIN    <= s.HOR_LED_SCALED_OFFS;
                    when 6      =>  SETTINGS_DIN    <= s.VER_LED_CNT;
                    when 7      =>  SETTINGS_DIN    <= s.VER_LED_SCALED_WIDTH;
                    when 8      =>  SETTINGS_DIN    <= s.VER_LED_SCALED_HEIGHT;
                    when 9      =>  SETTINGS_DIN    <= s.VER_LED_SCALED_STEP;
                    when 10     =>  SETTINGS_DIN    <= s.VER_LED_SCALED_PAD;
                    when 11     =>  SETTINGS_DIN    <= s.VER_LED_SCALED_OFFS;
                    when 12     =>  SETTINGS_DIN    <= s.START_LED_NUM;
                    when 13     =>  SETTINGS_DIN    <= s.FRAME_DELAY;
                    when 14     =>  SETTINGS_DIN    <= s.RGB_MODE;
                    when 15     =>  SETTINGS_DIN    <= s.LED_CONTROL_MODE;
                    when 16     =>  SETTINGS_DIN    <= s.GAMMA_CORRECTION(15 downto 8);
                    when 17     =>  SETTINGS_DIN    <= s.GAMMA_CORRECTION(7 downto 0);
                    when 18     =>  SETTINGS_DIN    <= s.MIN_RED;
                    when 19     =>  SETTINGS_DIN    <= s.MAX_RED;
                    when 20     =>  SETTINGS_DIN    <= s.MIN_GREEN;
                    when 21     =>  SETTINGS_DIN    <= s.MAX_GREEN;
                    when 22     =>  SETTINGS_DIN    <= s.MIN_BLUE;
                    when 23     =>  SETTINGS_DIN    <= s.MAX_BLUE;
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
            wait until rising_edge(CLK);
            
            CONFIGURE_LEDEX <= '1';
            wait until rising_edge(CLK);
            CONFIGURE_LEDEX <= '0';
            wait until BUSY='0';
            wait until rising_edge(CLK);
        end procedure;
    begin
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait until rising_edge(CLK);
        
        settings1    := (
            HOR_LED_CNT             => stdulv( 16, 8),
            HOR_LED_SCALED_WIDTH    => stdulv( 96, 8), -- 720p: 60 pixel
            HOR_LED_SCALED_HEIGHT   => stdulv(226, 8), -- 720p: 80 pixel
            HOR_LED_SCALED_STEP     => stdulv(128, 8), -- 720p: 80 pixel
            HOR_LED_SCALED_PAD      => stdulv( 15, 8), -- 720p:  5 pixel
            HOR_LED_SCALED_OFFS     => stdulv( 16, 8), -- 720p: 10 pixel
            VER_LED_CNT             => stdulv(  9, 8),
            VER_LED_SCALED_WIDTH    => stdulv(128, 8), -- 720p: 80 pixel
            VER_LED_SCALED_HEIGHT   => stdulv(169, 8), -- 720p: 60 pixel
            VER_LED_SCALED_STEP     => stdulv(226, 8), -- 720p: 80 pixel
            VER_LED_SCALED_PAD      => stdulv(  8, 8), -- 720p:  5 pixel
            VER_LED_SCALED_OFFS     => stdulv( 29, 8), -- 720p: 10 pixel
            START_LED_NUM           => stdulv( 10, 8),
            FRAME_DELAY             => stdulv(120, 8),
            RGB_MODE                => x"00",
            LED_CONTROL_MODE        => x"00",
            GAMMA_CORRECTION        => x"2000", -- 2.0
            MIN_RED                 => x"00",
            MAX_RED                 => x"FF",
            MIN_GREEN               => x"00",
            MAX_GREEN               => x"FF",
            MIN_BLUE                => x"00",
            MAX_BLUE                => x"FF",
            R_LOOKUP_TABLE          => (others  => x"FF"),
            G_LOOKUP_TABLE          => (others  => x"FF"),
            B_LOOKUP_TABLE          => (others  => x"FF")
        );
        
        settings2    := (
            HOR_LED_CNT             => x"10",
            HOR_LED_SCALED_WIDTH    => x"00",
            HOR_LED_SCALED_HEIGHT   => x"00",
            HOR_LED_SCALED_STEP     => x"00",
            HOR_LED_SCALED_PAD      => x"00",
            HOR_LED_SCALED_OFFS     => x"00",
            VER_LED_CNT             => x"09",
            VER_LED_SCALED_WIDTH    => x"00",
            VER_LED_SCALED_HEIGHT   => x"00",
            VER_LED_SCALED_STEP     => x"00",
            VER_LED_SCALED_PAD      => x"00",
            VER_LED_SCALED_OFFS     => x"00",
            START_LED_NUM           => x"00",
            FRAME_DELAY             => x"00",
            RGB_MODE                => x"00",
            LED_CONTROL_MODE        => x"00",
            GAMMA_CORRECTION        => x"0000",
            MIN_RED                 => x"00",
            MAX_RED                 => x"00",
            MIN_GREEN               => x"00",
            MAX_GREEN               => x"00",
            MIN_BLUE                => x"00",
            MAX_BLUE                => x"00",
            R_LOOKUP_TABLE          => (others  => x"FF"),
            G_LOOKUP_TABLE          => (others  => x"FF"),
            B_LOOKUP_TABLE          => (others  => x"FF")
        );
        
        send_settings(settings1);
        
        for i in 0 to 1023 loop
            SETTINGS_ADDR   <= stdulv(i, 10);
            wait until rising_edge(CLK);
        end loop;
        
        FRAME_WIDTH     <= stdulv(1280, 11);
        FRAME_HEIGHT    <= stdulv( 720, 11);
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until BUSY='0';
        wait until rising_edge(CLK);
        
        configure;
        
        FRAME_WIDTH     <= stdulv(640, 11);
        FRAME_HEIGHT    <= stdulv(480, 11);
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
