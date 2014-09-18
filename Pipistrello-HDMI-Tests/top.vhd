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
use work.help_funcs.all;

entity top is
    generic (
        CLK_IN_PERIOD   : real := 20.0; -- 50 MHz, in nano seconds
        DEBUG_STR_LEN   : positive := 128
    );
    port (
        CLK_IN  : in std_ulogic;
        
        -- SPI flash
        FLASH_MISO  : in std_ulogic;
        FLASH_MOSI  : out std_ulogic := '0';
        FLASH_CS    : out std_ulogic := '1';
        FLASH_SCK   : out std_ulogic := '1';
        FLASH_WP    : out std_ulogic := '1';
        FLASH_HOLD  : out std_ulogic := '1';
        
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
    
    signal pushbtn_q    : std_ulogic := '0';
    
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
    
    
    ------------------
    --- UART debug ---
    ------------------
    
    -- Inputs
    signal dbg_clk  : std_ulogic := '0';
    signal dbg_rst  : std_ulogic := '0';
    
    signal dbg_msg      : string(1 to DEBUG_STR_LEN) := (others => nul);
    signal dbg_wr_en    : std_ulogic := '0';
    signal dbg_cts      : std_ulogic := '0';
    
    -- Outputs
    signal dbg_done : std_ulogic := '0';
    signal dbg_full : std_ulogic := '0';
    signal dbg_txd  : std_ulogic := '1';
    
    
    -------------------------
    --- SPI flash control ---
    -------------------------
    
    -- Inputs
    signal flashctrl_clk    : std_ulogic := '0';
    signal flashctrl_rst    : std_ulogic := '0';
    
    signal flashctrl_addr   : std_ulogic_vector(23 downto 0) := x"000000";
    signal flashctrl_din    : std_ulogic_vector(7 downto 0) := x"00";
    signal flashctrl_rd_en  : std_ulogic := '0';
    signal flashctrl_wr_en  : std_ulogic := '0';
    signal flashctrl_miso   : std_ulogic := '0';
    
    -- Outputs
    signal flashctrl_dout   : std_ulogic_vector(7 downto 0) := x"00";
    signal flashctrl_valid  : std_ulogic := '0';
    signal flashctrl_wr_ack : std_ulogic := '0';
    signal flashctrl_busy   : std_ulogic := '0';
    signal flashctrl_full   : std_ulogic := '0';
    signal flashctrl_mosi   : std_ulogic := '0';
    signal flashctrl_c      : std_ulogic := '0';
    signal flashctrl_sn     : std_ulogic := '1';
    
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
    
    g_rst   <= '0'; --PUSHBTN;
    LEDS(4) <= PUSHBTN;
    LEDS(3) <= not USB_TXLEDN;
    LEDS(2) <= not USB_RXLEDN;
    LEDS(1) <= uartin_error;
    LEDS(0) <= flashctrl_busy;
    
    FLASH_MOSI  <= flashctrl_mosi;
    FLASH_CS    <= flashctrl_sn;
    FLASH_SCK   <= flashctrl_c;
    
    USB_TXD     <= dbg_txd;
    USB_RTS     <= not dbg_full;
    
    process(g_clk)
    begin
        if rising_edge(g_clk) then
            pushbtn_q   <= PUSHBTN;
        end if;
    end process;
    
    ---------------------
    --- UART receiver ---
    ---------------------
    
    uartin_clk  <= g_clk;
    uartin_rst  <= g_rst;
    
    uartin_rxd      <= USB_RXD;
    uartin_rd_en    <= '0';
    
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
    
    
    ------------------
    --- UART debug ---
    ------------------
    
    dbg_clk <= g_clk;
    dbg_rst <= g_rst;
    
    dbg_msg     <= (1 => character'val(int(flashctrl_dout)), others => nul);
    dbg_wr_en   <= flashctrl_valid;
    dbg_cts     <= USB_CTS;
    
    UART_DEBUG_inst : entity work.UART_DEBUG
        generic map (
            CLK_IN_PERIOD   => g_clk_period,
            STR_LEN         => DEBUG_STR_LEN
        )
        port map (
            CLK => dbg_clk,
            RST => dbg_rst,
    
            MSG     => dbg_msg,
            WR_EN   => dbg_wr_en,
            CTS     => dbg_cts,
            
            DONE    => dbg_done,
            FULL    => dbg_full,
            TXD     => dbg_txd
        );
    
    
    -------------------------
    --- SPI flash control ---
    -------------------------
    
    flashctrl_clk   <= g_clk;
    flashctrl_rst   <= g_rst;
    
    flashctrl_addr  <= x"000000";
    flashctrl_rd_en <= PUSHBTN and not pushbtn_q;
    flashctrl_wr_en <= '0';
    flashctrl_miso  <= FLASH_MISO;
    
    SPI_FLASH_CONTROL_inst : entity work.SPI_FLASH_CONTROL
        generic map (
            CLK_IN_PERIOD   => g_clk_period,
            CLK_OUT_MULT    => 2,
            CLK_OUT_DIV     => 2
        )
        port map (
            CLK => flashctrl_clk,
            RST => flashctrl_rst,
            
            ADDR    => flashctrl_addr,
            DIN     => flashctrl_din,
            RD_EN   => flashctrl_rd_en,
            WR_EN   => flashctrl_wr_en,
            MISO    => flashctrl_miso,
            
            DOUT    => flashctrl_dout,
            VALID   => flashctrl_valid,
            WR_ACK  => flashctrl_wr_ack,
            BUSY    => flashctrl_busy,
            FULL    => flashctrl_full,
            MOSI    => flashctrl_mosi,
            C       => flashctrl_c,
            SN      => flashctrl_sn
        );
    
end rtl;

