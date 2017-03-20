library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;

entity testbench is
end testbench;

architecture behavior of testbench is

    signal g_clk20  : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    -- Outputs
    signal LEDS_CLK     : std_ulogic_vector(1 downto 0);
    signal LEDS_DATA    : std_ulogic_vector(1 downto 0);
    
    signal PMOD0    : std_ulogic_vector(3 downto 0);
    
    constant G_CLK20_PERIOD : time := 50 ns;
    
begin
    
    g_clk20 <= not g_clk20 after G_CLK20_PERIOD/2;
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => g_clk20,
        
        LEDS_CLK    => LEDS_CLK,
        LEDS_DATA   => LEDS_DATA,
        
        PMOD0   => PMOD0
    );
    
    process
    begin
        g_rst   <= '1';
        wait for 200 ns;
        g_rst   <= '0';
        
        wait for 1.5 ms;
        
        report "NONE. All tests completed."
            severity FAILURE;
    end process;
    
end;