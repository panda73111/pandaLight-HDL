--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   09:03:26 08/04/2014
-- Module Name:   LED_CORRECTION_tb.vhd
-- Project Name:  LED_CORRECTION
-- Tool versions: Xilinx ISE 14.7
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: LED_CORRECTION
-- 
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments:
--  
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;
 
ENTITY LED_CORRECTION_tb IS
END LED_CORRECTION_tb;
 
ARCHITECTURE behavior OF LED_CORRECTION_tb IS 

    --Inputs
    signal clk  : std_ulogic := '0';
    signal rst  : std_ulogic := '0';
    
    signal cfg_addr     : std_ulogic_vector(1 downto 0) := (others => '0');
    signal cfg_wr_en    : std_ulogic := '0';
    signal cfg_data     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal led_in_vsync : std_ulogic := '0';
    signal led_in_num   : std_ulogic_vector(7 downto 0) := x"00";
    signal led_in_rgb   : std_ulogic_vector(23 downto 0) := x"000000";
    signal led_in_wr_en : std_ulogic := '0';

    --outputs
    signal led_out_vsync    : std_ulogic := '0';
    signal led_out_rgb      : std_ulogic_vector(23 downto 0) := x"000000";
    signal led_out_valid    : std_ulogic := '0';

    -- Clock period definitions
    constant clk_period : time := 10 ns;
    
    type mode_type is (RGB, RBG, GRB, GBR, BRG, BGR);
    signal cur_mode : mode_type := RGB;
    signal cur_start_led_num    : natural range 0 to 255 := 0;
    signal cur_frame_delay      : natural range 0 to 255 := 0;
    
BEGIN
    
    LED_CORRECTION_inst : entity work.LED_CORRECTION
        generic map (
            MAX_LED_COUNT   => 128,
             -- 32 frames = ~1 second of delay at 30 fps
            MAX_FRAME_COUNT => 32
        )
        port map (
            CLK => clk,
            RST => rst,
            
            CFG_ADDR    => cfg_addr,
            CFG_WR_EN   => cfg_wr_en,
            CFG_DATA    => cfg_data,
            
            LED_IN_VSYNC    => led_in_vsync,
            LED_IN_NUM      => led_in_num,
            LED_IN_RGB      => led_in_rgb,
            LED_IN_WR_EN    => led_in_wr_en,
            
            LED_OUT_VSYNC   => led_out_vsync,
            LED_OUT_RGB     => led_out_rgb,
            LED_OUT_VALID   => led_out_valid
        );
    
    
    clk <= not clk after clk_period/2;
    
    -- Stimulus process
    stim_proc: process
        variable r, g, b    : std_ulogic_vector(7 downto 0);
        
        procedure configure(
            addr : in std_ulogic_vector(1 downto 0);
            data : in std_ulogic_vector(7 downto 0)) is
        begin
            cfg_addr    <= addr;
            cfg_wr_en   <= '1';
            cfg_data    <= data;
            wait until rising_edge(clk);
            cfg_wr_en   <= '0';
        end procedure;
    begin
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for CLK_period*10;
        wait until rising_edge(clk);
        
        -- set 50 test colors
        led_in_vsync    <= '1';
        configure("00", stdulv(50, 8));
        
        for mode_i in 0 to 5 loop
            cur_mode    <= mode_type'val(mode_i);
            
            configure("11", stdulv(mode_i, 8));
            
            for start_led_num in 0 to 49 loop
                cur_start_led_num   <= start_led_num;
                
                configure("01", stdulv(start_led_num, 8));
                
                for frame_delay in 0 to 29 loop
                    cur_frame_delay <= frame_delay;
                    
                    configure("10", stdulv(frame_delay, 8));
                    
                    for frame_i in 0 to 199 loop
                        led_in_vsync    <= '0';
                        
                        r   := x"FF";
                        g   := x"00";
                        b   := x"7F";
                        
                        led_in_wr_en    <= '1';
                        for led_i in 0 to 49 loop
                            
                            led_in_num  <= stdulv(led_i, 8);
                            led_in_rgb  <= r & g & b;
                            wait until rising_edge(clk);
                            
                            r   := r-1;
                            g   := g+1;
                            b   := b+1;
                            
                        end loop;
                        led_in_wr_en    <= '0';
                        
                        led_in_vsync   <= '1';
                        wait for 100*clk_period;
                        wait until rising_edge(clk);
                    end loop;
                end loop;
            end loop;
        end loop;
        
        report "NONE. All tests successful, quitting" severity FAILURE;
    end process;
    
END;
