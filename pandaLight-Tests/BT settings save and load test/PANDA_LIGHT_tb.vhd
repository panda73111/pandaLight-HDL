library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;
use work.txt_util.all;
use work.transport_layer_pkg.all;

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
    
    -- SPI Flash
    signal FLASH_MISO   : std_ulogic := '0';
    signal FLASH_MOSI   : std_ulogic;
    signal FLASH_CS     : std_ulogic;
    signal FLASH_SCK    : std_ulogic;
    
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
        
        -- SPI Flash
        FLASH_MISO  => FLASH_MISO,
        FLASH_MOSI  => FLASH_MOSI,
        FLASH_SCK   => FLASH_SCK,
        FLASH_CS    => FLASH_CS,
        
        PMOD0   => PMOD0,
        PMOD1   => PMOD1
    );
    
    test_spi_flash_inst : entity work.test_spi_flash
        generic map (
            BYTE_COUNT      => 1024*1024,
            INIT_FILE_PATH  => "../settings.bin",
            INIT_ADDR       => x"060000",
            VERBOSE         => false
        )
        port map (
            MISO    => FLASH_MOSI,
            MOSI    => FLASH_MISO,
            C       => FLASH_SCK,
            SN      => FLASH_CS
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
        constant TEST_SETTINGS  : std_ulogic_vector(1024*8-1 downto 0) :=
            x"10_60_e2_80_0f_10_09_80_a9_e2_08_1d_20_20_20_20" &
            x"2c_20_20_ff_20_ff_20_ff_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_01_01_01_01_01_01_01_01_01_01_02_02_02_02" &
            x"02_02_02_03_03_03_03_03_03_04_04_04_04_04_05_05" &
            x"05_05_06_06_06_07_07_07_07_08_08_08_09_09_09_0a" &
            x"0a_0a_0b_0b_0c_0c_0c_0d_0d_0e_0e_0e_0f_0f_10_10" &
            x"11_11_12_12_13_13_14_15_15_16_16_17_18_18_19_19" &
            x"1a_1b_1b_1c_1d_1d_1e_1f_20_20_21_22_23_23_24_25" &
            x"26_27_27_28_29_2a_2b_2c_2d_2e_2f_30_31_31_32_33" &
            x"34_35_37_38_39_3a_3b_3c_3d_3e_3f_40_42_43_44_45" &
            x"46_47_49_4a_4b_4d_4e_4f_50_52_53_54_56_57_59_5a" &
            x"5b_5d_5e_60_61_63_64_66_67_69_6b_6c_6e_6f_71_73" &
            x"74_76_78_79_7b_7d_7f_80_82_84_86_88_8a_8b_8d_8f" &
            x"91_93_95_97_99_9b_9d_9f_a1_a3_a5_a7_a9_ac_ae_b0" &
            x"b2_b4_b6_b9_bb_bd_c0_c2_c4_c6_c9_cb_ce_d0_d2_d5" &
            x"d7_da_dc_df_e1_e4_e7_e9_ec_ee_f1_f4_f6_f9_fc_ff" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_01_01_01_01_01_01_01_01_01_01_02_02_02_02" &
            x"02_02_02_03_03_03_03_03_03_04_04_04_04_04_05_05" &
            x"05_05_06_06_06_07_07_07_07_08_08_08_09_09_09_0a" &
            x"0a_0a_0b_0b_0c_0c_0c_0d_0d_0e_0e_0e_0f_0f_10_10" &
            x"11_11_12_12_13_13_14_15_15_16_16_17_18_18_19_19" &
            x"1a_1b_1b_1c_1d_1d_1e_1f_20_20_21_22_23_23_24_25" &
            x"26_27_27_28_29_2a_2b_2c_2d_2e_2f_30_31_31_32_33" &
            x"34_35_37_38_39_3a_3b_3c_3d_3e_3f_40_42_43_44_45" &
            x"46_47_49_4a_4b_4d_4e_4f_50_52_53_54_56_57_59_5a" &
            x"5b_5d_5e_60_61_63_64_66_67_69_6b_6c_6e_6f_71_73" &
            x"74_76_78_79_7b_7d_7f_80_82_84_86_88_8a_8b_8d_8f" &
            x"91_93_95_97_99_9b_9d_9f_a1_a3_a5_a7_a9_ac_ae_b0" &
            x"b2_b4_b6_b9_bb_bd_c0_c2_c4_c6_c9_cb_ce_d0_d2_d5" &
            x"d7_da_dc_df_e1_e4_e7_e9_ec_ee_f1_f4_f6_f9_fc_ff" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_20_20_20_20_20_20_20_20_20_20_20_20_20_20" &
            x"20_20_01_01_01_01_01_01_01_01_01_01_02_02_02_02" &
            x"02_02_02_03_03_03_03_03_03_04_04_04_04_04_05_05" &
            x"05_05_06_06_06_07_07_07_07_08_08_08_09_09_09_0a" &
            x"0a_0a_0b_0b_0c_0c_0c_0d_0d_0e_0e_0e_0f_0f_10_10" &
            x"11_11_12_12_13_13_14_15_15_16_16_17_18_18_19_19" &
            x"1a_1b_1b_1c_1d_1d_1e_1f_20_20_21_22_23_23_24_25" &
            x"26_27_27_28_29_2a_2b_2c_2d_2e_2f_30_31_31_32_33" &
            x"34_35_37_38_39_3a_3b_3c_3d_3e_3f_40_42_43_44_45" &
            x"46_47_49_4a_4b_4d_4e_4f_50_52_53_54_56_57_59_5a" &
            x"5b_5d_5e_60_61_63_64_66_67_69_6b_6c_6e_6f_71_73" &
            x"74_76_78_79_7b_7d_7f_80_82_84_86_88_8a_8b_8d_8f" &
            x"91_93_95_97_99_9b_9d_9f_a1_a3_a5_a7_a9_ac_ae_b0" &
            x"b2_b4_b6_b9_bb_bd_c0_c2_c4_c6_c9_cb_ce_d0_d2_d5" &
            x"d7_da_dc_df_e1_e4_e7_e9_ec_ee_f1_f4_f6_f9_fc_ff";
        constant CRLF           : string := CR & LF;
        variable cmd_buf        : string(1 to 128);
        variable cmd_len        : natural;
        
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
        
        function wrap_as_tl_packet(packet_num : in natural; v : in std_ulogic_vector) return std_ulogic_vector is
            variable tmp        : std_ulogic_vector(v'length+4*8-1 downto 0);
            variable checksum   : std_ulogic_vector(7 downto 0);
        begin
            tmp(tmp'high downto tmp'high-7)     := DATA_MAGIC;
            tmp(tmp'high-8 downto tmp'high-15)  := stdulv(packet_num, 8);
            tmp(tmp'high-16 downto tmp'high-23) := stdulv(v'length/8, 8);
            tmp(tmp'high-24 downto 8)           := v;
            checksum                            := DATA_MAGIC+packet_num+v'length/8;
            for i in v'length/8+1 downto 2 loop
                checksum    := checksum+tmp(i*8-1 downto i*8-8);
            end loop;
            tmp(7 downto 0) := checksum;
            return tmp;
        end function;
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
                    send_string_to_b("+RCCRCNF=500," & SERVICE_UUID & ",0" & CRLF);
                    send_string_to_b("+RSNFCNF=0320,2" & CRLF);
                    send_string_to_b("+ESNS=0320,0320,0000,0002" & CRLF);
                    wait for 10 ms;
                    
                    -- send "load settings from flash" request to the module (device B)
                    report "Sending 'load settings from flash' request";
                    send_string_to_b("+RDAI=005,");
                    send_bytes_to_b(wrap_as_tl_packet(0, x"20"));
                    send_string_to_b(CRLF);
                    wait for 10 ms;
                    
                    -- send "save settings to flash" request to the module (device B)
                    report "Sending 'save settings to flash' request";
                    send_string_to_b("+RDAI=005,");
                    send_bytes_to_b(wrap_as_tl_packet(1, x"21"));
                    send_string_to_b(CRLF);
                    wait for 10 ms;
                    
                    -- send "receive settings from UART" request to the module (device B)
                    report "Sending 'receive settings from UART' request";
                    send_string_to_b("+RDAI=500,");
                    send_bytes_to_b(wrap_as_tl_packet(2, x"22" & TEST_SETTINGS(1024*8-1 downto 529*8)));
                    send_string_to_b(CRLF);
                    send_string_to_b("+RDAI=500,");
                    send_bytes_to_b(wrap_as_tl_packet(3, TEST_SETTINGS(529*8-1 downto 33*8)));
                    send_string_to_b(CRLF);
                    send_string_to_b("+RDAI=37,");
                    send_bytes_to_b(wrap_as_tl_packet(4, TEST_SETTINGS(33*8-1 downto 0)));
                    send_string_to_b(CRLF);
                    wait for 10 ms;
                    
                    -- send "send settings to UART" request to the module (device B)
                    report "Sending 'send settings to UART' request";
                    send_string_to_b("+RDAI=005,");
                    send_bytes_to_b(wrap_as_tl_packet(5, x"23"));
                    send_string_to_b(CRLF);
                    wait for 10 ms;
                    
                    -- disconnect
                    report "Disconnecting";
                    send_string_to_b("+RDII" & CRLF);
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