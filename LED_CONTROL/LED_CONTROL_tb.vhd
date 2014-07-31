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
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments:
--  
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.math_real.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

ENTITY LED_CONTROL_tb IS
END LED_CONTROL_tb;

ARCHITECTURE behavior OF LED_CONTROL_tb IS

    --Inputs
    signal clk  : std_ulogic := '0';
    signal rst  : std_ulogic := '0';
    
    signal mode         : std_ulogic_vector(0 downto 0) := (others => '0');
    signal vsync        : std_ulogic := '0';
    signal rgb          : std_ulogic_vector(23 downto 0) := (others => '0');
    signal rgb_wr_en    : std_ulogic := '0';

    --outputs
    signal leds_clk     : std_ulogic;
    signal leds_data    : std_ulogic;

    -- clock period definitions
    constant clk_period : time := 10 ns;
    
    constant clk_period_real    : real := real(clk_period / 1 ps) / real(1 ns / 1 ps);

BEGIN
    
    -- clock generation
    clk <= not clk after clk_period / 2;

    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD           => clk_period_real,
            -- 1 MHz, 100 LEDs: 2.9 ms latency, ~344 fps
            WS2801_LEDS_CLK_PERIOD  => 1000.0
        )
        port map (
            CLK => clk,
            RST => rst,
            
            MODE        => mode,
            VSYNC       => vsync,
            RGB         => rgb,
            RGB_WR_EN   => rgb_wr_en,
            
            LEDS_CLK    => leds_clk,
            LEDS_DATA   => leds_data
        );
    
    -- Stimulus process
    stim_proc: process
        variable r, g, b    : std_ulogic_vector(7 downto 0);
    begin
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for clk_period*10;
        wait until rising_edge(clk);

        -- set 100 test colors
        
        for mode_i in 0 to 1 loop
            
            mode    <= stdulv(mode_i, 1);
            vsync   <= '1';
            
            r   := x"FF";
            g   := x"00";
            b   := x"7F";
            
            for i in 0 to 99 loop
                
                rgb         <= r & g & b;
                rgb_wr_en   <= '1';
                wait until rising_edge(clk);
                rgb_wr_en   <= '0';
                wait for clk_period*100;
                
                r   := r-1;
                g   := g+1;
                b   := b+1;
                
            end loop;
            
            vsync   <= '0';
            wait for 100*24*2.5 us + 100*clk_period;
            wait until rising_edge(clk);
        
        end loop;
        
        report "NONE. All tests successful, quitting" severity FAILURE;
    end process;

END;
