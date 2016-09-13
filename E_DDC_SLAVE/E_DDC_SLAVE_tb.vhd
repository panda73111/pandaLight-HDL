--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   15:38:39 08/14/2014
-- Module Name:   /home/sebastian/GitHub/VHDL/pandaLight-HDL/E_DDC_SLAVE/E_DDC_SLAVE_tb.vhd
-- Project Name:  E_DDC_SLAVE
-- Tool versions: Xilinx ISE 14.7
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: E_DDC_SLAVE
-- 
-- Additional Comments:
--
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;
use work.txt_util.all;
 
ENTITY E_DDC_SLAVE_tb IS
END E_DDC_SLAVE_tb;
 
ARCHITECTURE behavior OF E_DDC_SLAVE_tb IS 
    
    -------------
    --- slave ---
    -------------
    
    --Inputs
    signal slave_clk            : std_ulogic := '0';
    signal slave_rst            : std_ulogic := '0';
    signal slave_data_in_addr   : std_ulogic_vector(6 downto 0) := (others => '0');
    signal slave_data_in_wr_en  : std_ulogic := '0';
    signal slave_data_in        : std_ulogic_vector(7 downto 0) := (others => '0');
    signal slave_block_valid    : std_ulogic := '0';
    signal slave_block_invalid  : std_ulogic := '0';

    --bidirs
    signal slave_sda_in     : std_ulogic := '0';
    signal slave_sda_out    : std_ulogic;
    signal slave_scl_in     : std_ulogic := '0';
    signal slave_scl_out    : std_ulogic;

    --outputs
    signal slave_block_check    : std_ulogic;
    signal slave_block_request  : std_ulogic;
    signal slave_block_number   : std_ulogic_vector(7 downto 0);
    signal slave_busy           : std_ulogic;
    
    
    --------------
    --- master ---
    --------------
    
    --Inputs
    signal master_clk           : std_ulogic := '0';
    signal master_rst           : std_ulogic := '0';
    signal master_start         : std_ulogic := '0';
    signal master_block_number  :std_ulogic_vector(7 downto 0) := x"00";

    --bidirs
    signal master_sda_in    : std_ulogic := '0';
    signal master_sda_out   : std_ulogic;
    signal master_scl_in    : std_ulogic := '0';
    signal master_scl_out   : std_ulogic;

    --outputs
    signal master_busy              : std_ulogic;
    signal master_transm_error      : std_ulogic;
    signal master_data_out          : std_ulogic_vector(7 downto 0);
    signal master_data_out_valid    : std_ulogic;
    signal master_byte_index        : std_ulogic_vector(6 downto 0);

    -- Clock period definitions
    constant clk_period         : time := 10 ns; -- 100 MHz

    constant clk_period_real    : real := real(clk_period / 1 ps) / real(1 ns / 1 ps);

    signal clk, rst     : std_ulogic := '0';
    signal global_sda   : std_ulogic := '1';
    signal global_scl   : std_ulogic := '1';

