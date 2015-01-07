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
    
    signal LED_COUNT        : std_ulogic_vector(7 downto 0) := x"00";
    signal START_LED_NUM    : std_ulogic_vector(7 downto 0) := x"00";
    signal FRAME_DELAY      : std_ulogic_vector(7 downto 0) := x"00";
    signal RGB_MODE         : std_ulogic_vector(2 downto 0) := "000";
    
    -- Outputs
    signal CFG_SEL_LEDEX    : std_ulogic;
    signal CFG_SEL_LEDCOR   : std_ulogic;
    
    signal CFG_ADDR     : std_ulogic_vector(3 downto 0);
    signal CFG_WR_EN    : std_ulogic;
    signal CFG_DATA     : std_ulogic_vector(7 downto 0);
    
    signal CALCULATION_FINISHED : std_ulogic;
    
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
            
            LED_COUNT       => LED_COUNT,
            START_LED_NUM   => START_LED_NUM,
            FRAME_DELAY     => FRAME_DELAY,
            RGB_MODE        => RGB_MODE,
            
            CFG_SEL_LEDEX   => CFG_SEL_LEDEX,
            CFG_SEL_LEDCOR  => CFG_SEL_LEDCOR,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            CALCULATION_FINISHED    => CALCULATION_FINISHED
        );
    
    CLK <= not CLK after CLK_PERIOD/2;
    
    -- Stimulus process
    stim_proc: process
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
            VER_LED_SCALED_OFFS     => stdulv( 29, 8)  -- 720p: 10 pixel
        );
        
        LED_COUNT           <= stdulv(100, 8);
        START_LED_NUM       <= stdulv(50, 8);
        FRAME_DELAY         <= stdulv(10, 8);
        RGB_MODE            <= "000";
        CONFIGURE_LEDCOR    <= '1';
        wait until rising_edge(CLK);
        CONFIGURE_LEDCOR    <= '0';
        wait for CLK_PERIOD*100;
        
        FRAME_WIDTH     <= stdulv(1280, FRAME_SIZE_BITS);
        FRAME_HEIGHT    <= stdulv( 720, FRAME_SIZE_BITS);
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until CALCULATION_FINISHED='1';
        CONFIGURE_LEDEX <= '1';
        wait until rising_edge(CLK);
        CONFIGURE_LEDEX <= '0';
        wait for CLK_PERIOD*100;
        
        FRAME_WIDTH     <= stdulv(640, FRAME_SIZE_BITS);
        FRAME_HEIGHT    <= stdulv(480, FRAME_SIZE_BITS);
        CALCULATE       <= '1';
        wait until rising_edge(CLK);
        CALCULATE       <= '0';
        wait until CALCULATION_FINISHED='1';
        CONFIGURE_LEDEX <= '1';
        wait until rising_edge(CLK);
        CONFIGURE_LEDEX <= '0';
        wait for CLK_PERIOD*100;
        
        wait for 10 us;
        report "NONE. All tests finished successfully."
            severity FAILURE;
    end process;
    
END;
