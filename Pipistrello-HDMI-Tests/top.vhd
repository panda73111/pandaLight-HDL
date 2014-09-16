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
library UNISIM;
use UNISIM.VComponents.all;

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
        USB_RXLED   : in std_ulogic;
        USB_TXLED   : in std_ulogic;
        
        -- IO
        LEDS    : out std_ulogic_vector(4 downto 0) := (others => '0');
        PUSHBTN : in std_ulogic
    );
end TOP;

architecture rtl of top is
    
    constant g_clk_period   : real := 10.0; -- in nano seconds
    
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
            DIVISOR         => 1
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
    LEDS(3) <= not USB_TXLED;
    LEDS(2) <= not USB_RXLED;
    LEDS(1) <= uartin_error;
    LEDS(0) <= '0';
    
    USB_TXD <= uartout_txd;
    USB_RTS <= not uartin_full;
    
    
    ---------------------
    --- UART receiver ---
    ---------------------
    
    uartin_clk  <= g_clk;
    uartin_rst  <= g_rst;
    
    uartin_rxd      <= USB_RXD;
    uartin_rd_en    <= not uartout_full;
    
    UART_RECEIVER_inst : entity work.UART_RECEIVER
        generic map (
            CLK_IN_PERIOD   => g_clk_period
        )
        port map (
            CLK => uartin_clk,
            RST => uartin_rst,
            
            RXD     => uartin_rxd,
            RD_EN   => uartin_rd_en,
            
            DOUT    => open, --uartin_dout,
            VALID   => open, --uartin_valid,
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
            CLK_IN_PERIOD   => g_clk_period
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
    
    echo_proc : process(g_rst, g_rst)
    begin
        if g_rst='1' then
            echo_tick_cnt   <= (others => '0');
        elsif rising_edge(g_clk) then
            echo_tick_cnt   <= echo_tick_cnt+1;
            uartin_valid    <= '0';
            if echo_tick_cnt(echo_tick_cnt'high)='1' then
                echo_tick_cnt   <= (others => '0');
                uartin_dout     <= "0" & std_ulogic_vector(char_index);
                uartin_valid    <= '1';
                char_index      <= char_index+1;
            end if;
        end if;
    end process;
    
end rtl;

