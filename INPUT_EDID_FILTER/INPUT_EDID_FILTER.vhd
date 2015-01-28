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
        rx_scl_out      : std_ulogic;
        rx_sda_out      : std_ulogic;
        tx_scl_out      : std_ulogic;
        segment_pointer : std_ulogic_vector(6 downto 0);
        byte            : std_ulogic_vector(7 downto 0);
        bit_index       : unsigned(2 downto 0); -- 0..7
        block_number    : std_ulogic_vector(7 downto 0);
    end record;
    
    signal cur_reg, next_reg    : reg_type_def := (
        state           => INIT,
        rx_scl_out      => '1',
        rx_sda_out      => '1',
        tx_scl_out      => '1',
        segment_pointer => "0000000",
        byte            => x"00",
        bit_index       => uns(7, 3),
        block_number    => x"00"
    );
    
    signal rx_sda_in_sync   : std_ulogic := '1';
    signal rx_scl_in_sync   : std_ulogic := '1';
    signal tx_sda_in_sync   : std_ulogic := '1';
    signal tx_scl_in_sync   : std_ulogic := '1';
    
    signal rx_sda_in_q  : std_ulogic := '1';
    signal rx_scl_in_q  : std_ulogic := '1';
    signal stop         : std_ulogic := '0';
    
