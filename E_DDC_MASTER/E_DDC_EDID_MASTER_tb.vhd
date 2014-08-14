--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   17:50:45 01/30/2014
-- Module Name:   DDC_EDID_MASTER_tb
-- Project Name:  DDC_MASTER
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: DDC_EDID_MASTER
-- 
-- Additional Comments:
--   First test: DDC2B receiver, one EDID block
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;
use work.txt_util.all;
 
ENTITY DDC_EDID_MASTER_tb IS
END DDC_EDID_MASTER_tb;
 
ARCHITECTURE behavior OF DDC_EDID_MASTER_tb IS 

    --Inputs
    signal ddc_edid_clk     : std_ulogic := '0';
    signal ddc_edid_rst     : std_ulogic := '0';
    signal ddc_edid_start   : std_ulogic := '0';

    --BiDirs
    signal ddc_edid_sda_in  : std_ulogic := '1';
    signal ddc_edid_sda_out : std_ulogic := '1';
    signal ddc_edid_scl_in  : std_ulogic := '1';
    signal ddc_edid_scl_out : std_ulogic := '1';

    --Outputs
    signal ddc_edid_busy            : std_ulogic := '0';
    signal ddc_edid_transm_error    : std_ulogic := '0';
    signal ddc_edid_data_out        : std_ulogic_vector(7 downto 0) := (others => '0');
    signal ddc_edid_data_out_valid  : std_ulogic := '0';
    signal ddc_edid_byte_index      : std_ulogic_vector(6 downto 0) := (others => '0');
    signal ddc_edid_block_number    : std_ulogic_vector(7 downto 0) := (others => '0');
    
    -- Clock period definitions
--    constant clk_period             : time := 10 ns; -- 100 MHz
    constant clk_period             : time := 2.5 us; -- 400 kHz, for very fast simulation
    constant receiver_clk_period    : time := 10 us; -- 100 kHz
    
    constant clk_period_real    : real := real(clk_period / 1 ps) / real(1 ns / 1 ps);
    
    signal clk, rst     : std_ulogic := '0';
    signal global_sda   : std_ulogic := '1';
    signal global_scl   : std_ulogic := '1';
    
    signal slave1_sda_in            : std_ulogic := '1';
    signal slave1_sda_out           : std_ulogic := '1';
    signal slave1_scl_in            : std_ulogic := '1';
    signal slave1_scl_out           : std_ulogic := '1';
    signal slave1_activate          : std_ulogic := '0';
    signal slave1_clock_stretching  : std_ulogic := '0';
    signal slave1_byte_read_valid   : std_ulogic := '0';
    signal slave1_byte_read         : std_ulogic_vector(7 downto 0) := (others => '0');
    signal slave1_byte_read_index   : std_ulogic_vector(6 downto 0) := (others => '0');
    signal slave1_busy              : std_ulogic := '0';
    signal slave1_transm_error      : std_ulogic := '0';
    signal slave1_read_error        : std_ulogic := '0';
    
