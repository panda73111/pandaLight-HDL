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
        USB_TXD     : out std_ulogic := '0';
        USB_CTSN    : in std_ulogic;
        USB_RTSN    : out std_ulogic := '0';
        USB_DSRN    : in std_ulogic;
        USB_DTRN    : out std_ulogic := '0';
        USB_DCDN    : out std_ulogic := '0';
        USB_RIN     : out std_ulogic := '0';
        
        -- BT UART
        BT_CTS  : in std_ulogic;
        BT_RTS  : out std_ulogic := '0';
        BT_RXD  : in std_ulogic;
        BT_TXD  : out std_ulogic := '0';
        BT_WAKE : out std_ulogic := '0';
        BT_RSTN : out std_ulogic := '0';
        
        -- PMOD
        PMOD0   : inout std_ulogic_vector(3 downto 0) := "0000"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    signal pmod0_deb    : std_ulogic_vector(3 downto 0) := x"0";
--    signal pmod0_deb_q  : std_ulogic_vector(3 downto 0) := x"0";
    
    attribute keep of USB_RXD   : signal is true;
    attribute keep of USB_TXD   : signal is true;
    attribute keep of USB_CTSN  : signal is true;
    attribute keep of USB_RTSN  : signal is true;
    attribute keep of BT_CTS    : signal is true;
    attribute keep of BT_RTS    : signal is true;
    attribute keep of BT_RXD    : signal is true;
    attribute keep of BT_TXD    : signal is true;
    attribute keep of BT_WAKE   : signal is true;
    attribute keep of BT_RSTN   : signal is true;
    
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
    
    g_rst   <= not g_clk_locked;
    
    PMOD0(0)    <= 'Z';
    PMOD0(1)    <= 'Z';
    PMOD0(2)    <= USB_RXD or USB_CTSN;
    PMOD0(3)    <= BT_RXD or BT_CTS;
    
    BT_TXD  <= USB_RXD;
    USB_TXD <= BT_RXD;
    
    USB_RTSN    <= not BT_CTS;
    BT_RTS      <= not USB_CTSN;
    
    BT_RSTN <= not pmod0_deb(0); -- high: reset BT module
    BT_WAKE <= not pmod0_deb(1); -- high: BT low power mode
    
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
    
end rtl;