begin
    
    -- pass through the detect signals
    RX_EN   <= TX_DET;
    TX_EN   <= RX_DET;
    
    -- pass through the DDC signals,
    -- filter the clock signals for clock stretching and
    -- the data signal to the master for injections
    
    rx_sda_in_SIGNAL_SYNC_INST : entity work.SIGNAL_SYNC generic map ('1') port map (CLK, RX_SDA_IN, rx_sda_in_sync);
    rx_scl_in_SIGNAL_SYNC_INST : entity work.SIGNAL_SYNC generic map ('1') port map (CLK, RX_SCL_IN, rx_scl_in_sync);
    tx_sda_in_SIGNAL_SYNC_INST : entity work.SIGNAL_SYNC generic map ('1') port map (CLK, TX_SDA_IN, tx_sda_in_sync);
    tx_scl_in_SIGNAL_SYNC_INST : entity work.SIGNAL_SYNC generic map ('1') port map (CLK, TX_SCL_IN, tx_scl_in_sync);
    
    scl_BIDIR_REPEAT_BUFFER_inst : entity work.BIDIR_REPEAT_BUFFER
        generic map (PULL => "UP")
        port map (
            CLK => CLK,
            
            P0_IN   => cur_reg.tx_scl_out,
            P0_OUT  => RX_SCL_OUT,
            P1_IN   => cur_reg.rx_scl_out,
            P1_OUT  => TX_SCL_OUT
        );
    
    sda_BIDIR_REPEAT_BUFFER_inst : entity work.BIDIR_REPEAT_BUFFER
        generic map (PULL => "UP")
        port map (
            CLK => CLK,
            
            P0_IN   => rx_sda_in_sync,
            P0_OUT  => RX_SDA_OUT,
            P1_IN   => cur_reg.rx_sda_out,
            P1_OUT  => TX_SDA_OUT
        );
    
    stop_detect_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            rx_sda_in_q <= rx_sda_in_sync;
            rx_scl_in_q <= rx_scl_in_sync;
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
        tx_scl_in_sync, tx_sda_in_sync, rx_scl_in_sync, rx_sda_in_sync)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cr;
        
        r.rx_scl_out    := tx_scl_in_sync;
        r.rx_sda_out    := tx_sda_in_sync;
        r.tx_scl_out    := rx_scl_in_sync;
        
        case cr.state is
            
            when INITIALIZING =>
                r.bit_index := uns(7, 3);
                r.state     := WAITING_FOR_CONNECTION;
            
            when WAITING_FOR_CONNECTION =>
                if (RX_DET and TX_DET)='1' then
                    r.state := WAITING_FOR_SENDER;
                end if;
            
            when WAITING_FOR_SENDER =>
                if (rx_scl_in_sync and rx_sda_in_sync)='1' then
                    r.state := WAITING_FOR_START;
                end if;
            
            when WAITING_FOR_START =>
                if rx_sda_in_sync='0' then
                    r.state := GETTING_ADDR_WAITING_FOR_SCL_LOW;
                end if;
            
            when GETTING_ADDR_WAITING_FOR_SCL_LOW =>
                if rx_scl_in_sync='0' then
                    r.state := GETTING_ADDR_WAITING_FOR_SCL_HIGH;
                end if;
            
            when GETTING_ADDR_WAITING_FOR_SCL_HIGH =>
                r.byte(int(cr.bit_index))   := rx_sda_in_sync;
                if rx_scl_in_sync='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GETTING_ADDR_WAITING_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := CHECKING_ADDR_WAITING_FOR_SCL_LOW;
                    end if;
                end if;
            
            when CHECKING_ADDR_WAITING_FOR_SCL_LOW =>
                if rx_scl_in_sync='0' then
                    r.state := CHECKING_ADDR;
                end if;
            
            when CHECKING_ADDR =>
                if    cr.byte=SEG_P_ADDR then r.state  := SEG_P_ADDR_GETTING_ACK_WAITING_FOR_SCL_HIGH;
                elsif cr.byte=WRITE_ADDR then r.state  := WRITE_ADDR_GETTING_ACK_WAITING_FOR_SCL_HIGH;
                elsif cr.byte=READ_ADDR  then r.state  := READ_ADDR_GETTING_ACK_WAITING_FOR_SCL_HIGH;
                else                          r.state  := INITIALIZING; -- unrecognized address
                end if;
            
            when SEG_P_ADDR_GETTING_ACK_WAITING_FOR_SCL_HIGH =>
                if rx_scl_in_sync='1' then
                    r.state := SEG_P_ADDR_GETTING_ACK_WAITING_FOR_SCL_LOW;
                end if;
            
            when SEG_P_ADDR_GETTING_ACK_WAITING_FOR_SCL_LOW =>
                -- the segment pointer acknowledge is ignored in case
                -- the slave doesn't support segments
                if rx_scl_in_sync='0' then
                    r.state := GETTING_SEG_P_WAITING_FOR_SCL_HIGH;
                end if;
            
            when GETTING_SEG_P_WAITING_FOR_SCL_HIGH =>
                r.byte(int(cr.bit_index))   := rx_sda_in_sync;
                -- check for first block of that segment
                r.block_number              := cr.byte(6 downto 0) & "0";
                r.segment_pointer           := cr.byte(6 downto 0);
                if rx_scl_in_sync='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GETTING_SEG_P_WAITING_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := GETTING_SEG_P_ACK_WAITING_FOR_SCL_LOW;
                    end if;
                end if;
            
            when GETTING_SEG_P_WAITING_FOR_SCL_LOW =>
                if rx_scl_in_sync='0' then
                    r.state := GETTING_SEG_P_WAITING_FOR_SCL_HIGH;
                end if;
            
            when GETTING_SEG_P_ACK_WAITING_FOR_SCL_LOW =>
                if rx_scl_in_sync='0' then
                    r.state := GETTING_SEG_P_ACK_WAITING_FOR_SCL_HIGH;
                end if;
            
            when GETTING_SEG_P_ACK_WAITING_FOR_SCL_HIGH =>
                if rx_scl_in_sync='1' then
                    r.state := WAITING_FOR_START;
                end if;
            
            when WRITE_ADDR_GETTING_ACK_WAITING_FOR_SCL_HIGH =>
                if rx_scl_in_sync='1' then
                    r.state := GETTING_WORD_OFFS_WAITING_FOR_SCL_LOW;
                    if tx_sda_in='1' then
                        -- got NACK for writing the word offset; no slave?!
                        r.state := INITIALIZING;
                    end if;
                end if;
            
            when GETTING_WORD_OFFS_WAITING_FOR_SCL_LOW =>
                if rx_scl_in_sync='0' then
                    r.state := GETTING_WORD_OFFS_WAITING_FOR_SCL_HIGH;
                end if;
            
            when GETTING_WORD_OFFS_WAITING_FOR_SCL_HIGH =>
                r.byte(int(cr.bit_index))   := rx_sda_in_sync;
                -- the highest bit of the word offset determines the block in that segment
                r.block_number  := cr.segment_pointer & cr.byte(7);
                if rx_scl_in_sync='1' then
                    r.bit_index := cr.bit_index-1;
                    r.state     := GETTING_WORD_OFFS_WAITING_FOR_SCL_LOW;
                    if cr.bit_index=0 then
                        r.state := WAITING_FOR_START;
                    end if;
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

