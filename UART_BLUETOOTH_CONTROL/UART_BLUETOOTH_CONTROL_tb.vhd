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
    constant CLK_PERIOD         : time := 100 ns; -- 2.5 MHz
    constant CLK_PERIOD_REAL    : real := real(CLK_PERIOD / 1 ps) / real(1 ns / 1 ps);
    
    constant UART_CLK_PERIOD    : time := 1 sec / 115_200;
    
    signal rxd, txd : std_ulogic := '0';
    
    signal tx_data      : std_ulogic_vector(7 downto 0) := x"00";
    signal tx_wr_en     : std_ulogic := '0';
    signal tx_wr_ack    : std_ulogic := '0';
    
    signal rx_data  : std_ulogic_vector(7 downto 0) := x"00";
    signal rx_valid : std_ulogic := '0';
    
begin
    
    BT_RXD  <= txd;
    rxd     <= BT_TXD;
    
    BT_CTS  <= '1';
    
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
    
    tx_proc : process
    begin
        txd <= '1';
        wait until tx_wr_en='1';
        while tx_wr_en='1' loop
            -- start bit
            txd <= '0';
            wait for UART_CLK_PERIOD;
            for i in 0 to 7 loop
                txd <= tx_data(i);
                wait for UART_CLK_PERIOD;
            end loop;
            -- stop bit
            txd         <= '1';
            tx_wr_ack   <= '1';
            wait for UART_CLK_PERIOD;
            tx_wr_ack   <= '0';
        end loop;
    end process;
    
    rx_proc : process
    begin
        wait until rxd='0';
        rx_valid    <= '0';
        -- start bit
        wait for UART_CLK_PERIOD;
        wait for UART_CLK_PERIOD/2;
        for i in 0 to 7 loop
            rx_data(i)  <= rxd;
            wait for UART_CLK_PERIOD;
        end loop;
        assert rxd='1'
            report "Didn't get stop bit!"
            severity FAILURE;
        rx_valid    <= '1';
    end process;
    
    stim_proc : process
        constant BT_ADDR    : string := "05A691C102E8"; -- (random)
        constant CRLF       : string := CR & LF;
        variable cmd_buf    : string(1 to 128);
        variable cmd_len    : natural;
        
        procedure send_char(c : in character) is
        begin
            tx_data     <= stdulv(c);
            tx_wr_en    <= '1';
            wait for UART_CLK_PERIOD;
            tx_wr_en    <= '0';
            wait until tx_wr_ack='1';
        end procedure;
        
        procedure send_string(s : in string) is
        begin
            for i in s'range loop
                send_char(s(i));
            end loop;
        end procedure;
        
        procedure get_cmd(s : out string; len : out natural) is
            variable tmp    : string(1 to 128);
            variable char_i : natural;
        begin
            char_i  := 3;
            while tmp(char_i-2 to char_i-1)/=CRLF loop
                wait until rx_valid='1';
                tmp(char_i) := character'val(int(rx_data));
                char_i      := char_i+1;
            end loop;
            report "Got command: " & tmp(3 to char_i-3);
            len                 := char_i-5;
            s(1 to char_i-5)    := tmp(3 to char_i-3);
        end procedure;
    begin
        RST <= '1';
        wait for 200 ns;
        RST <= '0';
        wait for 200 ns;
        
        if BT_RSTN='0' then
            wait until BT_RSTN='1';
        end if;
        -- boot complete
        send_string("ROK" & CRLF);
        
        loop
            get_cmd(cmd_buf, cmd_len);
            case cmd_buf(1 to 7) is
                when "AT+JSEC"  => send_string("OK" & CRLF);
                when "AT+JSLN"  => send_string("OK" & CRLF);
                when "AT+JRLS"  => send_string("OK" & CRLF);
                when "AT+JDIS"  => send_string("OK" & CRLF);
                when "AT+JAAC"  => send_string("OK" & CRLF);
                    -- test a connection
                    wait for 1 ms;
                    send_string("+RCOI=" & BT_ADDR & CRLF);
                when others =>
                    report "Unknown command!"
                    severity FAILURE;
            end case;
        end loop;
        
        wait;
    end process;
    
end behaviour;
