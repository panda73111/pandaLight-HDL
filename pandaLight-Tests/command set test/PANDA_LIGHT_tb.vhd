library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.help_funcs.all;
use work.txt_util.all;
use work.transport_layer_pkg.all;
use work.mcs_parser.all;
use work.linked_list.all;

entity testbench is
end testbench;

architecture behavior of testbench is
    
    constant VERBOSE    : boolean := false;

    signal g_clk20  : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    -- USB UART
    signal USB_RXD  : std_ulogic := '1';
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
    
    USB_RXD <= txd;
    rxd     <= USB_TXD;
    
    USB_CTSN    <= '0';
    
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
            BYTE_COUNT      => 1024*1024, -- 8 MBit
            INIT_FILE_PATH  => "../pandaLight.mcs",
            VERBOSE         => VERBOSE
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
            x"10_60_E2_80_0F_10_09_80_A9_E2_08_1D_00_00_00_00" &
            x"20_00_00_FF_00_FF_00_FF_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"01_01_01_01_01_01_01_02_02_02_02_02_03_03_03_03" &
            x"04_04_04_04_05_05_05_05_06_06_06_07_07_07_08_08" &
            x"09_09_09_0A_0A_0B_0B_0B_0C_0C_0D_0D_0E_0E_0F_0F" &
            x"10_10_11_11_12_12_13_13_14_14_15_16_16_17_17_18" &
            x"19_19_1A_1B_1B_1C_1D_1D_1E_1F_1F_20_21_21_22_23" &
            x"24_24_25_26_27_28_28_29_2A_2B_2C_2C_2D_2E_2F_30" &
            x"31_32_32_33_34_35_36_37_38_39_3A_3B_3C_3D_3E_3F" &
            x"40_41_42_43_44_45_46_47_48_49_4A_4B_4C_4D_4F_50" &
            x"51_52_53_54_55_57_58_59_5A_5B_5D_5E_5F_60_61_63" &
            x"64_65_66_68_69_6A_6C_6D_6E_70_71_72_74_75_76_78" &
            x"79_7A_7C_7D_7F_80_81_83_84_86_87_89_8A_8C_8D_8F" &
            x"90_92_93_95_96_98_99_9B_9C_9E_A0_A1_A3_A4_A6_A8" &
            x"A9_AB_AC_AE_B0_B1_B3_B5_B6_B8_BA_BC_BD_BF_C1_C3" &
            x"C4_C6_C8_CA_CB_CD_CF_D1_D3_D4_D6_D8_DA_DC_DE_E0" &
            x"E1_E3_E5_E7_E9_EB_ED_EF_F1_F3_F5_F7_F9_FB_FD_FF" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"01_01_01_01_01_01_01_02_02_02_02_02_03_03_03_03" &
            x"04_04_04_04_05_05_05_05_06_06_06_07_07_07_08_08" &
            x"09_09_09_0A_0A_0B_0B_0B_0C_0C_0D_0D_0E_0E_0F_0F" &
            x"10_10_11_11_12_12_13_13_14_14_15_16_16_17_17_18" &
            x"19_19_1A_1B_1B_1C_1D_1D_1E_1F_1F_20_21_21_22_23" &
            x"24_24_25_26_27_28_28_29_2A_2B_2C_2C_2D_2E_2F_30" &
            x"31_32_32_33_34_35_36_37_38_39_3A_3B_3C_3D_3E_3F" &
            x"40_41_42_43_44_45_46_47_48_49_4A_4B_4C_4D_4F_50" &
            x"51_52_53_54_55_57_58_59_5A_5B_5D_5E_5F_60_61_63" &
            x"64_65_66_68_69_6A_6C_6D_6E_70_71_72_74_75_76_78" &
            x"79_7A_7C_7D_7F_80_81_83_84_86_87_89_8A_8C_8D_8F" &
            x"90_92_93_95_96_98_99_9B_9C_9E_A0_A1_A3_A4_A6_A8" &
            x"A9_AB_AC_AE_B0_B1_B3_B5_B6_B8_BA_BC_BD_BF_C1_C3" &
            x"C4_C6_C8_CA_CB_CD_CF_D1_D3_D4_D6_D8_DA_DC_DE_E0" &
            x"E1_E3_E5_E7_E9_EB_ED_EF_F1_F3_F5_F7_F9_FB_FD_FF" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"01_01_01_01_01_01_01_02_02_02_02_02_03_03_03_03" &
            x"04_04_04_04_05_05_05_05_06_06_06_07_07_07_08_08" &
            x"09_09_09_0A_0A_0B_0B_0B_0C_0C_0D_0D_0E_0E_0F_0F" &
            x"10_10_11_11_12_12_13_13_14_14_15_16_16_17_17_18" &
            x"19_19_1A_1B_1B_1C_1D_1D_1E_1F_1F_20_21_21_22_23" &
            x"24_24_25_26_27_28_28_29_2A_2B_2C_2C_2D_2E_2F_30" &
            x"31_32_32_33_34_35_36_37_38_39_3A_3B_3C_3D_3E_3F" &
            x"40_41_42_43_44_45_46_47_48_49_4A_4B_4C_4D_4F_50" &
            x"51_52_53_54_55_57_58_59_5A_5B_5D_5E_5F_60_61_63" &
            x"64_65_66_68_69_6A_6C_6D_6E_70_71_72_74_75_76_78" &
            x"79_7A_7C_7D_7F_80_81_83_84_86_87_89_8A_8C_8D_8F" &
            x"90_92_93_95_96_98_99_9B_9C_9E_A0_A1_A3_A4_A6_A8" &
            x"A9_AB_AC_AE_B0_B1_B3_B5_B6_B8_BA_BC_BD_BF_C1_C3" &
            x"C4_C6_C8_CA_CB_CD_CF_D1_D3_D4_D6_D8_DA_DC_DE_E0" &
            x"E1_E3_E5_E7_E9_EB_ED_EF_F1_F3_F5_F7_F9_FB_FD_FF";
        constant BITFILE_MCS_PATH   : string := "../PANDA_LIGHT.bit.mcs";
        constant CRLF               : string := CR & LF;
        variable cmd_buf            : string(1 to 128);
        variable cmd_len            : natural;
        variable tl_packet_i        : natural;
        
        function wrap_as_tl_packet(
            packet_num  : in natural;
            v           : in std_ulogic_vector)
        return std_ulogic_vector is
            variable tmp        : std_ulogic_vector(v'length+4*8-1 downto 0);
            variable checksum   : std_ulogic_vector(7 downto 0);
        begin
            tmp(tmp'high downto tmp'high-7)     := DATA_MAGIC;
            tmp(tmp'high-8 downto tmp'high-15)  := stdulv(packet_num, 8);
            tmp(tmp'high-16 downto tmp'high-23) := stdulv(v'length/8-1, 8);
            tmp(tmp'high-24 downto 8)           := v;
            checksum                            := DATA_MAGIC+packet_num+v'length/8-1;
            for i in v'length/8+1 downto 2 loop
                checksum    := checksum+tmp(i*8-1 downto i*8-8);
            end loop;
            tmp(7 downto 0) := checksum;
            return tmp;
        end function;
        
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
        
        procedure send_wrapped_mcs_file_to_b(
            path        : in string;
            tl_packet_i : inout natural;
            packet_size : in positive
        ) is
            variable list           : ll_item_pointer_type;
            variable mcs_valid      : boolean;
            variable mcs_addr       : std_ulogic_vector(31 downto 0);
            variable prev_mcs_addr  : std_ulogic_vector(31 downto 0);
            variable mcs_byte       : std_ulogic_vector(7 downto 0);
            variable v              : std_ulogic_vector(packet_size*8-1 downto 0);
            variable i              : natural;
        begin
            mcs_init(path, list, VERBOSE);
            
            i   := 255;
            mcs_read_byte(list, mcs_addr, mcs_byte, mcs_valid, VERBOSE);
            prev_mcs_addr   := mcs_addr-1;
            
            while mcs_valid loop
                
                assert mcs_addr=prev_mcs_addr+1
                    report "Bitfile .mcs file contains non-sequential data"
                    severity FAILURE;
                
                v(i*8+7 downto i*8) := mcs_byte;
                
                if i=0 then
                    send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, v));
                    tl_packet_i := tl_packet_i+1;
                    i   := 255;
                else
                    i   := i-1;
                end if;
                
                prev_mcs_addr   := mcs_addr;
                mcs_read_byte(list, mcs_addr, mcs_byte, mcs_valid, VERBOSE);
                
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
        
        main_loop : loop
                    
            tl_packet_i := 0;
            
            -- send "send system information via UART" request to the module (device B)
            report "Sending 'send system information via UART' request";
            send_string_to_b("+RDAI=005,");
            send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, x"00"));
            send_string_to_b(CRLF);
            wait for 2 ms;
            
            tl_packet_i := tl_packet_i+1;
            
            -- send "load settings from flash" request to the module (device B)
            report "Sending 'load settings from flash' request";
            send_string_to_b("+RDAI=005,");
            send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, x"20"));
            send_string_to_b(CRLF);
            wait for 2 ms;
            
            tl_packet_i := tl_packet_i+1;
            
            -- send "save settings to flash" request to the module (device B)
            report "Sending 'save settings to flash' request";
            send_string_to_b("+RDAI=005,");
            send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, x"21"));
            send_string_to_b(CRLF);
            wait for 2 ms;
            
            tl_packet_i := tl_packet_i+1;
            
            -- send "receive settings from UART" request to the module (device B)
            report "Sending 'receive settings from UART' request";
            send_string_to_b("+RDAI=005,");
            send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, x"22"));
            send_string_to_b(CRLF);
            for block_i in 4 downto 1 loop
                send_string_to_b("+RDAI=260,");
                send_bytes_to_b(wrap_as_tl_packet(tl_packet_i,
                    TEST_SETTINGS(block_i*256*8-1 downto (block_i-1)*256*8)));
                send_string_to_b(CRLF);
            
                tl_packet_i := tl_packet_i+1;
            end loop;
            wait for 2 ms;
            
            -- send "send settings to UART" request to the module (device B)
            report "Sending 'send settings to UART' request";
            send_string_to_b("+RDAI=005,");
            send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, x"23"));
            send_string_to_b(CRLF);
            wait for 2 ms;
            
            tl_packet_i := tl_packet_i+1;
            
           -- send "receive bitfile from UART" (RX0 bitfile) request to the module (device B)
           report "Sending 'send settings to UART' request";
           send_string_to_b("+RDAI=005,");
           send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, x"40"));
           send_string_to_b(CRLF);
           send_wrapped_mcs_file_to_b(BITFILE_MCS_PATH, tl_packet_i, 256);
           wait for 2 ms;
           
           tl_packet_i := tl_packet_i+1;
           
           -- send "send bitfile to UART" (RX0 bitfile) request to the module (device B)
           report "Sending 'send settings to UART' request";
           send_string_to_b("+RDAI=005,");
           send_bytes_to_b(wrap_as_tl_packet(tl_packet_i, x"41"));
           send_string_to_b(CRLF);
           wait for 2 ms;
            
            report "NONE. All tests completed."
                severity FAILURE;
            
        end loop;
        
        wait;
    end process;
    
end;