BEGIN
    
    ddc_edid_clk    <= clk;
    ddc_edid_rst    <= rst;
    
    -- low dominant I2C bus
    global_sda      <= ddc_edid_sda_out and slave1_sda_out;
    global_scl      <= ddc_edid_scl_out and slave1_scl_out;
    ddc_edid_sda_in <= global_sda;
    ddc_edid_scl_in <= global_scl;
    slave1_sda_in   <= global_sda;
    slave1_scl_in   <= global_scl;
    
    slave1_byte_read_valid  <= ddc_edid_data_out_valid;
    slave1_byte_read        <= ddc_edid_data_out;
    slave1_byte_read_index  <= ddc_edid_byte_index;
    
    DDC_EDID_MASTER_inst : entity work.DDC_EDID_MASTER
        generic map (
            CLK_IN_PERIOD   => clk_period_real
        )
        port map (
            CLK             => ddc_edid_clk,
            RST             => ddc_edid_rst,
            
            SDA_IN          => ddc_edid_sda_in,
            SDA_OUT         => ddc_edid_sda_out,
            SCL_IN          => ddc_edid_scl_in,
            SCL_OUT         => ddc_edid_scl_out,
            
            START           => ddc_edid_start,
            BLOCK_NUMBER    => ddc_edid_block_number,
            
            BUSY            => ddc_edid_busy,
            TRANSM_ERROR    => ddc_edid_transm_error,
            DATA_OUT        => ddc_edid_data_out,
            DATA_OUT_VALID  => ddc_edid_data_out_valid,
            BYTE_INDEX      => ddc_edid_byte_index
        );
    
    -- clock generation
    clk <= not clk after clk_period / 2;
    
    slave1_inst : entity work.DDC_EDID_MASTER_tb_slave1
        generic map (
            VERBOSE     => false,
            CLK_PERIOD  => receiver_clk_period
        )
        port map (
            CLK => clk,
            RST => rst,
            
            SDA_IN  => slave1_sda_in,
            SDA_OUT => slave1_sda_out,
            SCL_IN  => slave1_scl_in,
            SCL_OUT => slave1_scl_out,
            
            ACTIVATE            => slave1_activate,
            CLOCK_STRETCHING    => slave1_clock_stretching,
            BYTE_READ_VALID     => slave1_byte_read_valid,
            BYTE_READ           => slave1_byte_read,
            BYTE_READ_INDEX     => slave1_byte_read_index,
            BUSY                => slave1_busy,
            TRANSM_ERROR        => slave1_transm_error,
            READ_ERROR          => slave1_read_error
        );
    
    -- Stimulus process
    stim_proc: process
        constant test_timeout       : time := 20 ms;
        variable test_start_time    : time;
        variable timed_out          : boolean;
        
        procedure start_slave1_test (test_number : in natural) is
            constant test_str    : string := "Test " & natural'image(test_number);
        begin
            test_start_time := now;
            report test_str & " started at " & time'image(test_start_time);
            ddc_edid_start      <= '1';
            wait until rising_edge(clk);
            ddc_edid_start  <= '0';
            wait until ddc_edid_busy = '1';
            
            while ddc_edid_busy = '1' loop
                wait for 1 us;
                assert (now - test_start_time) <= test_timeout
                    report test_str & " timed out"
                    severity FAILURE;
            end loop;
            
            wait for 50 us;
            
            assert ddc_edid_transm_error = '0'
                report test_str & " ended with transmission error in DDC master"
                severity FAILURE;
            assert slave1_transm_error = '0'
                report test_str & " ended with transmission error in DDC slave"
                severity FAILURE;
            assert slave1_read_error = '0'
                report test_str & " ended with read error from DDC slave"
                severity FAILURE;
            assert slave1_busy = '0'
                report test_str & " slave still busy"
                severity FAILURE;
        end procedure;
        
        procedure start_error_test (test_number : in natural) is
            constant test_str   : string := "Test " & natural'image(test_number);
        begin
            test_start_time := now;
            report test_str & " started at " & time'image(test_start_time);
            ddc_edid_start      <= '1';
            wait until rising_edge(clk);
            ddc_edid_start  <= '0';
            wait until ddc_edid_busy = '1';
            
            while ddc_edid_busy = '1' loop
                wait for 1 us;
                assert (now - test_start_time) <= test_timeout
                    report test_str & " timed out"
                    severity FAILURE;
            end loop;
            
            wait for 50 us;
            
            assert ddc_edid_transm_error = '1'
                report test_str & " ended without expected transmission error in DDC master"
                severity FAILURE;
        end procedure;
    begin		
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for clk_period*10;
        wait until rising_edge(clk);
        
        ------ Test 1: receiver 1, without clock stretching ------
        slave1_clock_stretching  <= '0';
        slave1_activate  <= '1';
        wait until rising_edge(clk);
        slave1_activate  <= '0';
        start_slave1_test(1);
        report "Test 1 completed successfully";
        
        wait for clk_period*10;
        wait until rising_edge(clk);
        
        ------ Test 2: receiver 1, with clock stretching ------
        slave1_clock_stretching  <= '1';
        slave1_activate  <= '1';
        wait until rising_edge(clk);
        slave1_activate  <= '0';
        start_slave1_test(2);
        report "Test 2 completed successfully";
        
        wait for clk_period*10;
        wait until rising_edge(clk);
        
        ------ Test 3: no receiver, expecting error ------
        start_error_test(3);
        report "Test 3 completed successfully";
        
        wait for clk_period*10;
        wait until rising_edge(clk);
        
        assert false report "NONE. All tests successful, quitting" severity FAILURE;
    end process;

END;
