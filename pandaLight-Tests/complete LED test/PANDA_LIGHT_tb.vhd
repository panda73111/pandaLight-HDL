library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;
use work.video_profiles.all;

entity testbench is
end testbench;

architecture behavior of testbench is
    
    constant VERBOSE        : boolean := false;
    constant UART_BAUD_RATE : positive := 921_600;

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
    
    signal TX_CHANNELS_OUT_P    : std_ulogic_vector(3 downto 0);
    signal TX_CHANNELS_OUT_N    : std_ulogic_vector(3 downto 0);
    signal TX_SDA               : std_ulogic := '1';
    signal TX_SCL               : std_ulogic := '1';
    signal TX_CEC               : std_ulogic := '1';
    signal TX_DET               : std_ulogic := '0';
    signal TX_EN                : std_ulogic;
    
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
    
    constant UART_CLK_PERIOD    : time := 1 sec / UART_BAUD_RATE;
    
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
    
    RX_CHANNELS_IN_P(7 downto 4)    <= RX_CHANNELS_IN_P(3 downto 0);
    RX_CHANNELS_IN_N(7 downto 4)    <= RX_CHANNELS_IN_N(3 downto 0);
    
    PANDA_LIGHT_inst : entity work.panda_light
    generic map (
        UART_BAUD_RATE  => UART_BAUD_RATE
    )
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
        
        TX_CHANNELS_OUT_P   => TX_CHANNELS_OUT_P,
        TX_CHANNELS_OUT_N   => TX_CHANNELS_OUT_N,
        TX_SDA              => TX_SDA,
        TX_SCL              => TX_SCL,
        TX_CEC              => TX_CEC,
        TX_DET              => TX_DET,
        TX_EN               => TX_EN,
        
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
    
    test_spi_flash_inst : entity work.test_spi_flash
        generic map (
            BYTE_COUNT      => 1024*1024, -- 8 MBit
            INIT_FILE_PATH  => "..\settings.bin",
            INIT_FILE_ADDR  => x"0C0000",
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
    
    test_tmds_encoder_inst : entity work.test_tmds_encoder
        generic map (
            PROFILE => 0
        )
        port map (
            CHANNELS_OUT_P  => RX_CHANNELS_IN_P(3 downto 0),
            CHANNELS_OUT_N  => RX_CHANNELS_IN_N(3 downto 0)
        );
    
    stim_proc : process
        constant PANDALIGHT_MAGIC   : string := "PL";
        
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
        PMOD2(0)    <= '1';
        wait for 100 ns;
        PMOD2(0)    <= '0';
        wait for 1 ms;
        
        -- send "send system information via UART" request to the module
        report "Sending 'send system information via UART' request";
        send_magic;
        send_bytes(x"00");
        wait for 2 ms;
        
        -- send "send settings to UART" request to the module
        report "Sending 'send settings to UART' request";
        send_magic;
        send_bytes(x"23");
        wait for 2 ms;
        
        report "NONE. All tests completed."
            severity FAILURE;
    end process;
    
end;