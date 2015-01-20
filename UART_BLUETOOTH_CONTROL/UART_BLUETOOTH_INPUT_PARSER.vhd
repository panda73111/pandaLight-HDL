----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    12:48:50 01/20/2015 
-- Module Name:    UART_BLUETOOTH_INPUT_PARSER - rtl 
-- Project Name:   UART_BLUETOOTH_CONTROL
-- Tool versions:  Xilinx ISE 14.7
-- Description:
--  
-- Additional Comments:
--  
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity UART_BLUETOOTH_INPUT_PARSER is
    generic (
        CLK_IN_PERIOD   : real;
        BAUD_RATE       : positive := 115_200;
        BUFFER_SIZE     : positive := 128
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        BT_RXD  : in std_ulogic;
        
        OK      : out std_ulogic := '0';
        ERROR   : out std_ulogic := '0';
        BUSY    : out std_ulogic := '0'
    );
end UART_BLUETOOTH_INPUT_PARSER;

architecture rtl of UART_BLUETOOTH_INPUT_PARSER is
    
    type state_type is (
        RESETTING_RX,
        WAITING_FOR_DATA,
        READING_FIRST_BYTE,
        COMPARING_FIRST_CHAR,
        EXPECTING_O,
        EXPECTING_K,
        WAITING_FOR_RESPONSE_END
    );
    
    type reg_type is record
        state       : state_type;
        rx_rst      : std_ulogic;
        ok          : std_ulogic;
        error       : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAITING_FOR_DATA,
        rx_rst      => '1',
        ok          => '0',
        error       => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal rx_dout          : std_ulogic_vector(7 downto 0) := x"00";
    signal rx_dout_char     : character := NUL;
    signal rx_dout_char_q   : character := NUL;
    
    signal rx_valid : std_ulogic := '0';
    signal rx_empty : std_ulogic := '0';
    signal rx_error : std_ulogic := '0';
    signal rx_busy  : std_ulogic := '0';
    
    signal resp_end : boolean := false;
    
begin
    
    OK      <= cur_reg.ok;
    ERROR   <= cur_reg.error;
    BUSY    <= '1' when cur_reg.state/=WAITING_FOR_DATA or rx_busy='1' else '0';
    
    rx_dout_char    <= character'val(nat(rx_dout));
    resp_end        <= rx_valid='1' and rx_dout_char_q=CR and rx_dout_char=LF;
    
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
            RST => cur_reg.rx_rst,
            
            RXD     => BT_RXD,
            RD_EN   => '1',
            
            DOUT    => rx_dout,
            VALID   => rx_valid,
            EMPTY   => rx_empty,
            ERROR   => rx_error,
            BUSY    => rx_busy
        );
    
    stm_proc : process(cur_reg, RST, rx_dout, rx_valid, rx_empty, rx_error)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
        
        procedure expect_char(
            constant c          : in character;
            constant next_state : in state_type;
            constant set_ok     : in boolean
        ) is
        begin
            if rx_valid='1' then
                r.state     := next_state;
                if rx_dout_char=c then
                    if set_ok then
                        r.ok    := '1';
                    end if;
                else
                    r.error := '1';
                    r.state := WAITING_FOR_RESPONSE_END;
                end if;
            end if;
        end procedure;
        
        procedure expect_char(
            constant c          : in character;
            constant next_state : in state_type
        ) is
        begin
            expect_char(c, next_state, false);
        end procedure;
    begin
        r           := cr;
        r.error     := '0';
        r.rx_rst    := '0';
        
        case cr.state is
            
            when RESETTING_RX =>
                r.rx_rst    := '1';
                r.state     := COMPARING_FIRST_CHAR;
            
            when COMPARING_FIRST_CHAR =>
                if rx_valid='1' then
                    r.rx_rd_en  := '1';
                    case rx_dout_char is
                        when 'R' =>
                            r.state := EXPECTING_ROK__O;
                        when 'O' =>
                            r.state := EXPECTING_ROK_OK__K;
                        when '+' =>
                            r.state := EXPECTING_ANY_CMD__R;
                        when others =>
                            r.error := '1';
                            r.state := WAITING_FOR_RESPONSE_END;
                    end case;
                end if;
            
            when EXPECTING_ROK__O =>
                expect_char('O', EXPECTING_K);
            
            when EXPECTING_ROK_OK__K =>
                expect_char('K', COMPARING_FIRST_CHAR, true);
            
            when EXPECTING_ANY_CMD__R =>
                expect_char('R', EXPECTING_RCOI_CMD__C);
            
            when EXPECTING_RCOI_CMD__C =>
                expect_char('C', EXPECTING_RCOI_CMD__O);
            
            when EXPECTING_RCOI_CMD__O =>
                expect_char('O', EXPECTING_RCOI_CMD__EQUALS);
            
            when EXPECTING_RCOI_CMD__EQUALS =>
                expect_char('=', );
            
            when WAITING_FOR_RESPONSE_END =>
                null;
            
        end case;
        
        if rx_error='1' then
            r.error := '1';
            r.state := RESETTING_RX;
        end if;
        
        if resp_end then
            r.state := COMPARING_FIRST_CHAR;
        end if;
        
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
            cur_reg     <= next_reg;
            if rx_valid='1' then
                rx_dout_char_q  <= rx_dout_char;
            end if;
        end if;
    end process;
    
end rtl;
