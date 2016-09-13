library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;

entity testbench is
end testbench;

architecture behavior of testbench is

    signal CLK20    : std_ulogic := '0';
    
    -- HDMI
    signal RX_CHANNELS_IN_P : std_ulogic_vector(7 downto 0) := x"FF";
    signal RX_CHANNELS_IN_N : std_ulogic_vector(7 downto 0) := x"00";
    signal RX_SDA           : std_logic_vector(1 downto 0) := "ZZ";
    signal RX_SCL           : std_logic_vector(1 downto 0) := "ZZ";
    signal RX_CEC           : std_ulogic_vector(1 downto 0) := "ZZ";
    signal RX_DET           : std_ulogic_vector(1 downto 0) := "00";
    signal RX_EN            : std_ulogic_vector(1 downto 0);
    
    signal TX_CHANNELS_OUT_P    : std_ulogic_vector(3 downto 0);
    signal TX_CHANNELS_OUT_N    : std_ulogic_vector(3 downto 0);
    signal TX_SDA               : std_logic := 'Z';
    signal TX_SCL               : std_logic := 'Z';
    signal TX_CEC               : std_ulogic := 'Z';
    signal TX_DET               : std_ulogic := '0';
    signal TX_EN                : std_ulogic;
    
    -- USB UART
    signal USB_RXD  : std_ulogic := '1';
    signal USB_TXD  : std_ulogic;
    signal USB_CTSN : std_ulogic := '1';
    signal USB_RTSN : std_ulogic;
    signal USB_DSRN : std_ulogic := '1';
    signal USB_DTRN : std_ulogic;
    signal USB_DCDN : std_ulogic;
    signal USB_RIN  : std_ulogic;
    
    -- BT UART
    signal BT_CTSN  : std_ulogic := '1';
    signal BT_RTSN  : std_ulogic;
    signal BT_RXD   : std_ulogic := '1';
    signal BT_TXD   : std_ulogic;
    signal BT_WAKE  : std_ulogic;
    signal BT_RSTN  : std_ulogic;
    
    -- SPI Flash
    signal FLASH_MISO   : std_ulogic := '1';
    signal FLASH_MOSI   : std_ulogic;
    signal FLASH_CS     : std_ulogic;
    signal FLASH_SCK    : std_ulogic;
    
    -- LEDs
    signal LEDS_CLK     : std_ulogic_vector(1 downto 0);
    signal LEDS_DATA    : std_ulogic_vector(1 downto 0);
    
    -- PMOD
    signal PMOD0    : std_logic_vector(3 downto 0) := "ZZZZ";
    signal PMOD1    : std_logic_vector(3 downto 0) := "ZZZZ";
    signal PMOD2    : std_logic_vector(3 downto 0) := "ZZZZ";
    signal PMOD3    : std_logic_vector(3 downto 0) := "ZZZZ";
    
    constant g_clk20_period         : time := 50 ns;
    constant g_clk20_period_real    : real := real(g_clk20_period / 1 ps) / real(1 ns / 1 ps);
    
    signal slave_sda_in         : std_ulogic := '1';
    signal slave_sda_out        : std_ulogic := '1';
    signal slave_scl_in         : std_ulogic := '1';
    signal slave_scl_out        : std_ulogic := '1';
    signal slave_transm_error   : std_ulogic := '0';
    signal slave_read_error     : std_ulogic := '0';
    
    signal master_start             : std_ulogic := '0';
    signal master_block_number      :std_ulogic_vector(7 downto 0) := x"00";
    signal master_sda_in            : std_ulogic := '0';
    signal master_sda_out           : std_ulogic;
    signal master_scl_in            : std_ulogic := '0';
    signal master_scl_out           : std_ulogic;
    signal master_busy              : std_ulogic;
    signal master_transm_error      : std_ulogic;
    signal master_data_out          : std_ulogic_vector(7 downto 0);
    signal master_data_out_valid    : std_ulogic;
    signal master_byte_index        : std_ulogic_vector(6 downto 0);
    
begin
    
    CLK20   <= not CLK20 after g_clk20_period/2;
    
    TX_SDA  <= '0' when slave_sda_out='0' else 'Z';
    TX_SCL  <= '0' when slave_scl_out='0' else 'Z';
    
    RX_SDA(1)   <= '0' when master_sda_out='0' else 'Z';
    RX_SCL(1)   <= '0' when master_scl_out='0' else 'Z';
    
    USB_RXD     <= '1';
    USB_DSRN    <= '0';
    USB_CTSN    <= '0';
    
    PMOD0   <= x"0";
    PMOD1   <= x"0";
    PMOD2   <= x"0";
    PMOD3   <= x"0";
    
    slave_sda_in    <= '0' when TX_SDA='0' else '1';
    slave_scl_in    <= '0' when TX_SCL='0' else '1';
    
    master_sda_in   <= '0' when RX_SDA(1)='0' else '1';
    master_scl_in   <= '0' when RX_SCL(1)='0' else '1';
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => CLK20,
        
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
        BT_CTSN => BT_CTSN,
        BT_RTSN => BT_RTSN,
        BT_RXD  => BT_RXD,
        BT_TXD  => BT_TXD,
        BT_WAKE => BT_WAKE,
        BT_RSTN => BT_RSTN,
        
        -- SPI Flash
        FLASH_MISO  => FLASH_MISO,
        FLASH_MOSI  => FLASH_MOSI,
        FLASH_CS    => FLASH_CS,
        FLASH_SCK   => FLASH_SCK,
        
        -- LEDs
        LEDS_CLK    => LEDS_CLK,
        LEDS_DATA   => LEDS_DATA,
        
        -- PMOD
        PMOD0   => PMOD0,
        PMOD1   => PMOD1,
        PMOD2   => PMOD2,
        PMOD3   => PMOD3
    );
    
    test_edid_slave_inst : entity work.test_edid_slave
        generic map (
            VERBOSE     => false,
            CLK_PERIOD  => 10 us -- 100 kHz
        )
        port map (
            CLK => CLK20,
            
            SDA_IN  => slave_sda_in,
            SDA_OUT => slave_sda_out,
            SCL_IN  => slave_scl_in,
            SCL_OUT => slave_scl_out,
            
            TRANSM_ERROR        => slave_transm_error,
            READ_ERROR          => slave_read_error
        );
    
    E_DDC_MASTER_inst : entity work.E_DDC_MASTER
        generic map (
            CLK_IN_PERIOD   => g_clk20_period_real
        )
        port map (
            CLK => CLK20,
            RST => '0',
            
            START           => master_start,
            BLOCK_NUMBER    => master_block_number,
            SDA_IN          => master_sda_in,
            SDA_OUT         => master_sda_out,
            
            SCL_IN          => master_scl_in,
            SCL_OUT         => master_scl_out,
            BUSY            => master_busy,
            TRANSM_ERROR    => master_transm_error,
            DATA_OUT        => master_data_out,
            DATA_OUT_VALID  => master_data_out_valid,
            BYTE_INDEX      => master_byte_index
        );
    
    process
    begin
        wait for 100 us;
        TX_DET      <= '1';
        wait for 1 ms;
        RX_DET(1)   <= '1';
        wait for 100 us;
        master_start    <= '1';
        wait;
    end process;
    
end;