BEGIN
    
    slave_clk   <= clk;
    slave_rst   <= rst;
    
    slave_sda_in    <= global_sda;
    slave_scl_in    <= global_scl;
    
    master_clk  <= clk;
    master_rst  <= rst;
    
    master_sda_in   <= global_sda;
    master_scl_in   <= global_scl;
    
    global_sda  <= '0' when slave_sda_out='0' or master_sda_out='0' else 'Z';
    global_scl  <= '0' when slave_scl_out='0' or master_scl_out='0' else 'Z';
    
    E_DDC_SLAVE_inst : entity work.E_DDC_SLAVE
        port map (
            CLK => slave_clk,
            RST => slave_rst,
            
            DATA_IN_ADDR    => slave_data_in_addr,
            DATA_IN_WR_EN   => slave_data_in_wr_en,
            DATA_IN         => slave_data_in,
            BLOCK_VALID     => slave_block_valid,
            BLOCK_INVALID   => slave_block_invalid,
            SDA_IN          => slave_sda_in,
            SCL_IN          => slave_scl_in,
            
            SDA_OUT         => slave_sda_out,
            SCL_OUT         => slave_scl_out,
            BLOCK_CHECK     => slave_block_check,
            BLOCK_REQUEST   => slave_block_request,
            BLOCK_NUMBER    => slave_block_number,
            BUSY            => slave_busy
        );
    
    E_DDC_MASTER_inst : entity work.E_DDC_MASTER
        generic map (
            CLK_IN_PERIOD   => clk_period_real
        )
        port map (
            CLK => master_clk,
            RST => master_rst,
            
            START           => master_start,
            BLOCK_NUMBER    => master_block_number,
            SDA_IN          => master_sda_in,
            SDA_OUT         => master_sda_out,
            
            SCL_IN          => master_scl_in,
            SCL_OUT         => master_scl_out,
            BUSY            => master_busy,
            TRANSM_ERROR    => master_transm_error,
            DATA_OUT        => master_data_out,
            DATA_OUT_VALID  => master_data_out_valid,
            BYTE_INDEX      => master_byte_index
        );
    
    -- clock generation
    clk <= not clk after clk_period / 2;
    
    write_slave_edid_proc : process
        -- example EDID block from the EDID specification rel. A, rev. 2, example 2
        type edid_block_type is array(0 to 127) of std_ulogic_vector(7 downto 0);
        type edid_blocks_type is array(0 to 1) of edid_block_type;
        constant edid_blocks    : edid_blocks_type := (
            -- block 0
            (
                x"00", x"FF", x"FF", x"FF", x"FF", x"FF", x"FF", x"00", x"04", x"43", x"07", x"F2", x"01", x"00", x"00", x"00", 
                x"FF", x"11", x"01", x"04", x"A2", x"4F", x"00", x"78", x"1E", x"EE", x"91", x"A3", x"54", x"4C", x"99", x"26", 
                x"0F", x"50", x"54", x"20", x"00", x"00", x"01", x"01", x"01", x"01", x"01", x"01", x"01", x"01", x"01", x"01", 
                x"01", x"01", x"01", x"01", x"01", x"01", x"02", x"3A", x"80", x"18", x"71", x"38", x"2D", x"40", x"58", x"2C", 
                x"04", x"05", x"0F", x"48", x"42", x"00", x"00", x"1E", x"01", x"1D", x"80", x"18", x"71", x"1C", x"16", x"20", 
                x"58", x"2C", x"25", x"00", x"0F", x"48", x"42", x"00", x"00", x"9E", x"01", x"1D", x"00", x"72", x"51", x"D0", 
                x"1E", x"20", x"6E", x"28", x"55", x"00", x"0F", x"48", x"42", x"00", x"00", x"1E", x"00", x"00", x"00", x"FC", 
                x"00", x"41", x"42", x"43", x"20", x"4C", x"43", x"44", x"34", x"37", x"77", x"0A", x"20", x"20", x"01", x"CB"
            ),
            -- block 1
            (
                x"02", x"03", x"18", x"72", x"47", x"90", x"85", x"04", x"03", x"02", x"07", x"06", x"23", x"09", x"07", x"07", 
                x"83", x"01", x"00", x"00", x"65", x"03", x"0C", x"00", x"10", x"00", x"8E", x"0A", x"D0", x"8A", x"20", x"E0", 
                x"2D", x"10", x"10", x"3E", x"96", x"00", x"1F", x"09", x"00", x"00", x"00", x"18", x"8E", x"0A", x"D0", x"8A", 
                x"20", x"E0", x"2D", x"10", x"10", x"3E", x"96", x"00", x"04", x"03", x"00", x"00", x"00", x"18", x"8E", x"0A", 
                x"A0", x"14", x"51", x"F0", x"16", x"00", x"26", x"7C", x"43", x"00", x"1F", x"09", x"00", x"00", x"00", x"98", 
                x"8E", x"0A", x"A0", x"14", x"51", x"F0", x"16", x"00", x"26", x"7C", x"43", x"00", x"04", x"03", x"00", x"00", 
                x"00", x"98", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", 
                x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"C9"
            )
        );
        
    begin
        wait until rising_edge(clk);
        
        slave_block_valid   <= '0';
        slave_block_invalid <= '0';
        slave_data_in_wr_en <= '0';
        
        if slave_block_check='1' then
            if slave_block_number<2 then
                slave_block_valid   <= '1';
            else
                slave_block_invalid <= '1';
            end if;
        end if;
        
        if slave_block_request='1' then
            if slave_block_number<2 then
                slave_data_in_wr_en <= '1';
                for i in 0 to 127 loop
                    slave_data_in       <= edid_blocks(int(slave_block_number))(i);
                    slave_data_in_addr  <= stdulv(i, 7);
                    wait until rising_edge(clk);
                end loop;
                slave_block_valid   <= '1';
            else
                slave_block_invalid <= '1';
            end if;
        end if;
        
    end process;
    
    -- Stimulus process
    stim_proc: process
    begin
        -- hold reset state for 100 ns.
        wait for 100 ns;
        
        wait for clk_period*10;
        
        -- insert stimulus here
        
        -- Read block 0
        wait until rising_edge(clk);
        master_block_number <= x"00";
        master_start        <= '1';
        wait until rising_edge(clk);
        master_start    <= '0';
        
        wait until master_busy='1';
        wait until master_busy='0';
        
        wait for clk_period*200;
        
        -- Read block 1
        wait until rising_edge(clk);
        master_block_number <= x"01";
        master_start        <= '1';
        wait until rising_edge(clk);
        master_start    <= '0';
        
        wait until master_busy='1';
        wait until master_busy='0';
        
        wait for clk_period*200;
        report "NONE. All tests successful, quitting" severity FAILURE;
        
    end process;

END;
