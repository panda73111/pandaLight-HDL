----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    17:10:08 01/25/2014
-- Module Name:    TOP - Behavioral
-- Project Name:   HDMI Tests
-- Target Devices: Pipistrello
-- Tool versions:  Xilinx ISE 14.7
-- Description:    Just some messing around
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    generic (
        CLK_IN_PERIOD   : real := 20.0 -- 50 MHz, in nano seconds
    );
    port (
        CLK_IN  : in std_ulogic;
        
        -- USB UART
        USB_TXD     : out std_ulogic;
        USB_RXD     : in std_ulogic;
        USB_RTS     : out std_ulogic;
        USB_CTS     : in std_ulogic;
        USB_RXLEDN  : in std_ulogic;
        USB_TXLEDN  : in std_ulogic;
        
        -- IO
        LEDS    : out std_ulogic_vector(4 downto 0) := (others => '0');
        PUSHBTN : in std_ulogic
    );
end TOP;

architecture rtl of top is
    
    constant g_clk_period   : real := 20.0; -- in nano seconds
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal echo_tick_cnt    : unsigned(25 downto 0);
    signal char_index       : unsigned(6 downto 0);
    
    ---------------------
    --- UART receiver ---
    ---------------------
    
    -- Inputs
    signal uartin_clk   : std_ulogic := '0';
    signal uartin_rst   : std_ulogic := '0';
    
    signal uartin_rxd   : std_ulogic := '0';
    signal uartin_rd_en : std_ulogic := '0';
    
    -- Outputs
    signal uartin_dout  : std_ulogic_vector(7 downto 0) := x"00";
    signal uartin_valid : std_ulogic := '0';
    signal uartin_full  : std_ulogic := '0';
    signal uartin_error : std_ulogic := '0';
    signal uartin_busy  : std_ulogic := '0';
    
    
    -------------------
    --- UART sender ---
    -------------------
    
    -- Inputs
    signal uartout_clk  : std_ulogic := '0';
    signal uartout_rst  : std_ulogic := '0';
    
    signal uartout_din      : std_ulogic_vector(7 downto 0) := x"00";
    signal uartout_wr_en    : std_ulogic := '0';
    signal uartout_cts      : std_ulogic := '0';
    
    -- Outputs
    signal uartout_txd  : std_ulogic := '0';
    signal uartout_full : std_ulogic := '0';
    signal uartout_busy : std_ulogic := '0';
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLK_MAN_inst : entity work.CLK_MAN
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            MULTIPLIER      => 2,
            DIVISOR         => 2
        )
        port map (
            CLK_IN  => CLK_IN,
            RST     => g_rst,
            
            CLK_OUT         => g_clk,
            CLK_IN_STOPPED  => open,
            CLK_OUT_STOPPED => open
        );
    
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    g_rst   <= PUSHBTN;
    LEDS(4) <= PUSHBTN;
    LEDS(3) <= not USB_TXLEDN;
    LEDS(2) <= not USB_RXLEDN;
    LEDS(1) <= uartin_error;
    LEDS(0) <= '0';
    
    USB_TXD     <= uartout_txd;
    USB_RTS     <= not uartin_full;
    
    
    ---------------------
    --- UART receiver ---
    ---------------------
    
    uartin_clk  <= g_clk;
    uartin_rst  <= g_rst;
    
    uartin_rxd      <= USB_RXD;
    uartin_rd_en    <= not uartout_full;
    
    UART_RECEIVER_inst : entity work.UART_RECEIVER
        generic map (
            CLK_IN_PERIOD   => g_clk_period,
            BAUD_RATE       => 115_200,
            DATA_BITS       => 8,
            PARITY_BIT_TYPE => 0,
            BUFFER_SIZE     => 512
        )
        port map (
            CLK => uartin_clk,
            RST => uartin_rst,
            
            RXD     => uartin_rxd,
            RD_EN   => uartin_rd_en,
            
            DOUT    => uartin_dout,
            VALID   => uartin_valid,
            FULL    => uartin_full,
            ERROR   => uartin_error,
            BUSY    => uartin_busy
        );
    
    
    -------------------
    --- UART sender ---
    -------------------
    
    uartout_clk <= g_clk;
    uartout_rst <= g_rst;
    
    uartout_din     <= uartin_dout;
    uartout_wr_en   <= uartin_valid;
    uartout_cts     <= USB_CTS;
    
    UART_SENDER_inst : entity work.UART_SENDER
        generic map (
            CLK_IN_PERIOD   => g_clk_period,
            BAUD_RATE       => 115_200,
            DATA_BITS       => 8,
            STOP_BITS       => 1,
            PARITY_BIT_TYPE => 0,
            BUFFER_SIZE     => 512
        )
        port map (
            CLK => uartout_clk,
            RST => uartout_rst,
    
            DIN     => uartout_din,
            WR_EN   => uartout_wr_en,
            CTS     => uartout_cts,
    
            TXD     => uartout_txd,
            FULL    => uartout_full,
            BUSY    => uartout_busy
        );
    
end rtl;

