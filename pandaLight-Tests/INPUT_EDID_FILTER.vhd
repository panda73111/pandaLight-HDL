----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    12:29:59 10/07/2014 
-- Module Name:    EDID_FILTER - rtl 
-- Project Name:   PandaLight
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--  Data flow is from the DDC slave at the TX port to the
--  DDC master at the RX port, which sets the clock signal
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity INPUT_EDID_FILTER is
    generic (
        READ_ADDR       : std_ulogic_vector(7 downto 0) := x"A1";
        WRITE_ADDR      : std_ulogic_vector(7 downto 0) := x"A0";
        SEG_P_ADDR      : std_ulogic_vector(7 downto 0) := x"60"
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        RX_SDA_IN   : in std_ulogic;
        RX_SDA_OUT  : out std_ulogic := '1';
        RX_SCL_IN   : in std_ulogic;
        RX_SCL_OUT  : out std_ulogic := '1';
        
        TX_SDA_IN   : in std_ulogic;
        TX_SDA_OUT  : out std_ulogic := '1';
        TX_SCL_IN   : in std_ulogic;
        TX_SCL_OUT  : out std_ulogic := '1';
        
        RX_DET  : in std_ulogic;
        TX_DET  : in std_ulogic;
        
        RX_EN   : out std_ulogic := '0';
        TX_EN   : out std_ulogic := '0'
        
    );
end INPUT_EDID_FILTER;

architecture rtl of INPUT_EDID_FILTER is
    
    type state_type is (
        INIT
    );
    
    type reg_type is record
        state           : state_type;
        rx_sda_out      : std_ulogic;
        segment_pointer : std_ulogic_vector(6 downto 0);
        byte            : std_ulogic_vector(7 downto 0);
        bit_index       : unsigned(2 downto 0); -- 0..7
        block_number    : std_ulogic_vector(7 downto 0);
    end record;
    
    signal cur_reg, next_reg    : reg_type_def := (
        state           => INIT,
        rx_sda_out      => '1'
        segment_pointer => "0000000",
        byte            => x"00",
        bit_index       => uns(7, 3),
        block_number    => x"00"
    );
    
    signal rx_sda_in_q  : std_ulogic := '1';
    signal rx_scl_in_q  : std_ulogic := '1';
    signal stop         : std_ulogic := '0';
    
