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
    
   --Inputs
   signal slave_clk             : std_ulogic := '0';
   signal slave_rst             : std_ulogic := '0';
   signal slave_data_in_addr    : std_ulogic_vector(6 downto 0) := (others => '0');
   signal slave_data_in_wr_en   : std_ulogic := '0';
   signal slave_data_in         : std_ulogic_vector(7 downto 0) := (others => '0');
   signal slave_block_valid     : std_ulogic := '0';
   signal slave_block_invalid   : std_ulogic := '0';
   
   --bidirs
   signal slave_sda_in  : std_ulogic := '0';
   signal slave_sda_out : std_ulogic;
   signal slave_scl_in  : std_ulogic := '0';
   signal slave_scl_out : std_ulogic;

    --outputs
   signal slave_block_check     : std_ulogic;
   signal slave_block_request   : std_ulogic;
   signal slave_block_number    : std_ulogic_vector(7 downto 0);
   signal slave_busy            : std_ulogic;

   -- Clock period definitions
    constant clk_period         : time := 10 ns; -- 100 MHz
    constant master_clk_period  : time := 10 us; -- 100 kHz
    
    constant clk_period_real    : real := real(clk_period / 1 ps) / real(1 ns / 1 ps);
    
    signal clk, rst     : std_ulogic := '0';
    signal global_sda   : std_ulogic := '1';
    signal global_scl   : std_ulogic := '1';
 
BEGIN
    
    slave_clk   <= clk;
    slave_rst   <= rst;
    
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
    
    -- clock generation
    clk <= not clk after clk_period / 2;
    
    -- Stimulus process
    stim_proc: process
    begin
        -- hold reset state for 100 ns.
        wait for 100 ns;

        wait for clk_period*10;

        -- insert stimulus here 

        wait;
    end process;

END;
