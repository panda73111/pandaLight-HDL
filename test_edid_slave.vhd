----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:20:52 01/31/2014 
-- Module Name:    DDC_EDID_MASTER_tb_test1 - rtl 
-- Project Name:   DDC_MASTER
-- Description:    First test: DDC2B receiver, one EDID block
-- 
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments:
--   EDID table from http://www.komeil.com/download/656
--   EDID bytes:
--    0x   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
--        ------------------------------------------------
--    00 | 00 FF FF FF FF FF FF 00 5A 63 1D E5 01 01 01 01
--    10 | 20 10 01 03 80 2B 1B 78 2E CF E5 A3 5A 49 A0 24
--    20 | 13 50 54 BF EF 80 B3 0F 81 80 81 40 71 4F 31 0A
--    30 | 01 01 01 01 01 01 21 39 90 30 62 1A 27 40 68 B0
--    40 | 36 00 B1 0F 11 00 00 1C 00 00 00 FF 00 51 36 59
--    50 | 30 36 30 30 30 30 30 30 30 0A 00 00 00 FD 00 32
--    60 | 4B 1E 52 11 00 0A 20 20 20 20 20 20 00 00 00 FC
--    70 | 00 56 58 32 30 32 35 77 6D 0A 20 20 20 20 00 FE
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;
use work.txt_util.all;
use work.ddc_edid_tb_funcs.all;

entity test_edid_slave is
    generic (
        CLK_PERIOD          : time;
        VERBOSE             : boolean := false;
        CORE_NAME           : string := "Receiver 1";
        WR_ADDR             : std_ulogic_vector(7 downto 0) := x"A0";
        RD_ADDR             : std_ulogic_vector(7 downto 0) := x"A1";
        STRETCH_DURATION    : time := 10 us
    );
    port (
        CLK     : in std_ulogic;
        
        SDA_IN  : in std_ulogic;
        SDA_OUT : out std_ulogic := '1';
        SCL_IN  : in std_ulogic;
        SCL_OUT : out std_ulogic := '1';
        
        ACTIVATE            : in std_ulogic := '1';
        CLOCK_STRETCHING    : in std_ulogic := '0';
        BYTE_READ_VALID     : in std_ulogic := '0';
        BYTE_READ           : in std_ulogic_vector(7 downto 0) := x"00";
        BYTE_READ_INDEX     : in std_ulogic_vector(6 downto 0) := "0000000";
        
        BUSY                : out std_ulogic := '0';
        TRANSM_ERROR        : out std_ulogic := '0';
        READ_ERROR          : out std_ulogic := '0'
    );
end test_edid_slave;

architecture rtl of test_edid_slave is
    
    type edid_block_type is array(0 to 127) of std_ulogic_vector(7 downto 0);
    constant test1_edid_block0  : edid_block_type := (
        x"00", x"FF", x"FF", x"FF", x"FF", x"FF", x"FF", x"00", x"5A", x"63", x"1D", x"E5", x"01", x"01", x"01", x"01",
        x"20", x"10", x"01", x"03", x"80", x"2B", x"1B", x"78", x"2E", x"CF", x"E5", x"A3", x"5A", x"49", x"A0", x"24",
        x"13", x"50", x"54", x"BF", x"EF", x"80", x"B3", x"0F", x"81", x"80", x"81", x"40", x"71", x"4F", x"31", x"0A",
        x"01", x"01", x"01", x"01", x"01", x"01", x"21", x"39", x"90", x"30", x"62", x"1A", x"27", x"40", x"68", x"B0",
        x"36", x"00", x"B1", x"0F", x"11", x"00", x"00", x"1C", x"00", x"00", x"00", x"FF", x"00", x"51", x"36", x"59",
        x"30", x"36", x"30", x"30", x"30", x"30", x"30", x"30", x"30", x"0A", x"00", x"00", x"00", x"FD", x"00", x"32",
        x"4B", x"1E", x"52", x"11", x"00", x"0A", x"20", x"20", x"20", x"20", x"20", x"20", x"00", x"00", x"00", x"FC",
        x"00", x"56", x"58", x"32", x"30", x"32", x"35", x"77", x"6D", x"0A", x"20", x"20", x"20", x"20", x"00", x"FE"
    );
    
    signal active   : boolean := false;
    
