----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    21:49:35 07/28/2014 
-- Module Name:    PANDA_LIGHT - rtl 
-- Project Name:   PANDA_LIGHT
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity PANDA_LIGHT is
    generic (
        G_CLK_MULT          : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV           : positive range 1 to 256 := 2;
        G_CLK_PERIOD        : real := 20.0 -- 50 MHz in nano seconds
    );
    port (
        CLK20   : in std_ulogic;
        
        -- USB UART
        USB_RXD     : in std_ulogic;
        USB_TXD     : out std_ulogic := '1';
        USB_CTSN    : in std_ulogic;
        USB_RTSN    : out std_ulogic := '0';
        USB_DSRN    : in std_ulogic;
        USB_DTRN    : out std_ulogic := '0';
        USB_DCDN    : out std_ulogic := '0';
        USB_RIN     : out std_ulogic := '0';
        
        -- BT UART
        BT_CTSN : in std_ulogic;
        BT_RTSN : out std_ulogic := '0';
        BT_RXD  : in std_ulogic;
        BT_TXD  : out std_ulogic := '1';
        BT_WAKE : out std_ulogic := '0';
        BT_RSTN : out std_ulogic := '0';
        
        -- PMOD
        PMOD0   : inout std_ulogic_vector(3 downto 0) := "0000";
        PMOD1   : inout std_ulogic_vector(3 downto 0) := "0000"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    signal pmod0_deb    : std_ulogic_vector(3 downto 0) := x"0";
    signal pmod0_deb_q  : std_ulogic_vector(3 downto 0) := x"0";
    
    
    ------------------------------
    --- UART Bluetooth control ---
    ------------------------------
    
    -- inputs
    signal BTCTRL_CLK   : std_ulogic := '0';
    signal BTCTRL_RST   : std_ulogic := '0';
    
    signal BTCTRL_BT_CTS    : std_ulogic := '0';
    signal BTCTRL_BT_RXD    : std_ulogic := '0';
    
    signal BTCTRL_DIN           : std_ulogic_vector(7 downto 0) := x"00";
    signal BTCTRL_DIN_WR_EN     : std_ulogic := '0';
    signal BTCTRL_SEND_PACKET   : std_ulogic := '0';
    
    -- outputs
    signal BTCTRL_BT_RTS    : std_ulogic := '0';
    signal BTCTRL_BT_TXD    : std_ulogic := '0';
    signal BTCTRL_BT_WAKE   : std_ulogic := '0';
    signal BTCTRL_BT_RSTN   : std_ulogic := '0';
    
    signal BTCTRL_DOUT          : std_ulogic_vector(7 downto 0) := x"00";
    signal BTCTRL_DOUT_VALID    : std_ulogic := '0';
    
    signal BTCTRL_CONNECTED : std_ulogic := '0';
    
    signal BTCTRL_MTU_SIZE          : std_ulogic_vector(9 downto 0) := (others => '0');
    signal BTCTRL_MTU_SIZE_VALID    : std_ulogic := '0';
    
    signal BTCTRL_ERROR : std_ulogic := '0';
    signal BTCTRL_BUSY  : std_ulogic := '0';
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLK_MAN_inst : entity work.CLK_MAN
        generic map (
            CLK_IN_PERIOD   => 50.0, -- 20 MHz in nano seconds
            MULTIPLIER      => G_CLK_MULT,
            DIVISOR         => G_CLK_DIV
        )
        port map (
            RST => '0',
            
            CLK_IN  => CLK20,
            CLK_OUT => g_clk,
            LOCKED  => g_clk_locked
        );
    
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    g_rst   <= not g_clk_locked or pmod0_deb(0);
    
    PMOD0(0)    <= 'Z';
    PMOD0(1)    <= 'Z';
    PMOD0(2)    <= BTCTRL_ERROR;
    PMOD0(3)    <= BTCTRL_CONNECTED;
    
    PMOD1(0)    <=  BTCTRL_DOUT(0) or BTCTRL_DOUT(1) or BTCTRL_DOUT(2) or BTCTRL_DOUT(3) or
                    BTCTRL_DOUT(4) or BTCTRL_DOUT(5) or BTCTRL_DOUT(6) or BTCTRL_DOUT(7);
    PMOD1(1)    <=  BTCTRL_MTU_SIZE(0) or BTCTRL_MTU_SIZE(1) or BTCTRL_MTU_SIZE(2) or BTCTRL_MTU_SIZE(3) or BTCTRL_MTU_SIZE(4) or
                    BTCTRL_MTU_SIZE(5) or BTCTRL_MTU_SIZE(6) or BTCTRL_MTU_SIZE(7) or BTCTRL_MTU_SIZE(8) or BTCTRL_MTU_SIZE(9);
    PMOD1(2)    <= 'Z';
    PMOD1(3)    <= BTCTRL_DOUT_VALID or BTCTRL_MTU_SIZE_VALID;
    
    BT_TXD  <= BTCTRL_BT_TXD and USB_RXD;
    USB_TXD <= BTCTRL_BT_TXD and BT_RXD;
    
    USB_RTSN    <= '1';
    BT_RTSN     <= not BTCTRL_BT_RTS;
    
    BT_RSTN <= BTCTRL_BT_RSTN;
    BT_WAKE <= BTCTRL_BT_WAKE;
    
    pmod0_DEBOUNCE_gen : for i in 0 to 3 generate
        
        pmod0_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 100
            )
            port map (
                CLK => g_clk,
                I   => PMOD0(i),
                O   => pmod0_deb(i)
            );
        
    end generate;
    
    pmod0_deb_sync_proc : process(g_clk)
    begin
        if rising_edge(g_clk) then
            pmod0_deb_q <= pmod0_deb;
        end if;
    end process;
    
    
    ------------------------------
    --- UART Bluetooth control ---
    ------------------------------
    
    BTCTRL_CLK  <= g_clk;
    BTCTRL_RST  <= g_rst;
    
    BTCTRL_BT_CTS   <= not BT_CTSN;
    BTCTRL_BT_RXD   <= BT_RXD;
    
    UART_BLUETOOTH_CONTROL_inst : entity work.UART_BLUETOOTH_CONTROL
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD
        )
        port map (
            CLK => BTCTRL_CLK,
            RST => BTCTRL_RST,
            
            BT_CTS  => BTCTRL_BT_CTS,
            BT_RTS  => BTCTRL_BT_RTS,
            BT_RXD  => BTCTRL_BT_RXD,
            BT_TXD  => BTCTRL_BT_TXD,
            BT_WAKE => BTCTRL_BT_WAKE,
            BT_RSTN => BTCTRL_BT_RSTN,
            
            DIN         => BTCTRL_DIN,
            DIN_WR_EN   => BTCTRL_DIN_WR_EN,
            SEND_PACKET => BTCTRL_SEND_PACKET,
            
            DOUT        => BTCTRL_DOUT,
            DOUT_VALID  => BTCTRL_DOUT_VALID,
            
            CONNECTED   => BTCTRL_CONNECTED,
            
            MTU_SIZE        => BTCTRL_MTU_SIZE,
            MTU_SIZE_VALID  => BTCTRL_MTU_SIZE_VALID,
            
            ERROR   => BTCTRL_ERROR,
            BUSY    => BTCTRL_BUSY
        );
    
    bt_control_stim_gen : if true generate
        type test_data_type is
            array(0 to 127) of
            std_ulogic_vector(7 downto 0);
        constant TEST_DATA  : test_data_type := ( -- (random)
            x"7E", x"9F", x"76", x"36", x"BB", x"67", x"9A", x"51", x"35", x"34", x"00", x"E3", x"7B", x"7C", x"41", x"D2",
            x"4A", x"1D", x"C1", x"E1", x"1F", x"FE", x"46", x"29", x"58", x"04", x"B0", x"3D", x"D7", x"F4", x"97", x"E3",
            x"35", x"C8", x"5F", x"23", x"78", x"C6", x"3C", x"FA", x"63", x"15", x"F4", x"3F", x"9B", x"AC", x"32", x"9E",
            x"D7", x"87", x"38", x"AC", x"C4", x"FF", x"37", x"A5", x"78", x"F3", x"95", x"AF", x"B0", x"C9", x"4E", x"33",
            x"D9", x"C4", x"B2", x"7B", x"D3", x"35", x"0D", x"D3", x"D5", x"73", x"72", x"00", x"C2", x"B9", x"71", x"F3",
            x"54", x"94", x"21", x"7E", x"16", x"28", x"70", x"BF", x"86", x"95", x"E5", x"67", x"EE", x"AD", x"6F", x"61",
            x"C7", x"B6", x"32", x"80", x"A3", x"73", x"A3", x"53", x"36", x"2D", x"72", x"97", x"F7", x"DC", x"FF", x"B1",
            x"69", x"28", x"EF", x"A0", x"3A", x"6E", x"A8", x"2C", x"A1", x"61", x"D8", x"20", x"45", x"32", x"65", x"4D"
        );
        type state_type is (
            INIT,
            WRITING_TEST_DATA,
            SENDING_PACKET,
            IDLE
        );
        signal state        : state_type := INIT;
        signal byte_counter : unsigned(6 downto 0) := (others => '0');
        signal bytes_left   : unsigned(7 downto 0) := uns(126, 8);
    begin
        
        bt_control_stim_proc : process(BTCTRL_RST, BTCTRL_CLK)
        begin
            if BTCTRL_RST='1' then
                state   <= INIT;
            elsif rising_edge(BTCTRL_CLK) then
                BTCTRL_DIN_WR_EN    <= '0';
                BTCTRL_SEND_PACKET  <= '0';
                case state is
                    
                    when INIT =>
                        state   <= IDLE;
                    
                    when WRITING_TEST_DATA =>
                        byte_counter        <= byte_counter+1;
                        bytes_left          <= bytes_left-1;
                        BTCTRL_DIN          <= TEST_DATA(int(byte_counter));
                        BTCTRL_DIN_WR_EN    <= '1';
                        if bytes_left(bytes_left'high)='1' then
                            state   <= SENDING_PACKET;
                        end if;
                    
                    when SENDING_PACKET =>
                        BTCTRL_SEND_PACKET  <= '1';
                        state               <= IDLE;
                    
                    when IDLE =>
                        bytes_left  <= uns(126, 8);
                        if pmod0_deb_q(1)='0' and pmod0_deb(1)='1' then
                            state   <= WRITING_TEST_DATA;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
end rtl;

