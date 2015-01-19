----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    12:51:56 01/19/2015 
-- Module Name:    UART_BLUETOOTH_CONTROL - rtl 
-- Project Name:   UART_BLUETOOTH_CONTROL
-- Tool versions:  Xilinx ISE 14.7
-- Description:
--  
-- Additional Comments:
--  Controller component for the PAN1322 bluetooth module
--  (and other chips compatible with the eUniStone SPP-AT protocol)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity UART_BLUETOOTH_CONTROL is
    generic (
        CLK_IN_PERIOD   : real;
        BAUD_RATE       : positive := 115_200;
        BUFFER_SIZE     : positive := 512
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        BT_CTS  : in std_ulogic;
        BT_RTS  : out std_ulogic := '0';
        BT_RXD  : in std_ulogic;
        BT_TXD  : out std_ulogic := '0';
        BT_WAKE : out std_ulogic := '0';
        BT_RSTN : out std_ulogic := '0';
        
        BUSY    : out std_ulogic := '0'
    );
end UART_BLUETOOTH_CONTROL;

architecture rtl of UART_BLUETOOTH_CONTROL is
    
    constant SET_SECURITY_CMD   : string := "AT+JSEC=4,1,04,0000,0,1"; -- "just works" security
    
    type state_type is (
        SETTING_SECURITY,
        WAITING_FOR_SECURITY_ACK
    );
    
    type reg_type is record
        state       : state_type;
        char_index  : unsigned(4 downto 0);
        tx_din      : std_ulogic_vector(7 downto 0);
        tx_wr_en    : std_ulogic;
        rx_rd_en    : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => SETTING_SECURITY,
        char_index  => "11111",
        tx_din      => x"00",
        tx_wr_en    => '0',
        rx_rd_en    => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal tx_full  : std_ulogic := '0';
    signal tx_busy  : std_ulogic := '0';
    
    signal rx_dout  : std_ulogic_vector(7 downto 0) := x"00";
    signal rx_valid : std_ulogic := '0';
    signal rx_full  : std_ulogic := '0';
    signal rx_error : std_ulogic := '0';
    signal rx_busy  : std_ulogic := '0';
    
begin
    
    UART_SENDER_inst : entity work.UART_SENDER
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            BAUD_RATE       => BAUD_RATE,
            DATA_BITS       => 8,
            STOP_BITS       => 1,
            PARITY_BIT_TYPE => 0,
            BUFFER_SIZE     => BUFFER_SIZE
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            DIN     => cur_reg.tx_din,
            WR_EN   => cur_reg.tx_wr_en,
            CTS     => BT_CTS,
            
            TXD     => BT_TXD,
            FULL    => tx_full,
            BUSY    => tx_busy
        );
    
    UART_RECEIVER_inst : entity work.UART_RECEIVER
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            BAUD_RATE       => BAUD_RATE,
            DATA_BITS       => 8,
            PARITY_BIT_TYPE => 0,
            BUFFER_SIZE     => BUFFER_SIZE
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            RXD     => BT_RXD,
            RD_EN   => cur_reg.rx_rd_en,
            
            DOUT    => rx_dout,
            VALID   => rx_valid,
            FULL    => rx_full,
            ERROR   => rx_error,
            BUSY    => rx_busy
        );
    
    stm_proc : process(cur_reg, RST, tx_busy, rx_dout, rx_valid, rx_error, rx_busy)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.tx_wr_en  := '0';
        r.rx_rd_en  := '0';
        
        case cr.state is
            
            when SETTING_SECURITY =>
                r.tx_wr_en      := '1';
                r.tx_din        := stdulv(SET_SECURITY_CMD(nat(cr.char_index)));
                r.char_index    := cr.char_index-1;
                if cr.char_index=0 then
                    r.state := WAITING_FOR_SECURITY_ACK;
                end if;
            
            when WAITING_FOR_SECURITY_ACK =>
                null;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;
    
    stm_sync_proc : process(RST, CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;
