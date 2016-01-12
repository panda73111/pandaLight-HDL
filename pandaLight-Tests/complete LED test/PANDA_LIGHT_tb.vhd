library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;
use work.video_profiles.all;

entity testbench is
end testbench;

architecture behavior of testbench is

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
    
    -- SPI Flash
    signal FLASH_MISO   : std_ulogic := '0';
    signal FLASH_MOSI   : std_ulogic;
    signal FLASH_CS     : std_ulogic;
    signal FLASH_SCK    : std_ulogic;
    
    -- LEDs
    signal LEDS_CLK     : std_ulogic_vector(1 downto 0) := "00";
    signal LEDS_DATA    : std_ulogic_vector(1 downto 0) := "00";
    
    -- PMOD
    signal PMOD0    : std_ulogic_vector(3 downto 0) := x"0";
    
    constant G_CLK20_PERIOD : time := 50 ns;
    constant PROFILE_BITS   : natural := log2(VIDEO_PROFILE_COUNT);
    
    signal vp   : video_profile_type;
    
begin
    
    g_clk20 <= not g_clk20 after G_CLK20_PERIOD/2;
    
    RX_CHANNELS_IN_P(7 downto 4)    <= RX_CHANNELS_IN_P(3 downto 0);
    RX_CHANNELS_IN_N(7 downto 4)    <= RX_CHANNELS_IN_N(3 downto 0);
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => g_clk20,
        
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
        
        FLASH_MISO  => FLASH_MISO,
        FLASH_MOSI  => FLASH_MOSI,
        FLASH_SCK   => FLASH_SCK,
        FLASH_CS    => FLASH_CS,
        
        LEDS_CLK    => LEDS_CLK,
        LEDS_DATA   => LEDS_DATA,
        
        PMOD0   => PMOD0
    );
    
    test_spi_flash_inst : entity work.test_spi_flash
        generic map (
            BYTE_COUNT      => 1024*1024,
            INIT_FILE_PATH  => "../settings.bin",
            INIT_FILE_ADDR  => x"0C0000",
            VERBOSE         => true
        )
        port map (
            MISO    => FLASH_MOSI,
            MOSI    => FLASH_MISO,
            C       => FLASH_SCK,
            SN      => FLASH_CS
        );
    
    test_tmds_encoder_inst : entity work.test_tmds_encoder
        generic map (
            PROFILE => 0
        )
        port map (
            CHANNELS_OUT_P  => RX_CHANNELS_IN_P(3 downto 0),
            CHANNELS_OUT_N  => RX_CHANNELS_IN_N(3 downto 0)
        );
    
    process
    begin
        PMOD0(0)    <= '1';
        wait for 1 ms;
        PMOD0(0)    <= '0';
        
        wait for 10 ms;
        
        PMOD0(1)    <= '1';
        
        wait;
    end process;
    
end;