begin
    
    -- pass through the detect signals
    RX_EN   <= TX_DET;
    TX_EN   <= RX_DET;
    
    -- pass through the DDC signals,
    -- filter the data signal to the master
    RX_SCL_OUT  <= TX_SCL_IN;
    RX_SDA_OUT  <= cur_reg.rx_sda_out;
    TX_SCL_OUT  <= RX_SCL_IN;
    TX_SDA_OUT  <= RX_SDA_IN;
    
    stop_detect_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            rx_sda_in_q <= RX_SDA_IN;
            rx_scl_in_q <= RX_SCL_IN;
            -- stop condition: SDA from low to high while SCL remains high
            -- (from the master at RX)
            stop    <=
                (rx_scl_in_q and RX_SCL_IN) and
                (not rx_sda_in_q and RX_SDA_IN);
        end if;
    end process;
    
    ---------------------
    --- state machine ---
    ---------------------
    
    stm_proc : process(cur_reg, RST, RX_DET, TX_DET,
        TX_SCL_IN, TX_SDA_IN, RX_SCL_IN, RX_SDA_IN)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cr;
        
        r.rx_sda_out    := TX_SDA_IN;
        
        case cr.state is
            
            when INIT =>
                r.bit_index := uns(7, 3);
                r.state     := WAIT_FOR_CONNECTION;
            
            when WAIT_FOR_CONNECTION =>
                if (RX_DET and TX_DET)='1' then
                    r.state := WAIT_FOR_SENDER;
                end if;
            
            when WAIT_FOR_SENDER =>
                if (RX_SCL_IN and RX_SDA_IN)='1' then
                    r.state := WAIT_FOR_START;
                end if;
            
            when WAIT_FOR_START =>
                if RX_SDA_IN='0' then
                    r.state := GET_ADDR_WAIT_FOR_SCL_LOW;
                end if;
            
            when GET_ADDR_WAIT_FOR_SCL_LOW =>
                if RX_SCL_IN='0' then
                    r.state := GET_ADDR_WAIT_FOR_SCL_HIGH;
                end if;
            
            when GET_ADDR_WAIT_FOR_SCL_HIGH =>
                r.byte(int(cr.bit_index))   := RX_SDA_IN;
                if SCL_IN='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GET_ADDR_WAIT_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := CHECK_ADDR_WAIT_FOR_SCL_LOW;
                    end if;
                end if;
            
            when CHECK_ADDR_WAIT_FOR_SCL_LOW =>
                if RX_SCL_IN='0' then
                    r.state := CHECK_ADDR;
                end if;
            
            when CHECK_ADDR =>
                if    cr.byte=SEG_P_ADDR then r.state  := SEG_P_ADDR_GET_ACK_WAIT_FOR_SCL_HIGH;
                elsif cr.byte=WRITE_ADDR then r.state  := WRITE_ADDR_GET_ACK_WAIT_FOR_SCL_HIGH;
                elsif cr.byte=READ_ADDR  then r.state  := REQUEST_BLOCK;
                else                          r.state  := INIT; -- unrecognized address
                end if;
            
            when SEG_P_ADDR_GET_ACK_WAIT_FOR_SCL_HIGH =>
                if RX_SCL_IN='1' then
                    r.state := SEG_P_ADDR_SEND_ACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when SEG_P_ADDR_GET_ACK_WAIT_FOR_SCL_LOW =>
                -- the segment pointer acknowledge is ignored in case
                -- the slave doesn't support segments
                if RX_SCL_IN='0' then
                    r.state := GET_SEG_P_WAIT_FOR_SCL_HIGH;
                end if;
            
            when GET_SEG_P_WAIT_FOR_SCL_HIGH =>
                r.byte(int(cr.bit_index))   := SDA_IN;
                -- check for first block of that segment
                r.block_number              := cr.byte(6 downto 0) & "0";
                r.segment_pointer           := cr.byte(6 downto 0);
                if RX_SCL_IN='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GET_SEG_P_WAIT_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := CHECK_FOR_BLOCK_WAIT_FOR_SCL_LOW;
                    end if;
                end if;
            
            when GET_SEG_P_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := GET_SEG_P_WAIT_FOR_SCL_HIGH;
                end if;
            
            when CHECK_FOR_BLOCK_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := CHECK_FOR_BLOCK;
                end if;
            
            when CHECK_FOR_BLOCK =>
                -- stretch the clock until the requested block is checked
                r.scl_out       := '0';
                r.block_check   := '1';
                if BLOCK_VALID='1' then
                    r.state := BLOCK_NUM_SEND_ACK_WAIT_FOR_SCL_HIGH;
                end if;
                if BLOCK_INVALID='1' then
                    r.state := SEND_NACK_WAIT_FOR_SCL_HIGH;
                end if;
            
            when BLOCK_NUM_SEND_ACK_WAIT_FOR_SCL_HIGH =>
                r.sda_out   := '0';
                if SCL_IN='1' then
                    r.state := BLOCK_NUM_SEND_ACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when BLOCK_NUM_SEND_ACK_WAIT_FOR_SCL_LOW =>
                r.sda_out   := '0';
                if SCL_IN='0' then
                    r.state := INIT;
                end if;
            
            when WRITE_ADDR_SEND_ACK_WAIT_FOR_SCL_HIGH =>
                r.sda_out   := '0';
                if SCL_IN='1' then
                    r.state := WRITE_ADDR_SEND_ACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when WRITE_ADDR_SEND_ACK_WAIT_FOR_SCL_LOW =>
                r.sda_out   := '0';
                if SCL_IN='0' then
                    r.state := GET_WORD_OFFS_WAIT_FOR_SCL_HIGH;
                end if;
            
            when GET_WORD_OFFS_WAIT_FOR_SCL_HIGH =>
                r.byte(int(cr.bit_index))   := SDA_IN;
                -- the highest bit of the word offset determines the block in that segment
                r.block_number              := cr.segment_pointer & cr.byte(7);
                if SCL_IN='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GET_WORD_OFFS_WAIT_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := CHECK_FOR_BLOCK_WAIT_FOR_SCL_LOW;
                    end if;
                end if;
            
            when GET_WORD_OFFS_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := GET_WORD_OFFS_WAIT_FOR_SCL_HIGH;
                end if;
            
            when REQUEST_BLOCK =>
                -- stretch the clock until the requested block has been written to the RAM
                r.scl_out       := '0';
                r.block_request := '1';
                if BLOCK_VALID='1' then
                    r.state := READ_ADDR_SEND_ACK_WAIT_FOR_SCL_HIGH;
                end if;
                if BLOCK_INVALID='1' then
                    r.state := SEND_NACK_WAIT_FOR_SCL_HIGH;
                end if;
            
            when READ_ADDR_SEND_ACK_WAIT_FOR_SCL_HIGH =>
                r.sda_out   := '0';
                if SCL_IN='1' then
                    r.state := READ_ADDR_SEND_ACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when READ_ADDR_SEND_ACK_WAIT_FOR_SCL_LOW =>
                r.sda_out   := '0';
                if SCL_IN='0' then
                    r.state := SEND_BYTE_WAIT_FOR_SCL_HIGH;
                end if;
            
            when SEND_BYTE_WAIT_FOR_SCL_HIGH =>
                r.sda_out   := ram_dout(int(cr.bit_index));
                if SCL_IN='1' then
                    r.state := SEND_BYTE_WAIT_FOR_SCL_LOW;
                end if;
            
            when SEND_BYTE_WAIT_FOR_SCL_LOW =>
                r.sda_out   := ram_dout(int(cr.bit_index));
                if SCL_IN='0' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := SEND_BYTE_WAIT_FOR_SCL_HIGH;
                    if cr.bit_index=0 then
                        r.state := CHECK_FOR_BLOCK_END;
                    end if;
                end if;
            
            when CHECK_FOR_BLOCK_END =>
                r.state := SEND_BYTE_GET_ACK_WAIT_FOR_SCL_HIGH;
                if cr.ram_rd_addr=BLOCK_SIZE-1 then
                    -- second block of segment
                    r.block_number(0)   := '1';
                    r.state             := REQUEST_BLOCK;
                end if;
            
            when SEND_BYTE_GET_ACK_WAIT_FOR_SCL_HIGH =>
                if SCL_IN='1' then
                    r.state := SEND_BYTE_GET_ACK_WAIT_FOR_SCL_LOW;
                    if SDA_IN='1' then
                        -- NACK from master, end of transmission
                        r.state := INIT;
                    end if;
                end if;
            
            when SEND_BYTE_GET_ACK_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.ram_rd_addr   := cr.ram_rd_addr+1;
                    r.state         := SEND_BYTE_WAIT_FOR_SCL_HIGH;
                end if;
            
            when SEND_NACK_WAIT_FOR_SCL_HIGH =>
                if SCL_IN='1' then
                    r.state := SEND_NACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when SEND_NACK_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := INIT;
                end if;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        next_reg    <= r;
    end process;
    
    sync_stm_proc : process(CLK, RST)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;

