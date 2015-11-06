----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    17:18:00 11/06/2015 
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

entity PANDA_LIGHT is
    generic (
        G_CLK_MULT      : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV       : positive range 1 to 256 := 2;
        G_CLK_PERIOD    : real := 20.0 -- 50 MHz in nano seconds
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
        USB_RIN     : out std_ulogic := '0'
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    
    ------------------------
    --- UART USB control ---
    ------------------------
    
    signal usbctrl_clk  : std_ulogic := '0';
    signal usbctrl_rst  : std_ulogic := '0';
    
    signal usbctrl_cts  : std_ulogic := '0';
    signal usbctrl_rts  : std_ulogic := '0';
    signal usbctrl_rxd  : std_ulogic := '0';
    signal usbctrl_txd  : std_ulogic := '0';
    
    signal usbctrl_din          : std_ulogic_vector(7 downto 0) := x"00";
    signal usbctrl_din_wr_en    : std_ulogic := '0';
    
    signal usbctrl_dout         : std_ulogic_vector(7 downto 0) := x"00";
    signal usbctrl_dout_valid   : std_ulogic := '0';
    
    signal usbctrl_full     : std_ulogic := '0';
    signal usbctrl_error    : std_ulogic := '0';
    signal usbctrl_busy     : std_ulogic := '0';
    
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
    
    g_rst   <= '1' when g_clk_locked='0' else '0';
    
    USB_TXD <= usbctrl_txd;
    
    USB_RTSN    <= not usbctrl_rts;
    
    
    ------------------------
    --- UART USB control ---
    ------------------------
    
    usbctrl_clk <= g_clk;
    usbctrl_rst <= g_rst;
    
    usbctrl_cts <= not USB_CTSN;
    usbctrl_rxd <= USB_RXD;
    
    usbctrl_din         <= usbctrl_dout;
    usbctrl_din_wr_en   <= usbctrl_dout_valid;
    
    UART_CONTROL_inst : entity work.UART_CONTROL
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            BUFFER_SIZE     => 128
        )
        port map (
            CLK => usbctrl_clk,
            RST => usbctrl_rst,
            
            CTS => usbctrl_cts,
            RTS => usbctrl_rts,
            RXD => usbctrl_rxd,
            TXD => usbctrl_txd,
            
            DIN         => usbctrl_din,
            DIN_WR_EN   => usbctrl_din_wr_en,
            
            DOUT        => usbctrl_dout,
            DOUT_VALID  => usbctrl_dout_valid,
            
            FULL    => usbctrl_full,
            ERROR   => usbctrl_error,
            BUSY    => usbctrl_busy
        );
    
end rtl;

