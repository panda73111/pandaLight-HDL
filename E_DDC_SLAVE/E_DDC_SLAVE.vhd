----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    13:17:27 08/12/2014 
-- Module Name:    E_DDC_SLAVE - rtl 
-- Project Name:   E_DDC_SLAVE
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--   This core implements the enhanced display data channel (1.1) in slave mode
--   and is compatible to DDC2B
-- Additional Comments:
--   Generic:
--     READ_ADDR     : 8bit read address of the DDC receiver, usually 0xA1
--     WRITE_ADDR    : 8bit write address of the DDC receiver, usually 0xA0
--     SEG_P_ADDR    : 8bit write address of the segment pointer, usually 0x60
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity E_DDC_SLAVE is
    generic (
        READ_ADDR       : std_ulogic_vector(7 downto 0) := x"A1";
        WRITE_ADDR      : std_ulogic_vector(7 downto 0) := x"A0";
        SEG_P_ADDR      : std_ulogic_vector(7 downto 0) := x"60"
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        DATA_IN_ADDR    : in std_ulogic_vector(6 downto 0);
        DATA_IN_WR_EN   : in std_ulogic;
        DATA_IN         : in std_ulogic_vector(7 downto 0);
        BLOCK_VALID     : in std_ulogic;
        BLOCK_INVALID   : in std_ulogic;
        
        SDA_IN  : in std_ulogic;
        SDA_OUT : out std_ulogic := '1';
        SCL_IN  : in std_ulogic;
        SCL_OUT : out std_ulogic := '1';
        
        BLOCK_REQUEST   : out std_ulogic := '0';
        BLOCK_NUMBER    : out std_ulogic_vector(7 downto 0) := x"00";
        BUSY            : out std_ulogic := '0';
        TRANSM_ERROR    : out std_ulogic := '0'
    );
end E_DDC_SLAVE;

