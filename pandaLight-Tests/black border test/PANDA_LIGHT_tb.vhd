library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.help_funcs.all;
use work.txt_util.all;

entity testbench is
end testbench;

architecture behavior of testbench is
    
    constant VERBOSE    : boolean := false;

    signal g_clk20  : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    -- HDMI
    signal RX_CHANNELS_IN_P : std_ulogic_vector(7 downto 0) := x"FF";
    signal RX_CHANNELS_IN_N : std_ulogic_vector(7 downto 0) := x"FF";
    signal RX_SDA           : std_ulogic_vector(1 downto 0) := "11";
    signal RX_SCL           : std_ulogic_vector(1 downto 0) := "11";
    signal RX_CEC           : std_ulogic_vector(1 downto 0) := "11";
    signal RX_DET           : std_ulogic_vector(1 downto 0) := "00";
    signal RX_EN            : std_ulogic_vector(1 downto 0);
    
    -- USB UART
    signal USB_RXD  : std_ulogic := '0';
    signal USB_TXD  : std_ulogic := '1';
    signal USB_CTSN : std_ulogic := '0';
    signal USB_RTSN : std_ulogic := '0';
    signal USB_DSRN : std_ulogic := '0';
    signal USB_DTRN : std_ulogic := '0';
    signal USB_DCDN : std_ulogic := '0';
    signal USB_RIN  : std_ulogic := '0';
    
    -- ESP32 UART
    signal ESP_CTS : std_ulogic := '0';
    signal ESP_RTS : std_ulogic := '0';
    signal ESP_RXD : std_ulogic := '0';
    signal ESP_TXD : std_ulogic := '1';
    signal ESP_IO0 : std_ulogic := '0';
    signal ESP_EN  : std_ulogic := '0';
    
    -- SPI Flash
    signal FLASH_MISO   : std_ulogic := '0';
    signal FLASH_MOSI   : std_ulogic := '0';
    signal FLASH_CS     : std_ulogic := '1';
    signal FLASH_SCK    : std_ulogic := '0';
    
    -- LEDs
    signal LEDS_CLK     : std_ulogic_vector(1 downto 0) := "00";
    signal LEDS_DATA    : std_ulogic_vector(1 downto 0) := "00";
    
    -- PMOD
    signal PMOD0    : std_ulogic_vector(3 downto 0) := x"0";
    signal PMOD1    : std_ulogic_vector(3 downto 0) := x"0";
    signal PMOD2    : std_ulogic_vector(3 downto 0) := x"0";
    signal PMOD3    : std_ulogic_vector(3 downto 0) := x"0";
    
    constant G_CLK20_PERIOD : time := 50 ns;
    
    constant UART_CLK_PERIOD    : time := 1 sec / 921_600;
    
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
    
    PMOD0(3)    <= '1' when g_rst='1' else 'Z';
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => g_clk20,
        
        -- HDMI
        RX_CHANNELS_IN_P    => RX_CHANNELS_IN_P,
        RX_CHANNELS_IN_N    => RX_CHANNELS_IN_N,
        RX_SDA              => RX_SDA,
        RX_SCL              => RX_SCL,
        RX_CEC              => RX_CEC,
        RX_DET              => RX_DET,
        RX_EN               => RX_EN,
        
        TX_CHANNELS_OUT_P   => open,
        TX_CHANNELS_OUT_N   => open,
        TX_SDA              => 'Z',
        TX_SCL              => 'Z',
        TX_CEC              => 'Z',
        TX_DET              => '0',
        TX_EN               => open,
        
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
        ESP_CTS => ESP_CTS,
        ESP_RTS => ESP_RTS,
        ESP_RXD => ESP_RXD,
        ESP_TXD => ESP_TXD,
        ESP_IO0 => ESP_IO0,
        ESP_EN  => ESP_EN,
        
        -- SPI Flash
        FLASH_MISO  => FLASH_MISO,
        FLASH_MOSI  => FLASH_MOSI,
        FLASH_SCK   => FLASH_SCK,
        FLASH_CS    => FLASH_CS,
        
        -- LEDs
        LEDS_CLK    => LEDS_CLK,
        LEDS_DATA   => LEDS_DATA,
        
        PMOD0   => PMOD0,
        PMOD1   => PMOD1,
        PMOD2   => PMOD2,
        PMOD3   => PMOD3
    );
    
    test_tmds_encoder_inst : entity work.test_tmds_encoder
        generic map (
            PROFILE => 0
        )
        port map (
            CHANNELS_OUT_P  => RX_CHANNELS_IN_P(3 downto 0),
            CHANNELS_OUT_N  => RX_CHANNELS_IN_N(3 downto 0)
        );
    
    test_spi_flash_inst : entity work.test_spi_flash
        generic map (
            BYTE_COUNT  => 1024*1024, -- 8 MBit
            VERBOSE     => VERBOSE
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
        constant PANDALIGHT_MAGIC   : string := "PL";
        constant TEST_SETTINGS      : std_ulogic_vector(1024*8-1 downto 0) :=
            x"10_00_5F_00_E3_00_7F_00_0E_00_0F_09_00_7F_00_AA" &
            x"00_E3_00_07_00_1C_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_20_00_00_FF_00_FF_00_FF_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00" &
            x"01_0A_0A_0A_00_02_7F_04_71_00_00_00_00_00_00_00" &
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
        
        procedure send_bytes(v : std_ulogic_vector) is
            constant BYTE_COUNT : positive := v'length/8;
            variable u  : std_ulogic_vector(v'length-1 downto 0);
            variable r  : std_ulogic_vector(v'reverse_range);
            variable b  : std_ulogic_vector(7 downto 0);
        begin
            for i in BYTE_COUNT downto 1 loop
            
                if v'ascending then
                    for j in v'range loop
                        r(v'length-j-1)   := v(j);
                    end loop;
                    u   := r;
                else
                    u   := v;
                end if;
                
                b   := u(i*8-1 downto i*8-8);
                
                tx_data     <= b;
                tx_wr_en    <= '1';
                wait for UART_CLK_PERIOD;
                tx_wr_en    <= '0';
                wait until tx_wr_ack='1';
                
            end loop;
        end procedure;
        
        procedure send_string(s : string) is
        begin
            for i in s'range loop
                send_bytes(stdulv(character'pos(s(i)), 8));
            end loop;
        end procedure;
        
        procedure send_magic is
        begin
            send_string(PANDALIGHT_MAGIC);
        end procedure;
    begin
        g_rst   <= '1';
        wait for 200 ns;
        g_rst   <= '0';
        wait for 200 ns;
        RX_DET  <= "01";
        wait for 1 ms;

        -- send "receive settings from UART" request to the module
        report "Sending 'receive settings from UART' request";
        send_magic;
        send_bytes(x"22");
        for block_i in 4 downto 1 loop
            send_bytes(TEST_SETTINGS(block_i*256*8-1 downto (block_i-1)*256*8));
        end loop;
        wait for 1 ms;

        report "NONE. All tests completed."
            severity FAILURE;

        wait;
    end process;
    
end;