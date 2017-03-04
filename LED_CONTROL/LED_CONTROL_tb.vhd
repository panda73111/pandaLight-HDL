--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   11:17:14 07/31/2014
-- Module Name:   LED_CONTROL_tb.vhd
-- Project Name:  LED_CONTROL
-- Tool versions: Xilinx ISE 14.7
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: LED_CONTROL
-- 
-- Dependencies:
-- 
-- Additional Comments:
--  
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.math_real.ALL;
use work.help_funcs.all;

ENTITY LED_CONTROL_tb IS
END LED_CONTROL_tb;

ARCHITECTURE behavior OF LED_CONTROL_tb IS

    --Inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal MODE         : std_ulogic_vector(1 downto 0) := (others => '0');
    
    signal LED_VSYNC        : std_ulogic := '0';
    signal LED_RGB          : std_ulogic_vector(23 downto 0) := (others => '0');
    signal LED_RGB_WR_EN    : std_ulogic := '0';

    --outputs
    signal LEDS_CLK     : std_ulogic;
    signal LEDS_DATA    : std_ulogic;

    -- clock period definitions
    constant CLK_PERIOD : time := 10 ns;
    
    constant CLK_PERIOD_REAL    : real := real(clk_period / 1 ps) / real(1 ns / 1 ps);

BEGIN
    
    -- clock generation
    CLK <= not CLK after CLK_PERIOD / 2;

    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD           => CLK_PERIOD_REAL,
            -- 1 MHz, 100 LEDs: 2.9 ms latency, ~344 fps
            WS2801_LEDS_CLK_PERIOD  => 1000.0
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            MODE        => MODE,
            
            LED_VSYNC       => LED_VSYNC,
            LED_RGB         => LED_RGB,
            LED_RGB_WR_EN   => LED_RGB_WR_EN,
            
            LEDS_CLK    => LEDS_CLK,
            LEDS_DATA   => LEDS_DATA
        );
    
    -- Stimulus process
    stim_proc: process
        variable r, g, b    : std_ulogic_vector(7 downto 0);
    begin
        -- hold reset state for 100 ns.
        RST <= '1';
        wait for 100 ns;
        RST <= '0';
        wait for CLK_PERIOD*10;
        wait until rising_edge(CLK);

        -- set 100 test colors
        
        for mode_i in 0 to 3 loop
            
            MODE        <= stdulv(mode_i, 2);
            LED_VSYNC   <= '0';
            
            r   := x"FF";
            g   := x"00";
            b   := x"7F";
            
            for i in 0 to 99 loop
                
                LED_RGB         <= r & g & b;
                LED_RGB_WR_EN   <= '1';
                wait until rising_edge(CLK);
                LED_RGB_WR_EN   <= '0';
                wait for CLK_PERIOD*100;
                
                r   := r-1;
                g   := g+1;
                b   := b+1;
                
            end loop;
            
            LED_VSYNC   <= '1';
            wait for 100*24*2.5 us + 100*CLK_PERIOD;
            wait until rising_edge(CLK);
        
        end loop;
        
        report "NONE. All tests successful, quitting"
            severity FAILURE;
    end process;

END;
