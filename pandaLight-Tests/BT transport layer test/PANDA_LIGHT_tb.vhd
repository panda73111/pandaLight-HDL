library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;
use work.txt_util.all;

entity testbench is
end testbench;

architecture behavior of testbench is

    signal g_clk20  : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    -- USB UART
    signal USB_RXD  : std_ulogic := '0';
    signal USB_TXD  : std_ulogic := '1';
    signal USB_CTSN : std_ulogic := '0';
    signal USB_RTSN : std_ulogic := '0';
    signal USB_DSRN : std_ulogic := '0';
    signal USB_DTRN : std_ulogic := '0';
    signal USB_DCDN : std_ulogic := '0';
    signal USB_RIN  : std_ulogic := '0';
    
    -- BT UART
    signal BT_CTSN  : std_ulogic := '0';
    signal BT_RTSN  : std_ulogic := '0';
    signal BT_RXD   : std_ulogic := '0';
    signal BT_TXD   : std_ulogic := '1';
    signal BT_WAKE  : std_ulogic := '0';
    signal BT_RSTN  : std_ulogic := '0';
    
    -- PMOD
    signal PMOD0    : std_ulogic_vector(3 downto 0) := x"0";
    signal PMOD1    : std_ulogic_vector(3 downto 0) := x"0";
    
    constant G_CLK20_PERIOD : time := 50 ns;
    
    constant UART_CLK_PERIOD    : time := 1 sec / 115_200;
    
    signal rxd, txd : std_ulogic := '0';
    
    signal tx_data      : std_ulogic_vector(7 downto 0) := x"00";
    signal tx_wr_en     : std_ulogic := '0';
    signal tx_wr_ack    : std_ulogic := '0';
    
    signal rx_data  : std_ulogic_vector(7 downto 0) := x"00";
    signal rx_valid : std_ulogic := '0';
    
begin
    
    g_clk20 <= not g_clk20 after G_CLK20_PERIOD/2;
    
    BT_RXD  <= txd;
    rxd     <= BT_TXD;
    
    BT_CTSN <= '0';
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => g_clk20,
        
        -- USB UART
        USB_RXD     => USB_RXD,
        USB_TXD     => USB_TXD,
        USB_CTSN    => USB_CTSN,
        USB_RTSN    => USB_RTSN,
        USB_DSRN    => USB_DSRN,
        USB_DTRN    => USB_DTRN,
        USB_DCDN    => USB_DCDN,
        USB_RIN     => USB_RIN,
        
        -- BT UART
        BT_CTSN => BT_CTSN,
        BT_RTSN => BT_RTSN,
        BT_RXD  => BT_RXD,
        BT_TXD  => BT_TXD,
        BT_WAKE => BT_WAKE,
        BT_RSTN => BT_RSTN,
        
        PMOD0   => PMOD0,
        PMOD1   => PMOD1
    );
    
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
        variable tmp    : std_ulogic_vector(7 downto 0);
    begin
        wait until rxd='0';
        -- start bit
        wait for UART_CLK_PERIOD;
        wait for UART_CLK_PERIOD/2;
        for i in 0 to 6 loop
            tmp(i)  := rxd;
            wait for UART_CLK_PERIOD;
        end loop;
        tmp(7)  := rxd;
        rx_data <= tmp;
        rx_valid    <= '1';
        wait for UART_CLK_PERIOD;
        rx_valid    <= '0';
        assert rxd='1'
            report "Didn't get stop bit!"
            severity FAILURE;
    end process;
    
    stim_proc : process
        constant BT_ADDR        : string := "05A691C102E8"; -- (random)
        constant SERVICE_UUID   : string(1 to 32) := "56F46190A07D11E4BCD80800200C9A66";
        constant TEST_DATA      : std_ulogic_vector(128*8-1 downto 0) :=
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
        
        procedure send_byte_to_b(v : std_ulogic_vector(7 downto 0)) is
        begin
            tx_data     <= v;
            tx_wr_en    <= '1';
            wait for UART_CLK_PERIOD;
            tx_wr_en    <= '0';
            wait until tx_wr_ack='1';
        end procedure;
        
        procedure send_bytes_to_b(v : std_ulogic_vector) is
        begin
            for i in v'length/8 downto 1 loop
                send_byte_to_b(v(i*8-1 downto i*8-8));
            end loop;
        end procedure;
        
        procedure send_char_to_b(c : in character) is
        begin
            send_byte_to_b(stdulv(c));
        end procedure;
        
        procedure send_string_to_b(s : in string) is
        begin
            for i in s'range loop
                send_char_to_b(s(i));
            end loop;
        end procedure;
        
        procedure get_cmd_from_b(s : out string; len : out natural) is
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
        g_rst   <= '1';
        wait for 200 ns;
        g_rst   <= '0';
        wait for 200 ns;
        
        if BT_RSTN='0' then
            wait until BT_RSTN='1';
        end if;
        -- boot complete
        send_string_to_b("ROK" & CRLF);
        
        main_loop : loop
            
            get_cmd_from_b(cmd_buf, cmd_len);
            case cmd_buf(1 to 7) is
                when "AT+JSEC"  => send_string_to_b("OK" & CRLF);
                when "AT+JSLN"  => send_string_to_b("OK" & CRLF);
                when "AT+JRLS"  => send_string_to_b("OK" & CRLF);
                when "AT+JDIS"  => send_string_to_b("OK" & CRLF);
                when "AT+JAAC"  => send_string_to_b("OK" & CRLF);
                    
                    -- connect
                    wait for 10 ms;
                    report "Connecting";
                    send_string_to_b("+RSLE" & CRLF);
                    send_string_to_b("+RCOI=" & BT_ADDR & CRLF);
                    send_string_to_b("+RCCRCNF=128," & SERVICE_UUID & ",0" & CRLF);
                    send_string_to_b("+RCCRCNF=128," & SERVICE_UUID & ",0" & CRLF);
                    send_string_to_b("+RSNFCNF=0320,2" & CRLF);
                    send_string_to_b("+ESNS=0320,0320,0000,0002" & CRLF);
                    wait for 10 ms;
                    
                    -- send data to the module (device B)
                    report "Sending test data to B";
                    send_string_to_b("+RDAI=" & pad_left(TEST_DATA'length/8, 3, '0') & ",");
                    send_bytes_to_b(TEST_DATA);
                    send_string_to_b(CRLF);
                    send_string_to_b("+RDAI=" & pad_left(TEST_DATA'length/8, 3, '0') & ",");
                    send_bytes_to_b(TEST_DATA);
                    send_string_to_b(CRLF);
                    send_string_to_b("+RSNFCNF=0320,2" & CRLF);
                    send_string_to_b("+ESNS=0320,0320,0000,0002" & CRLF);
                    wait for 10 ms;
                    
                    -- disconnect
                    report "Disconnecting";
                    send_string_to_b("+RDII" & CRLF);
                    wait for 10 ms;
                    
                    -- test error
                    report "Testing error";
                    send_string_to_b("X");
                    wait until rising_edge(BT_RSTN);
                    -- boot complete
                    send_string_to_b("ROK" & CRLF);
                    wait for 10 ms;
                    
                    report "NONE. All tests completed."
                        severity FAILURE;
                    
                when others =>
                    report "Unknown command!"
                    severity FAILURE;
            end case;
        end loop;
        
        wait;
    end process;
    
end;