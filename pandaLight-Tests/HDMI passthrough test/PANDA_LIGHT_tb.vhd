library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity testbench is
end testbench;

architecture behavior of testbench is

    signal CLK20    : std_ulogic := '0';
    
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
    signal USB_RXD     : std_ulogic := '0';
    signal USB_TXD     : std_ulogic;
--    signal USB_CTSN    : in std_ulogic;
--    signal USB_RTSN    : out std_ulogic := '1';
--    signal USB_DSRN    : in std_ulogic;
--    signal USB_DTRN    : out std_ulogic := '0';
--    signal USB_DCDN    : out std_ulogic := '0';
--    signal USB_RIN     : out std_ulogic := '0'
    
    constant CLK20_PERIOD   : time := 50 ns;
    
begin
    
    CLK20   <= not CLK20 after CLK20_PERIOD/2;
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => CLK20,
        
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
        
        USB_RXD => USB_RXD,
        USB_TXD => USB_TXD
    );
    
    process
    begin
        wait for 500 ns;
        RX_DET  <= "01";
        wait for 500 ns;
        TX_DET  <= '1';
        wait for 500 ns;
        RX_DET  <= "11";
        wait;
    end process;
    
end;