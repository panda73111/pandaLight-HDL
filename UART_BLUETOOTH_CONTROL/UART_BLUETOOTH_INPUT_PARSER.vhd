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
        -- ROK / OK
        EXPECTING_ROK_O,
        EXPECTING_ROK_OK_K,
        SETTING_OK,
        -- any response
        EXPECTING_ANY_RESP_R,
        -- RCOI / RDAI / RDII / RSLE / RCCRCNF response
        EXPECTING_RCOI_RDAI_RDII_RSLE_RCCRCNF_RESP_C_D_S,
        -- RCOI / RCCRCNF response
        EXPECTING_RCOI_RCCRCNF_RESP_O_C,
        -- RCOI response
        EXPECTING_RCOI_RESP_I,
        EXPECTING_RCOI_RESP_EQUALS,
        SETTING_CONNECTED,
        -- RCCRCNF response
        EXPECTING_RCCRCNF_RESP_C2,
        EXPECTING_RCCRCNF_RESP_R,
        EXPECTING_RCCRCNF_RESP_C3,
        EXPECTING_RCCRCNF_RESP_N,
        EXPECTING_RCCRCNF_RESP_F,
        EXPECTING_RCCRCNF_RESP_EQUALS,
        EVALUATING_RCCRCNF_RESP_MTU1,
        EVALUATING_RCCRCNF_RESP_MTU2,
        EVALUATING_RCCRCNF_RESP_MTU3,
        EXPECTING_RCCRCNF_RESP_COMMA1,
        IGNORING_RCCRCNF_RESP_SERVICE,
        EXPECTING_RCCRCNF_RESP_COMMA2,
        EVALUATING_RCCRCNF_RESP_CON_STATE,
        SETTING_CON_CONFIRMED,
        UNSETTING_CON_CONFIRMED,
        -- RDAI response
        EXPECTING_RDAI_RDII_RESP_A_I,
        EXPECTING_RDAI_RESP_I,
        EXPECTING_RDAI_RESP_EQUALS,
        EVALUATING_RDAI_RESP_DATA_LEN1,
        EVALUATING_RDAI_RESP_DATA_LEN2,
        EVALUATING_RDAI_RESP_DATA_LEN3,
        EXPECTING_RDAI_RESP_COMMA,
        RECEIVE_DATA_BYTE,
        EXPECTING_RSLE_RESP_L,
        EXPECTING_RSLE_RESP_E,
        -- RDII response
        EXPECTING_RDII_RESP_I2,
        UNSETTING_CONNECTED,
        -- response end
        WAITING_FOR_RESPONSE_END
    );
    
    type reg_type is record
        state           : state_type;
        rx_rst          : std_ulogic;
        ok              : std_ulogic;
        connected       : std_ulogic;
        con_confirmed   : std_ulogic;
        error           : std_ulogic;
        data_length     : unsigned(9 downto 0);
        byte_counter    : unsigned(10 downto 0);
        packet_valid    : std_ulogic;
        data            : std_ulogic_vector(7 downto 0);
        mtu_size        : unsigned(9 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => RESETTING_RX,
        rx_rst          => '1',
        ok              => '0',
        connected       => '0',
        con_confirmed   => '0',
        error           => '0',
        data_length     => (others => '0'),
        byte_counter    => (others => '0'),
        packet_valid    => '0',
        data            => x"00",
        mtu_size        => (others => '0')
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal rx_dout          : std_ulogic_vector(7 downto 0) := x"00";
    signal rx_dout_char     : character := NUL;
    signal rx_dout_char_q   : character := NUL;
    
    signal rx_valid : std_ulogic := '0';
    signal rx_error : std_ulogic := '0';
    signal rx_busy  : std_ulogic := '0';
    
    signal resp_end : boolean := false;
    
begin
    
    PACKET_VALID    <= cur_reg.packet_valid;
    DATA_VALID      <= rx_valid and cur_reg.packet_valid;
    DATA            <= rx_dout;
    
    OK          <= cur_reg.ok;
    CONNECTED   <= cur_reg.connected and cur_reg.con_confirmed;
    ERROR       <= cur_reg.error;
    BUSY        <= '1' when cur_reg.state/=COMPARING_FIRST_CHAR or rx_busy='1' else '0';
    
    resp_end    <= rx_valid='1' and rx_dout_char_q=CR and rx_dout_char=LF;
    
    process(rx_dout)
    begin
        -- in a process because of attribute evaluation bugs
        if rx_dout(rx_dout'high)='0' then
            rx_dout_char    <= character'val(int(rx_dout));
        else
            rx_dout_char    <= NUL;
        end if;
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
            
            DOUT    => rx_dout,
            VALID   => rx_valid,
            ERROR   => rx_error,
            BUSY    => rx_busy
        );
    
    stm_proc : process(cur_reg, RST, rx_dout, rx_valid, rx_error, rx_dout_char, resp_end)
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
        
        procedure eval_dec_char(
            variable val        : inout unsigned;
            constant factor     : in positive;
            constant next_state : in state_type
        ) is
        begin
            if rx_valid='1' then
                r.state := next_state;
                case rx_dout_char is
                    when '1'    => val  := val+(1*factor);
                    when '2'    => val  := val+(2*factor);
                    when '3'    => val  := val+(3*factor);
                    when '4'    => val  := val+(4*factor);
                    when '5'    => val  := val+(5*factor);
                    when '6'    => val  := val+(6*factor);
                    when '7'    => val  := val+(7*factor);
                    when '8'    => val  := val+(8*factor);
                    when '9'    => val  := val+(9*factor);
                    when '0'    => null;
                    when others => r.error  := '1'; r.state := WAITING_FOR_RESPONSE_END;
                end case;
            end if;
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
                            r.state := EXPECTING_ANY_RESP_R;
                        when others =>
                            r.error := '1';
                            r.state := WAITING_FOR_RESPONSE_END;
                    end case;
                end if;
            
            -- ROK / OK
            
            when EXPECTING_ROK_O =>
                expect_char('O', EXPECTING_ROK_OK_K, true);
            
            when EXPECTING_ROK_OK_K =>
                expect_char('K', SETTING_OK, true);
            
            when SETTING_OK =>
                if resp_end then
                    r.ok    := '1';
                end if;
            
            -- any response
            
            when EXPECTING_ANY_RESP_R =>
                expect_char('R', EXPECTING_RCOI_RDAI_RDII_RSLE_RCCRCNF_RESP_C_D_S, true);
            
            -- RCOI / RDAI / RDII / RSLE / RCCRCNF response
            
            when EXPECTING_RCOI_RDAI_RDII_RSLE_RCCRCNF_RESP_C_D_S =>
                expect_char('C', EXPECTING_RCOI_RCCRCNF_RESP_O_C, true);
                expect_char('D', EXPECTING_RDAI_RDII_RESP_A_I);
                expect_char('S', EXPECTING_RSLE_RESP_L);
            
            -- RCOI / RCCRCNF response
            
            when EXPECTING_RCOI_RCCRCNF_RESP_O_C =>
                expect_char('O', EXPECTING_RCOI_RESP_I, true);
                expect_char('C', EXPECTING_RCCRCNF_RESP_C2);
            
            -- RCOI response
            
            when EXPECTING_RCOI_RESP_I =>
                expect_char('I', EXPECTING_RCOI_RESP_EQUALS, true);
            
            when EXPECTING_RCOI_RESP_EQUALS =>
                expect_char('=', SETTING_CONNECTED, true);
            
            when SETTING_CONNECTED =>
                r.connected := '1';
                r.state     := WAITING_FOR_RESPONSE_END;
            
            -- RCCRCNF response
            
            when EXPECTING_RCCRCNF_RESP_C2 =>
                expect_char('C', EXPECTING_RCCRCNF_RESP_R, true);
            
            when EXPECTING_RCCRCNF_RESP_R =>
                expect_char('R', EXPECTING_RCCRCNF_RESP_C3, true);
            
            when EXPECTING_RCCRCNF_RESP_C3 =>
                expect_char('C', EXPECTING_RCCRCNF_RESP_N, true);
            
            when EXPECTING_RCCRCNF_RESP_N =>
                expect_char('N', EXPECTING_RCCRCNF_RESP_F, true);
            
            when EXPECTING_RCCRCNF_RESP_F =>
                expect_char('F', EXPECTING_RCCRCNF_RESP_EQUALS, true);
            
            when EXPECTING_RCCRCNF_RESP_EQUALS =>
                expect_char('=', EVALUATING_RCCRCNF_RESP_MTU1, true);
            
            when EVALUATING_RCCRCNF_RESP_MTU1 =>
                r.mtu_size  := uns(0, 10);
                eval_dec_char(r.mtu_size, 100, EVALUATING_RCCRCNF_RESP_MTU2);
            
            when EVALUATING_RCCRCNF_RESP_MTU2 =>
                eval_dec_char(r.mtu_size, 10, EVALUATING_RCCRCNF_RESP_MTU3);
            
            when EVALUATING_RCCRCNF_RESP_MTU3 =>
                eval_dec_char(r.mtu_size, 1, EXPECTING_RCCRCNF_RESP_COMMA1);
            
            when EXPECTING_RCCRCNF_RESP_COMMA1 =>
                r.byte_counter  := uns(31, 11);
                expect_char(',', IGNORING_RCCRCNF_RESP_SERVICE, true);
            
            when IGNORING_RCCRCNF_RESP_SERVICE =>
                if rx_valid='1' then
                    r.byte_counter  := cr.byte_counter-1;
                end if;
                if cr.byte_counter(cr.byte_counter'high)='1' then
                    r.state := EXPECTING_RCCRCNF_RESP_COMMA2;
                end if;
            
            when EXPECTING_RCCRCNF_RESP_COMMA2 =>
                expect_char(',', EVALUATING_RCCRCNF_RESP_CON_STATE, true);
            
            when EVALUATING_RCCRCNF_RESP_CON_STATE =>
                expect_char('0', SETTING_CON_CONFIRMED, true);
                expect_char('1', UNSETTING_CON_CONFIRMED);
            
            when SETTING_CON_CONFIRMED =>
                r.con_confirmed := '1';
                r.state         := WAITING_FOR_RESPONSE_END;
            
            when UNSETTING_CON_CONFIRMED =>
                r.con_confirmed := '0';
                r.state         := WAITING_FOR_RESPONSE_END;
            
            -- RDAI response
            
            when EXPECTING_RDAI_RDII_RESP_A_I =>
                expect_char('A', EXPECTING_RDAI_RESP_I, true);
                expect_char('I', EXPECTING_RDII_RESP_I2);
            
            when EXPECTING_RDAI_RESP_I =>
                expect_char('I', EXPECTING_RDAI_RESP_EQUALS, true);
            
            when EXPECTING_RDAI_RESP_EQUALS =>
                expect_char('=', EVALUATING_RDAI_RESP_DATA_LEN1, true);
            
            when EVALUATING_RDAI_RESP_DATA_LEN1 =>
                r.data_length   := uns(0, 10);
                eval_dec_char(r.data_length, 100, EVALUATING_RDAI_RESP_DATA_LEN2);
            
            when EVALUATING_RDAI_RESP_DATA_LEN2 =>
                eval_dec_char(r.data_length, 10, EVALUATING_RDAI_RESP_DATA_LEN3);
            
            when EVALUATING_RDAI_RESP_DATA_LEN3 =>
                eval_dec_char(r.data_length, 1, EXPECTING_RDAI_RESP_COMMA);
            
            when EXPECTING_RDAI_RESP_COMMA =>
                r.byte_counter  := resize(cr.data_length, 11)-1;
                expect_char(',', RECEIVE_DATA_BYTE, true);
            
            when RECEIVE_DATA_BYTE =>
                r.packet_valid  := '1';
                if rx_valid='1' then
                    r.byte_counter  := cr.byte_counter-1;
                end if;
                if cr.byte_counter(cr.byte_counter'high)='1' then
                    r.state := WAITING_FOR_RESPONSE_END;
                end if;
            
            when EXPECTING_RSLE_RESP_L =>
                expect_char('L', EXPECTING_RSLE_RESP_E, true);
            
            when EXPECTING_RSLE_RESP_E =>
                -- ignore the 'Secure Link Established' info for now
                expect_char('E', WAITING_FOR_RESPONSE_END, true);
            
            -- RDII response
            
            when EXPECTING_RDII_RESP_I2 =>
                expect_char('I', UNSETTING_CONNECTED, true);
            
            when UNSETTING_CONNECTED =>
                r.connected     := '0';
                r.con_confirmed := '0';
                r.state         := WAITING_FOR_RESPONSE_END;
            
            -- response end
            
            when WAITING_FOR_RESPONSE_END =>
                r.packet_valid  := '0';
            
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