begin
    
    DDC_EDID_MASTER_tb_slave1_proc : process
        variable word_offset    : unsigned(7 downto 0) := x"00";
        variable byte           : std_ulogic_vector(7 downto 0) := x"00";
        variable addr_match     : boolean := false;
        variable ack            : boolean := false;
    begin
        active  <= false;
        BUSY    <= '0';
        
        if ACTIVATE='0' then wait until ACTIVATE = '1'; end if;
        assert not VERBOSE
            report CORE_NAME & ": Activated"
            severity NOTE;
        
        active          <= true;
        BUSY            <= '1';
        TRANSM_ERROR    <= '0';
        
        -- get write address
        addr_match  := false;
        while not addr_match loop
            -- wait for start condition
            wait_for_start(VERBOSE, CORE_NAME, SCL_IN, SDA_IN);
            get_address(VERBOSE, CORE_NAME, WR_ADDR, SCL_IN, SDA_IN, CLK_PERIOD, addr_match);
        end loop;
        
        -- send ACK
        send_ack(VERBOSE, CORE_NAME, SCL_IN, SDA_OUT, CLK_PERIOD);
        if CLOCK_STRETCHING = '1' then
            stretch_clock(VERBOSE, CORE_NAME, SCL_OUT, STRETCH_DURATION);
        end if;
        
        -- get word offset
        get_word_offset(VERBOSE, CORE_NAME, SCL_IN, SDA_IN, CLK_PERIOD, word_offset);
        
        -- send ACK
        send_ack(VERBOSE, CORE_NAME, SCL_IN, SDA_OUT, CLK_PERIOD);
        if CLOCK_STRETCHING = '1' then
            stretch_clock(VERBOSE, CORE_NAME, SCL_OUT, STRETCH_DURATION);
        end if;
        
        -- get read address
        addr_match  := false;
        while not addr_match loop
            -- wait for repeated start condition
            wait_for_start(VERBOSE, CORE_NAME, SCL_IN, SDA_IN);
            get_address(VERBOSE, CORE_NAME, RD_ADDR, SCL_IN, SDA_IN, CLK_PERIOD, addr_match);
        end loop;
        
        -- send ACK
        send_ack(VERBOSE, CORE_NAME, SCL_IN, SDA_OUT, CLK_PERIOD);
        if CLOCK_STRETCHING = '1' then
            stretch_clock(VERBOSE, CORE_NAME, SCL_OUT, STRETCH_DURATION);
        end if;
        
        -- send the EDID table
        for byte_index in 0 to 127 loop
            -- send byte
            byte    := test1_edid_block0(byte_index);
            send_byte(VERBOSE, CORE_NAME, SCL_IN, SDA_OUT, CLK_PERIOD, byte_index, byte);
            
            -- wait for ACK
            get_ack(VERBOSE, CORE_NAME, SCL_IN, SDA_IN, CLK_PERIOD, ack);
            if not ack then
                if byte_index < 127 then
                    -- the master should have read the whole block
                    report CORE_NAME & ": Premature transmission stop by master"
                    severity ERROR;
                    TRANSM_ERROR    <= '1';
                end if;
                wait_for_stop(VERBOSE, CORE_NAME, SCL_IN, SDA_IN);
                exit;
            elsif CLOCK_STRETCHING = '1' then
                stretch_clock(VERBOSE, CORE_NAME, SCL_OUT, STRETCH_DURATION);
            end if;
        end loop;
    end process;
    
    byte_match_proc : process
        variable index      : natural := 0;
        variable edid_byte  : std_ulogic_vector(7 downto 0) := (others => '0');
    begin
        wait until active;
        READ_ERROR  <= '0';
        while active loop
            wait until rising_edge(CLK);
            if BYTE_READ_VALID = '1' then
                index       := int(BYTE_READ_INDEX);
                edid_byte   := test1_edid_block0(index);
                if BYTE_READ /= edid_byte then
                    report CORE_NAME & ": Byte " & integer'image(index) &
                        " read by master does not match byte of EDID block: sent 0x" &
                        hstr(edid_byte) & ", read 0x" & hstr(BYTE_READ)
                    severity ERROR;
                    READ_ERROR  <= '1';
                end if;
            end if;
        end loop;
    end process;
    
end rtl;

