----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    10:28:37 01/20/2015 
-- Module Name:    UART_BLUETOOTH_MODULE_tb - behaviour 
-- Project Name:   UART_BLUETOOTH_MODULE
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity UART_BLUETOOTH_CONTROL_tb is
end UART_BLUETOOTH_CONTROL_tb;

architecture behaviour of UART_BLUETOOTH_CONTROL_tb is
    
    -- inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal BT_CTS   : std_ulogic := '0';
    signal BT_RXD   : std_ulogic := '0';
    
    -- outputs
    signal BT_RTS   : std_ulogic;
    signal BT_TXD   : std_ulogic;
    signal BT_WAKE  : std_ulogic;
    signal BT_RSTN  : std_ulogic;
    
    signal BUSY     : std_ulogic;
    
    -- clock period definitions
    constant CLK_PERIOD         : time := 10 ns;
    constant CLK_PERIOD_REAL    : real := real(CLK_PERIOD / 1 ps) / real(1 ns / 1 ps);
    
begin
    
    UART_BLUETOOTH_CONTROL_inst : entity work.UART_BLUETOOTH_CONTROL
        generic map (
            CLK_IN_PERIOD   => CLK_PERIOD_REAL
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            BT_CTS  => BT_CTS,
            BT_RTS  => BT_RTS,
            BT_TXD  => BT_TXD,
            BT_RXD  => BT_RXD,
            BT_WAKE => BT_WAKE,
            BT_RSTN => BT_RSTN,
            
            BUSY    => BUSY
        );
    
    CLK <= not CLK after CLK_PERIOD/2;
    
    stim_proc : process
    begin
        RST <= '1';
        wait for 200 ns;
        RST <= '0';
        wait for 200 ns;
        
        wait;
    end process;
    
end behaviour;
