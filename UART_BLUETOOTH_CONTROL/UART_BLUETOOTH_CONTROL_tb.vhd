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
use work.txt_util.all;

entity UART_BLUETOOTH_CONTROL_tb is
end UART_BLUETOOTH_CONTROL_tb;

architecture behaviour of UART_BLUETOOTH_CONTROL_tb is
    
    -- inputs
    signal CLK  : std_ulogic := '0';
    signal RST  : std_ulogic := '0';
    
    signal BT_CTS   : std_ulogic := '0';
    signal BT_RXD   : std_ulogic := '0';
    
    signal DIN          : std_ulogic_vector(7 downto 0) := x"00";
    signal DIN_WR_EN    : std_ulogic := '0';
    signal SEND_PACKET  : std_ulogic := '0';
    
    -- outputs
    signal BT_RTS   : std_ulogic;
    signal BT_TXD   : std_ulogic;
    signal BT_WAKE  : std_ulogic;
    signal BT_RSTN  : std_ulogic;
    
    signal DOUT         : std_ulogic_vector(7 downto 0);
    signal DOUT_VALID   : std_ulogic;
    
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
            
            DIN         => DIN,
            DIN_WR_EN   => DIN_WR_EN,
            SEND_PACKET => SEND_PACKET,
            
            DOUT        => DOUT,
            DOUT_VALID  => DOUT_VALID,
            
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
        constant TEST_DATA  : std_ulogic_vector(128*8-1 downto 0) :=
            x"7E_9F_76_36_BB_67_9A_51_35_34_00_E3_7B_7C_41_D2" &
            x"4A_1D_C1_E1_1F_FE_46_29_58_04_B0_3D_D7_F4_97_E3" &
            x"35_C8_5F_23_78_C6_3C_FA_63_15_F4_3F_9B_AC_32_9E" &
            x"D7_87_38_AC_C4_FF_37_A5_78_F3_95_AF_B0_C9_4E_33" &
            x"D9_C4_B2_7B_D3_35_0D_D3_D5_73_72_00_C2_B9_71_F3" &
            x"54_94_21_7E_16_28_70_BF_86_95_E5_67_EE_AD_6F_61" &
            x"C7_B6_32_80_A3_73_A3_53_36_2D_72_97_F7_DC_FF_B1" &
            x"69_28_EF_A0_3A_6E_A8_2C_A1_61_D8_20_45_32_65_4D"; -- (also random)
        constant CRLF       : string := CR & LF;
        variable cmd_buf    : string(1 to 128);
        variable cmd_len    : natural;
        
        procedure send_byte(v : std_ulogic_vector(7 downto 0)) is
        begin
            tx_data     <= v;
            tx_wr_en    <= '1';
            wait for UART_CLK_PERIOD;
            tx_wr_en    <= '0';
            wait until tx_wr_ack='1';
        end procedure;
        
        procedure send_bytes(v : std_ulogic_vector) is
        begin
            for i in v'length/8 downto 1 loop
                send_byte(v(i*8-1 downto i*8-8));
            end loop;
        end procedure;
        
        procedure send_char(c : in character) is
        begin
            send_byte(stdulv(c));
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
                    -- connect
                    wait for 10 ms;
                    report "Connecting";
                    send_string("+RCOI=" & BT_ADDR & CRLF);
                    wait for 10 ms;
                    -- send data to the module (device B)
                    report "Sending test data to B";
                    send_string("+RDAI=" & pad_left(TEST_DATA'length/8, 3, '0') & ",");
                    send_bytes(TEST_DATA);
                    send_string(CRLF);
                    wait for 10 ms;
                    -- send data to the simulated host (device A)
                    report "Sending test data to A";
                    wait until rising_edge(CLK);
                    DIN_WR_EN   <= '1';
                    for i in TEST_DATA'length/8 downto 1 loop
                        DIN <= TEST_DATA(i*8-1 downto i*8-8);
                        wait until rising_edge(CLK);
                    end loop;
                    DIN_WR_EN   <= '0';
                    wait for 10 ms;
                    -- disconnect
                    report "Disconnecting";
                    send_string("+RDII" & CRLF);
                when others =>
                    report "Unknown command!"
                    severity FAILURE;
            end case;
        end loop;
        
        wait;
    end process;
    
end behaviour;
