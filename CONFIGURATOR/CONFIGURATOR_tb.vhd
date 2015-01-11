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
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

ENTITY CONFIGURATOR_tb IS
    generic (
        FRAME_SIZE_BITS : natural := 11
    );
END CONFIGURATOR_tb;

ARCHITECTURE behavior OF CONFIGURATOR_tb IS 
    
    -- Inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal CALCULATE        : std_ulogic := '0';
    signal CONFIGURE_LEDEX  : std_ulogic := '0';
    signal CONFIGURE_LEDCOR : std_ulogic := '0';
    
    signal FRAME_WIDTH  : std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0) := (others => '0');
    signal FRAME_HEIGHT : std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0) := (others => '0');
    
    signal SETTINGS_WR_EN   : std_ulogic := '0';
    signal SETTINGS_DATA    : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal CFG_SEL_LEDEX    : std_ulogic;
    signal CFG_SEL_LEDCOR   : std_ulogic;
    
    signal CFG_ADDR     : std_ulogic_vector(9 downto 0);
    signal CFG_WR_EN    : std_ulogic;
    signal CFG_DATA     : std_ulogic_vector(7 downto 0);
    
    signal IDLE : std_ulogic;
    
    -- Clock period definitions
    constant CLK_PERIOD : time := 10 ns; -- 100 Mhz
    
BEGIN
    
    CONFIGURATOR_inst : entity work.CONFIGURATOR
        generic map (
            FRAME_SIZE_BITS => FRAME_SIZE_BITS
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            CALCULATE           => CALCULATE,
            CONFIGURE_LEDEX     => CONFIGURE_LEDEX,
            CONFIGURE_LEDCOR    => CONFIGURE_LEDCOR,
            
            FRAME_WIDTH     => FRAME_WIDTH,
            FRAME_HEIGHT    => FRAME_HEIGHT,
            
            SETTINGS_WR_EN  => SETTINGS_WR_EN,
            SETTINGS_DATA   => SETTINGS_DATA,
            
            CFG_SEL_LEDEX   => CFG_SEL_LEDEX,
            CFG_SEL_LEDCOR  => CFG_SEL_LEDCOR,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            IDLE    => IDLE
        );
    
    CLK <= not CLK after CLK_PERIOD/2;
    
    -- Stimulus process
    stim_proc: process
        type settings_type is record
            HOR_LED_CNT, HOR_LED_SCALED_WIDTH, HOR_LED_SCALED_HEIGHT,
            HOR_LED_SCALED_STEP, HOR_LED_SCALED_PAD, HOR_LED_SCALED_OFFS,
            VER_LED_CNT, VER_LED_SCALED_WIDTH, VER_LED_SCALED_HEIGHT,
            VER_LED_SCALED_STEP, VER_LED_SCALED_PAD, VER_LED_SCALED_OFFS,
            START_LED_NUM, FRAME_DELAY, RGB_MODE
                : std_ulogic_vector(7 downto 0);
        end record;
        variable settings   : settings_type;
        
        procedure send_settings(s : in settings_type) is
        begin
            SETTINGS_WR_EN  <= '1';
            for i in 0 to 14 loop
                case i is
                    when 0  =>  SETTINGS_DATA   <= s.HOR_LED_CNT;
                    when 1  =>  SETTINGS_DATA   <= s.HOR_LED_SCALED_WIDTH;
                    when 2  =>  SETTINGS_DATA   <= s.HOR_LED_SCALED_HEIGHT;
                    when 3  =>  SETTINGS_DATA   <= s.HOR_LED_SCALED_STEP;
                    when 4  =>  SETTINGS_DATA   <= s.HOR_LED_SCALED_PAD;
                    when 5  =>  SETTINGS_DATA   <= s.HOR_LED_SCALED_OFFS;
                    when 6  =>  SETTINGS_DATA   <= s.VER_LED_CNT;
                    when 7  =>  SETTINGS_DATA   <= s.VER_LED_SCALED_WIDTH;
                    when 8  =>  SETTINGS_DATA   <= s.VER_LED_SCALED_HEIGHT;
                    when 9  =>  SETTINGS_DATA   <= s.VER_LED_SCALED_STEP;
                    when 10 =>  SETTINGS_DATA   <= s.VER_LED_SCALED_PAD;
                    when 11 =>  SETTINGS_DATA   <= s.VER_LED_SCALED_OFFS;
                    when 12 =>  SETTINGS_DATA   <= s.START_LED_NUM;
                    when 13 =>  SETTINGS_DATA   <= s.FRAME_DELAY;
                    when 14 =>  SETTINGS_DATA   <= s.RGB_MODE;
                end case;
                wait until rising_edge(CLK);
            end loop;
            SETTINGS_WR_EN  <= '0';
        end procedure;
        
        procedure configure is
        begin
            CONFIGURE_LEDCOR    <= '1';
            wait until rising_edge(CLK);
            CONFIGURE_LEDCOR    <= '0';
            wait until rising_edge(IDLE);
            wait until rising_edge(CLK);
            
            CONFIGURE_LEDEX <= '1';
            wait until rising_edge(CLK);
            CONFIGURE_LEDEX <= '0';
            wait until rising_edge(IDLE);
            wait until rising_edge(CLK);
        end procedure;
    begin
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait until rising_edge(CLK);
        
        settings    := (
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
            RGB_MODE                => x"00"
        );
        send_settings(settings);
        
        FRAME_WIDTH     <= stdulv(1280, FRAME_SIZE_BITS);
        FRAME_HEIGHT    <= stdulv( 720, FRAME_SIZE_BITS);
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until rising_edge(IDLE);
        wait until rising_edge(CLK);
        
        configure;
        
        FRAME_WIDTH     <= stdulv(640, FRAME_SIZE_BITS);
        FRAME_HEIGHT    <= stdulv(480, FRAME_SIZE_BITS);
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until rising_edge(IDLE);
        wait until rising_edge(CLK);
        
        configure;
        
        wait for 10 us;
        report "NONE. All tests finished successfully."
            severity FAILURE;
    end process;
    
END;
