
library IEEE;
use IEEE.STD_LOGIC_1164.all;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;
use work.txt_util.all;

package DDC_EDID_tb_funcs is
    
    procedure wait_for_start
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic
    );
    
    procedure wait_for_stop
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic
    );
    
    procedure get_address
    (
        verbose         : in boolean;
        core_name       : in string;
        match_addr      : in std_ulogic_vector(7 downto 0);
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic;
        clk_period      : in time;
        addr_match      : out boolean
    );
    
    procedure get_word_offset
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic;
        clk_period      : in time;
        word_offset     : out unsigned(7 downto 0)
    );
    
    procedure send_byte
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_out  : out std_ulogic;
        clk_period      : in time;
        byte_index      : in integer;
        byte            : in std_ulogic_vector(7 downto 0)
    );
    
    procedure send_ack
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_out  : out std_ulogic;
        clk_period      : in time
    );
    
    procedure get_ack
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic;
        clk_period      : in time;
        ack             : out boolean
    );
    
    procedure stretch_clock
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_out  : out std_ulogic;
        duration        : in time
    );
    
end DDC_EDID_tb_funcs;

package body DDC_EDID_tb_funcs is
    
    -- wait for start condition from master
    
    procedure wait_for_start
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic
    ) is
    begin
        assert not verbose
            report core_name & ": Waiting for start condition"
            severity NOTE;
        wait until falling_edge(sda_in) and scl_in = '1';
        -- stop condition
        assert not verbose
            report core_name & ": Got start condition"
            severity NOTE;
    end procedure;
    
    -- wait for stop condition from master
    
    procedure wait_for_stop
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic
    ) is
    begin
        assert not verbose
            report core_name & ": Waiting for stop condition"
            severity NOTE;
        wait until rising_edge(sda_in) and scl_in = '1';
        -- stop condition
        assert not verbose
            report core_name & ": Got stop condition"
            severity NOTE;
    end procedure;
    
    -- get address byte from master
    
    procedure get_address
    (
        verbose         : in boolean;
        core_name       : in string;
        match_addr      : in std_ulogic_vector(7 downto 0);
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic;
        clk_period      : in time;
        addr_match      : out boolean
    ) is
        variable address    : std_ulogic_vector(7 downto 0) := x"00";
    begin
        assert not verbose
            report core_name & ": Waiting for address: 0x" & hstr(match_addr)
            severity NOTE;
        for bit_index in 7 downto 0 loop
            wait until rising_edge(scl_in);
            wait for clk_period / 4;
            address(bit_index)  := sda_in;
        end loop;
        assert not verbose
            report core_name & ": Got address: 0x" & hstr(address)
            severity NOTE;
        
        if address = match_addr then
            assert not verbose
                report core_name & ": Addresses match"
                severity NOTE;
            addr_match  := true;
        else
            assert not verbose
                report core_name & ": Addresses don't match"
                severity NOTE;
            addr_match  := false;
        end if;
        wait until falling_edge(scl_in);
        wait for clk_period / 4;
    end procedure;
    
    
    -- get word offset
    
    procedure get_word_offset
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic;
        clk_period      : in time;
        word_offset     : out unsigned(7 downto 0)
    ) is
        variable offs   : unsigned(7 downto 0) := x"00";
    begin
        for bit_index in 7 downto 0 loop
            wait until rising_edge(scl_in);
            wait for clk_period / 4;
            offs(bit_index) := sda_in;
        end loop;
        assert not verbose
            report core_name & ": Got word offset: 0x" & hstr(stdulv(offs))
            severity NOTE;
        word_offset := offs;
        wait until falling_edge(scl_in);
        wait for clk_period / 4;
    end procedure;
    
    -- send byte
    
    procedure send_byte
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_out  : out std_ulogic;
        clk_period      : in time;
        byte_index      : in integer;
        byte            : in std_ulogic_vector(7 downto 0)
    ) is
    begin
        assert not verbose
            report core_name & ": Sending byte " & integer'image(byte_index) & ": 0x" & hstr(byte)
            severity NOTE;
        for bit_index in 7 downto 0 loop
            sda_out <= byte(bit_index);
            wait until falling_edge(scl_in);
            wait for clk_period / 4;
        end loop;
        sda_out <= '1'; -- release sda
    end procedure;
    
    -- send acknowledge to master
    
    procedure send_ack
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_out  : out std_ulogic;
        clk_period      : in time
    ) is
    begin
        assert not verbose
            report core_name & ": Sending ACK"
            severity NOTE;
        sda_out <= '0';
        wait until falling_edge(scl_in);
        wait for clk_period / 4;
        assert not verbose
            report core_name & ": Sent ACK"
            severity NOTE;
        sda_out <= '1'; -- release sda
    end procedure;
    
    -- receive acknowledge from master
    
    procedure get_ack
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_in   : in std_ulogic;
        signal sda_in   : in std_ulogic;
        clk_period      : in time;
        ack             : out boolean
    ) is
    begin
        assert not verbose
            report core_name & ": Waiting for ACK"
            severity NOTE;
        wait until rising_edge(scl_in);
        wait for clk_period / 4;
        if sda_in = '0' then
            assert not verbose
                report core_name & ": Got ACK"
                severity NOTE;
            ack := true;
        else
            assert not verbose
                report core_name & ": Got NACK"
                severity NOTE;
            ack := false;
        end if;
        wait until falling_edge(scl_in);
        wait for clk_period / 4;
    end procedure;
    
    -- stretch the clock by holding scl low
    
    procedure stretch_clock
    (
        verbose         : in boolean;
        core_name       : in string;
        signal scl_out  : out std_ulogic;
        duration        : in time
    ) is
    begin
        assert not verbose
            report core_name & ": Stretching scl for " & time'image(duration)
            severity NOTE;
        scl_out <= '0';
        wait for duration;
        scl_out <= '1'; -- release scl
    end procedure;
    
end DDC_EDID_tb_funcs;
