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
        
        PACKET_VALID    : out std_ulogic := '0';
        DATA_VALID      : out std_ulogic := '0';
        DATA            : out std_ulogic_vector(7 downto 0) := x"00";
        
        OK          : out std_ulogic := '0';
        CONNECTED   : out std_ulogic := '0';
        ERROR       : out std_ulogic := '0';
        BUSY        : out std_ulogic := '0'
    );
end UART_BLUETOOTH_INPUT_PARSER;

architecture rtl of UART_BLUETOOTH_INPUT_PARSER is
    
    type state_type is (
        RESETTING_RX,
        COMPARING_FIRST_CHAR,
        EXPECTING_ROK_O,
        EXPECTING_ROK_OK_K,
        SETTING_OK,
        EXPECTING_ANY_CMD_R,
        EXPECTING_RCOI_RDAI_RDII_CMD_C_D,
        EXPECTING_RCOI_CMD_O,
        EXPECTING_RCOI_CMD_I,
        EXPECTING_RDAI_RDII_CMD_A_I,
        EXPECTING_RDAI_CMD_I,
        EXPECTING_RDAI_CMD_EQUALS,
        EVALUATING_RDAI_CMD_DATA_LEN_1,
        EVALUATING_RDAI_CMD_DATA_LEN_2,
        EVALUATING_RDAI_CMD_DATA_LEN_3,
        EXPECTING_RDAI_CMD_COMMA,
        RECEIVE_DATA_BYTE,
        EXPECTING_RDII_CMD_I,
        UNSETTING_CONNECTED,
        EXPECTING_RCOI_CMD_EQUALS,
        SETTING_CONNECTED,
        WAITING_FOR_RESPONSE_END
    );
    
    type reg_type is record
        state           : state_type;
        rx_rst          : std_ulogic;
        ok              : std_ulogic;
        connected       : std_ulogic;
        error           : std_ulogic;
        data_length     : unsigned(9 downto 0);
        byte_counter    : unsigned(10 downto 0);
        packet_valid    : std_ulogic;
        data            : std_ulogic_vector(7 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => RESETTING_RX,
        rx_rst          => '1',
        ok              => '0',
        connected       => '0',
        error           => '0',
        data_length     => (others => '0'),
        byte_counter    => (others => '0'),
        packet_valid    => '0',
        data            => x"00"
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
    
    DATA_VALID  <= rx_valid and cur_reg.packet_valid;
    DATA        <= rx_dout;
    
    OK          <= cur_reg.ok;
    CONNECTED   <= cur_reg.connected;
    ERROR       <= cur_reg.error;
    BUSY        <= '1' when cur_reg.state/=COMPARING_FIRST_CHAR or rx_busy='1' else '0';
    
    resp_end    <= rx_valid='1' and rx_dout_char_q=CR and rx_dout_char=LF;
    
    process(rx_dout)
    begin
        -- in a process because of attribute evaluation bugs
        rx_dout_char    <= character'val(int(rx_dout));
    end process;
    
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
    
    stm_proc : process(cur_reg, RST, rx_dout, rx_valid, rx_empty, rx_error, rx_dout_char, resp_end)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
        
        procedure expect_char(
            constant c          : in character;
            constant next_state : in state_type;
            constant set_error  : in boolean
        ) is
        begin
            if rx_valid='1' then
                if set_error then
                    r.error := '1';
                    r.state := WAITING_FOR_RESPONSE_END;
                end if;
                if rx_dout_char=c then
                    r.error := '0';
                    r.state := next_state;
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
        r.ok        := '0';
        r.error     := '0';
        r.rx_rst    := '0';
        
        case cr.state is
            
            when RESETTING_RX =>
                r.rx_rst    := '1';
                r.state     := COMPARING_FIRST_CHAR;
            
            when COMPARING_FIRST_CHAR =>
                if rx_valid='1' then
                    case rx_dout_char is
                        when 'R' =>
                            r.state := EXPECTING_ROK_O;
                        when 'O' =>
                            r.state := EXPECTING_ROK_OK_K;
                        when '+' =>
                            r.state := EXPECTING_ANY_CMD_R;
                        when others =>
                            r.error := '1';
                            r.state := WAITING_FOR_RESPONSE_END;
                    end case;
                end if;
            
            when EXPECTING_ROK_O =>
                expect_char('O', EXPECTING_ROK_OK_K, true);
            
            when EXPECTING_ROK_OK_K =>
                expect_char('K', SETTING_OK, true);
            
            when SETTING_OK =>
                if resp_end then
                    r.ok    := '1';
                end if;
            
            when EXPECTING_ANY_CMD_R =>
                expect_char('R', EXPECTING_RCOI_RDAI_RDII_CMD_C_D, true);
            
            when EXPECTING_RCOI_RDAI_RDII_CMD_C_D =>
                expect_char('C', EXPECTING_RCOI_CMD_O, true);
                expect_char('D', EXPECTING_RDAI_RDII_CMD_A_I);
            
            when EXPECTING_RCOI_CMD_O =>
                expect_char('O', EXPECTING_RCOI_CMD_I, true);
            
            when EXPECTING_RCOI_CMD_I =>
                expect_char('I', EXPECTING_RCOI_CMD_EQUALS, true);
            
            when EXPECTING_RDAI_RDII_CMD_A_I =>
                expect_char('A', EXPECTING_RDAI_CMD_I, true);
                expect_char('I', EXPECTING_RDII_CMD_I);
            
            when EXPECTING_RDAI_CMD_I =>
                expect_char('I', EXPECTING_RDAI_CMD_EQUALS, true);
            
            when EXPECTING_RDAI_CMD_EQUALS =>
                expect_char('=', EVALUATING_RDAI_CMD_DATA_LEN_1, true);
            
            when EVALUATING_RDAI_CMD_DATA_LEN_1 =>
                if rx_valid='1' then
                    r.state := EVALUATING_RDAI_CMD_DATA_LEN_2;
                    case rx_dout_char is
                        when '1'    => r.data_length    := uns(100, 10);
                        when '2'    => r.data_length    := uns(200, 10);
                        when '3'    => r.data_length    := uns(300, 10);
                        when '4'    => r.data_length    := uns(400, 10);
                        when '5'    => r.data_length    := uns(500, 10);
                        when '6'    => r.data_length    := uns(600, 10);
                        when '7'    => r.data_length    := uns(700, 10);
                        when '8'    => r.data_length    := uns(800, 10);
                        when '9'    => r.data_length    := uns(900, 10);
                        when '0'    => r.data_length    := uns(0, 10);
                        when others => r.error  := '1'; r.state := WAITING_FOR_RESPONSE_END;
                    end case;
                end if;
            
            when EVALUATING_RDAI_CMD_DATA_LEN_2 =>
                if rx_valid='1' then
                    r.state := EVALUATING_RDAI_CMD_DATA_LEN_3;
                    case rx_dout_char is
                        when '1'    => r.data_length    := cr.data_length+10;
                        when '2'    => r.data_length    := cr.data_length+20;
                        when '3'    => r.data_length    := cr.data_length+30;
                        when '4'    => r.data_length    := cr.data_length+40;
                        when '5'    => r.data_length    := cr.data_length+50;
                        when '6'    => r.data_length    := cr.data_length+60;
                        when '7'    => r.data_length    := cr.data_length+70;
                        when '8'    => r.data_length    := cr.data_length+80;
                        when '9'    => r.data_length    := cr.data_length+90;
                        when '0'    => null;
                        when others => r.error  := '1'; r.state := WAITING_FOR_RESPONSE_END;
                    end case;
                end if;
            
            when EVALUATING_RDAI_CMD_DATA_LEN_3 =>
                if rx_valid='1' then
                    r.state := EXPECTING_RDAI_CMD_COMMA;
                    case rx_dout_char is
                        when '1'    => r.data_length    := cr.data_length+1;
                        when '2'    => r.data_length    := cr.data_length+2;
                        when '3'    => r.data_length    := cr.data_length+3;
                        when '4'    => r.data_length    := cr.data_length+4;
                        when '5'    => r.data_length    := cr.data_length+5;
                        when '6'    => r.data_length    := cr.data_length+6;
                        when '7'    => r.data_length    := cr.data_length+7;
                        when '8'    => r.data_length    := cr.data_length+8;
                        when '9'    => r.data_length    := cr.data_length+9;
                        when '0'    => null;
                        when others => r.error  := '1'; r.state := WAITING_FOR_RESPONSE_END;
                    end case;
                end if;
            
            when EXPECTING_RDAI_CMD_COMMA =>
                r.byte_counter  := resize(cr.data_length, 11)-2;
                expect_char(',', RECEIVE_DATA_BYTE, true);
            
            when RECEIVE_DATA_BYTE =>
                r.packet_valid  := '1';
                if rx_valid='1' then
                    r.byte_counter  := cr.byte_counter-1;
                end if;
                if cr.byte_counter(cr.byte_counter'high)='1' then
                    r.state := WAITING_FOR_RESPONSE_END;
                end if;
            
            when EXPECTING_RDII_CMD_I =>
                expect_char('I', UNSETTING_CONNECTED, true);
            
            when UNSETTING_CONNECTED =>
                r.connected := '0';
                r.state     := WAITING_FOR_RESPONSE_END;
            
            when EXPECTING_RCOI_CMD_EQUALS =>
                expect_char('=', SETTING_CONNECTED, true);
            
            when SETTING_CONNECTED =>
                r.connected := '1';
                r.state     := WAITING_FOR_RESPONSE_END;
            
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