architecture rtl of E_DDC_SLAVE is
    
    constant FIRST_BLOCK_WORD_OFFS  : std_ulogic_vector(7 downto 0) := x"00";
    constant SECOND_BLOCK_WORD_OFFS : std_ulogic_vector(7 downto 0) := x"80";
    
    type state_type is (
        INIT,
        WAIT_FOR_START
    );
    
    type reg_type is record
        state           : state_type;
        sda_out         : std_ulogic;
        scl_out         : std_ulogic;
        segment_pointer : unsigned(7 downto 0);
        error           : std_ulogic;
        byte            : std_ulogic_vector(7 downto 0);
        bit_index       : unsigned(2 downto 0); -- 0..7
        byte_index      : unsigned(6 downto 0); -- counts bytes of one EDID block (128 bytes)
        block_request   : std_ulogic;
        block_number    : std_ulogic_vector(7 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => INIT,
        sda_out         => '1',
        scl_out         => '1',
        segment_pointer => (others => '0'),
        error           => '0',
        byte            => x"00",
        bit_index       => uns(7, 3),
        byte_index      => uns(127, 7),
        block_request   => '0',
        block_number    => x"00"
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal ram_rd_addr  : std_ulogic_vector(15 downto 0) := x"0000";
    signal ram_dout     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal sda_in_q : std_ulogic := '1';
    signal scl_in_q : std_ulogic := '1';
    signal stop     : std_ulogic := '0';
    
begin
    
    SDA_OUT <= cur_reg.sda_out;
    SCL_OUT <= cur_reg.scl_out;
    
    BUSY            <= '0' when cur_reg.state=WAIT_FOR_START else '1';
    TRANSM_ERROR    <= cur_reg.error;
    
    BLOCK_REQUEST   <= cur_reg.block_request;
    BLOCK_NUMBER    <= cur_reg.block_number;
    
    DUAL_PORT_RAM_inst : entity work.DUAL_PORT_RAM
        generic map (
            WIDTH   => 8,
            DEPTH   => 128
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            RD_ADDR => ram_rd_addr,
            WR_EN   => DATA_IN_WR_EN,
            WR_ADDR => DATA_IN_ADDR,
            DIN     => DATA_IN,
            
            DOUT    => ram_dout
        );
    
    stop_detect_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            sda_in_q    <= SDA_IN;
            scl_in_q    <= SCL_IN;
            -- stop condition: SDA from low to high while SCL remains high
            stop        <=
                (scl_in_q and SCL_IN) and
                (not sda_in_q and SDA_IN);
        end if;
    end process;
    
    finite_state_machine : process(RST, cur_reg, BLOCK_VALID, BLOCK_INVALID, SDA_IN, SCL_IN, stop)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cr;
        
        r.scl_out       := '1';
        r.sda_out       := '1';
        r.block_request := '0';
        
        case cur_reg.state is
            
            when INIT =>
                r.bit_index     := uns(7, 3);
                r.byte_index    := uns(127, 7);
                r.state         := WAIT_FOR_SENDER;
            
            when WAIT_FOR_SENDER =>
                if (SCL_IN and SDA_IN)='1' then
                    r.state := WAIT_FOR_START;
                end if;
            
            when WAIT_FOR_START =>
                if SDA_IN='0' then
                    r.state := GET_ADDR_WAIT_FOR_SCL_LOW;
                end if;
            
            when GET_ADDR_WAIT_FOR_SCL_LOW =>
                if SCL_LOW='0' then
                    r.state := GET_ADDR_WAIT_FOR_SCL_HIGH;
                end if;
            
            when GET_ADDR_WAIT_FOR_SCL_HIGH =>
                r.byte(cr.bit_index)    := SDA_IN;
                if SCL_IN='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GET_ADDR_WAIT_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := CHECK_ADDR_WAIT_FOR_SCL_LOW;
                    end if;
                end if;
            
            when CHECK_ADDR_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := CHECK_ADDR;
                end if;
            
            when CHECK_ADDR =>
                case cr.byte is
                    when SEG_P_ADDR => r.state  := SEG_P_SEND_ACK_WAIT_FOR_SCL_HIGH;
                    when WRITE_ADDR => r.state  := WORD_OFFS_SEND_ACK_WAIT_FOR_SCL_HIGH;
                    when READ_ADDR  => r.state  := READ_SEND_ACK_WAIT_FOR_SCL_HIGH;
                    when others     => r.state  := INIT; -- unrecognized address
                end case;
            
            when SEG_P_SEND_ACK_WAIT_FOR_SCL_HIGH =>
                r.sda_out   := '0';
                if SCL_IN='1' then
                    r.state := SEG_P_SEND_ACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when SEG_P_SEND_ACK_WAIT_FOR_SCL_LOW =>
                r.sda_out   := '0';
                if SCL_IN='0' then
                    r.state := GET_SEG_P_WAIT_FOR_SCL_HIGH;
                end if;
            
            when GET_SEG_P_WAIT_FOR_SCL_HIGH =>
                r.byte(cr.bit_index)    := SDA_IN;
                if SCL_IN='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GET_SEG_P_WAIT_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := WAIT_FOR_BLOCK_WAIT_FOR_SCL_LOW;
                    end if;
                end if;
            
            when GET_SEG_P_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := GET_SEG_P_WAIT_FOR_SCL_HIGH;
                end if;
            
            when WAIT_FOR_BLOCK_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := WAIT_FOR_BLOCK;
                end if;
            
            when WAIT_FOR_BLOCK =>
                -- stretch the clock until the requested block is available
                r.scl_out       := '0';
                r.block_number  := cr.byte;
                r.block_request := '1';
                if BLOCK_VALID='1' then
                    r.state := BLOCK_SEND_ACK_WAIT_FOR_SCL_HIGH;
                end if;
                if BLOCK_INVALID='1' then
                    r.state := BLOCK_SEND_NACK_WAIT_FOR_SCL_HIGH;
                end if;
            
            when BLOCK_SEND_ACK_WAIT_FOR_SCL_HIGH =>
                r.sda_out   := '0';
                if SCL_IN='1' then
                    r.state := BLOCK_SEND_ACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when BLOCK_SEND_ACK_WAIT_FOR_SCL_LOW =>
                r.sda_out   := '0';
                if SCL_IN='0' then
                    r.state := INIT;
                end if;
            
            when BLOCK_SEND_NACK_WAIT_FOR_SCL_HIGH =>
                if SCL_IN='1' then
                    r.state := BLOCK_SEND_NACK_WAIT_FOR_SCL_LOW;
                end if;
            
            when BLOCK_SEND_NACK_WAIT_FOR_SCL_LOW =>
                if SCL_IN='0' then
                    r.state := INIT;
                end if;
            
            when WORD_OFFS_SEND_ACK_WAIT_FOR_SCL_HIGH =>
                
            
        end case;
        
        if RST='1' or stop='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;

    sync_stm : process(RST, CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end;
