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
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal CFG_ADDR     : std_ulogic_vector(9 downto 0) := (others => '0');
    signal CFG_WR_EN    : std_ulogic := '0';
    signal CFG_DATA     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal LED_IN_VSYNC     : std_ulogic := '0';
    signal LED_IN_NUM       : std_ulogic_vector(7 downto 0) := x"00";
    signal LED_IN_RGB       : std_ulogic_vector(23 downto 0) := x"000000";
    signal LED_IN_RGB_WR_EN : std_ulogic := '0';

    --outputs
    signal LED_OUT_VSYNC        : std_ulogic := '0';
    signal LED_OUT_RGB          : std_ulogic_vector(23 downto 0) := x"000000";
    signal LED_OUT_RGB_VALID    : std_ulogic := '0';

    -- Clock period definitions
    constant CLK_PERIOD : time := 10 ns;
    
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
            CLK => CLK,
            RST => RST,
            
            CFG_ADDR    => CFG_ADDR,
            CFG_WR_EN   => CFG_WR_EN,
            CFG_DATA    => CFG_DATA,
            
            LED_IN_VSYNC        => LED_IN_VSYNC,
            LED_IN_NUM          => LED_IN_NUM,
            LED_IN_RGB          => LED_IN_RGB,
            LED_IN_RGB_WR_EN    => LED_IN_RGB_WR_EN,
            
            LED_OUT_VSYNC       => LED_OUT_VSYNC,
            LED_OUT_RGB         => LED_OUT_RGB,
            LED_OUT_RGB_VALID   => LED_OUT_RGB_VALID
        );
    
    
    CLK <= not CLK after CLK_PERIOD/2;
    
    -- Stimulus process
    stim_proc: process
        variable r, g, b    : std_ulogic_vector(7 downto 0);
        
        procedure configure(
            addr    : in std_ulogic_vector(9 downto 0);
            data    : in std_ulogic_vector(7 downto 0)) is
        begin
            RST         <= '1';
            CFG_ADDR    <= addr;
            CFG_WR_EN   <= '1';
            CFG_DATA    <= data;
            wait until rising_edge(CLK);
            CFG_WR_EN   <= '0';
            RST         <= '0';
        end procedure;
        
        procedure configure(
            addr    : natural;
            data    : std_ulogic_vector(7 downto 0)) is
        begin
            configure(stdulv(addr, 10), data);
        end procedure;
        
        procedure configure(
            addr    : natural;
            data    : natural) is
        begin
            configure(stdulv(addr, 10), stdulv(data, 8));
        end procedure;
    begin
        -- hold reset state for 100 ns.
        RST <= '1';
        wait for 100 ns;
        RST <= '0';
        wait for CLK_PERIOD*10;
        wait until rising_edge(CLK);
        
        LED_IN_VSYNC    <= '1';
        
        -- no correction (input color = output color)
        for ch_i in 0 to 2 loop
            for brightn in 0 to 255 loop
                configure((ch_i+1)*256+brightn, brightn);
            end loop;
        end loop;
        
        -- set 50 test colors
        configure(0, 50);
        
        -- RGB mode
        cur_mode    <= RGB;
        configure(3, 0);
        
        for start_led_num in 0 to 49 loop
            cur_start_led_num   <= start_led_num;
            
            configure(1, start_led_num);
            
            for frame_delay in 0 to 29 loop
                cur_frame_delay <= frame_delay;
                
                configure(2, frame_delay);
                
                for frame_i in 0 to 199 loop
                    LED_IN_VSYNC    <= '0';
                    
                    r   := x"FF";
                    g   := x"00";
                    b   := x"7F";
                    
                    LED_IN_RGB_WR_EN    <= '1';
                    for led_i in 0 to 49 loop
                        
                        LED_IN_NUM  <= stdulv(led_i, 8);
                        LED_IN_RGB  <= r & g & b;
                        wait until rising_edge(CLK);
                        
                        r   := r-1;
                        g   := g+1;
                        b   := b+1;
                        
                    end loop;
                    LED_IN_RGB_WR_EN    <= '0';
                    
                    LED_IN_VSYNC   <= '1';
                    wait for 100*CLK_PERIOD;
                    wait until rising_edge(CLK);
                end loop;
            end loop;
        end loop;
        
        report "NONE. All tests successful, quitting"
            severity FAILURE;
    end process;
    
END;
