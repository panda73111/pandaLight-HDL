library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;

entity testbench is
end testbench;

architecture behavior of testbench is

    signal g_clk20  : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    -- SPI Flash
    signal FLASH_MISO   : std_ulogic := '0';
    signal FLASH_MOSI   : std_ulogic;
    signal FLASH_CS     : std_ulogic;
    signal FLASH_SCK    : std_ulogic;
    
    -- PMOD
    signal PMOD0    : std_ulogic_vector(3 downto 0) := x"0";
    
    constant G_CLK20_PERIOD : time := 50 ns;
    
begin
    
    g_clk20 <= not g_clk20 after G_CLK20_PERIOD/2;
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => g_clk20,
        
        FLASH_MISO  => FLASH_MISO,
        FLASH_MOSI  => FLASH_MOSI,
        FLASH_CS    => FLASH_CS,
        FLASH_SCK   => FLASH_SCK,
        
        PMOD0   => PMOD0
    );
    
    process
    begin
        g_rst   <= '1';
        wait for 200 ns;
        g_rst   <= '0';
        
        wait;
    end process;
    
end;