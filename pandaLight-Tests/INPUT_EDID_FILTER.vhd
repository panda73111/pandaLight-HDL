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
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity INPUT_EDID_FILTER is
    generic (
        CLK_PERIOD  : real
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        RX_SDA_IN  : in std_ulogic;
        RX_SDA_OUT : out std_ulogic := '1';
        RX_SCL_IN  : in std_ulogic;
        RX_SCL_OUT : out std_ulogic := '1';
        
        TX_SDA_IN  : in std_ulogic;
        TX_SDA_OUT : out std_ulogic := '1';
        TX_SCL_IN  : in std_ulogic;
        TX_SCL_OUT : out std_ulogic := '1';
        
        
    );
end INPUT_EDID_FILTER;

architecture rtl of INPUT_EDID_FILTER is
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    -- Inputs
    signal eddc_m_start : std_ulogic := '0';

    -- BiDirs
    signal eddc_m_sda_in    : std_ulogic := '1';
    signal eddc_m_sda_out   : std_ulogic := '1';
    signal eddc_m_scl_in    : std_ulogic := '1';
    signal eddc_m_scl_out   : std_ulogic := '1';

    -- Outputs
    signal eddc_m_block_number      : std_ulogic_vector(7 downto 0) := (others => '0');
    signal eddc_m_busy              : std_ulogic := '0';
    signal eddc_m_transm_error      : std_ulogic := '0';
    signal eddc_m_data_out          : std_ulogic_vector(7 downto 0) := (others => '0');
    signal eddc_m_data_out_valid    : std_ulogic := '0';
    signal eddc_m_byte_index        : std_ulogic_vector(6 downto 0) := (others => '0');
    
    
    ----------------------------------
    ------ E-DDC (E-)EDID Slave ------
    ----------------------------------
    
    -- Inputs
    signal eddc_s_clk      : std_ulogic := '0';
    signal eddc_s_rst      : std_ulogic := '0';
    
    signal eddc_s_data_in_addr  : std_ulogic_vector(6 downto 0) := (others => '0');
    signal eddc_s_data_in_wr_en : std_ulogic := '0';
    signal eddc_s_data_in       : std_ulogic_vector(7 downto 0) := (others => '0');
    signal eddc_s_block_valid   : std_ulogic := '0';
    signal eddc_s_block_invalid : std_ulogic := '0';

    -- BiDirs
    signal eddc_s_sda_in   : std_ulogic := '1';
    signal eddc_s_sda_out  : std_ulogic := '1';
    signal eddc_s_scl_in   : std_ulogic := '1';
    signal eddc_s_scl_out  : std_ulogic := '1';

    -- Outputs
    signal eddc_s_block_check      : std_ulogic := '0';
    signal eddc_s_block_request    : std_ulogic := '0';
    signal eddc_s_block_number     : std_ulogic_vector(7 downto 0) := (others => '0');
    signal eddc_s_busy             : std_ulogic := '0';
    
    
    ----------------------
    ------ EDID RAM ------
    ----------------------
    
    -- Inputs
    signal ram_rd_addr  : std_ulogic_vector(6 downto 0) := (others => '0');
    signal ram_wr_en    : std_ulogic := '0';
    signal ram_wr_addr  : std_ulogic_vector(6 downto 0) := (others => '0');
    signal ram_din      : std_ulogic_vector(7 downto 0) := (others => '0');
    
    -- Outputs
    signal ram_dout : std_ulogic_vector(7 downto 0) := (others => '0');
    
begin
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    eddc_m_sda_in       <= SDA_IN;
    eddc_m_scl_in       <= SCL_IN;
    
    E_DDC_MASTER_inst : entity work.E_DDC_MASTER
        generic map (
            CLK_IN_PERIOD   => CLK_PERIOD
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            SDA_IN  => eddc_m_sda_in,
            SDA_OUT => eddc_m_sda_out,
            SCL_IN  => eddc_m_scl_in,
            SCL_OUT => eddc_m_scl_out,
            
            START           => eddc_m_start,
            BLOCK_NUMBER    => eddc_m_block_number,
            
            BUSY            => eddc_m_busy,
            TRANSM_ERROR    => eddc_m_transm_error,
            DATA_OUT        => eddc_m_data_out,
            DATA_OUT_VALID  => eddc_m_data_out_valid,
            BYTE_INDEX      => eddc_m_byte_index
        );
    
    
    ----------------------
    ------ EDID RAM ------
    ----------------------
    
    ram_wr_en   <= eddc_m_data_out_valid;
    ram_wr_addr <= eddc_m_byte_index;
    ram_din     <= eddc_m_data_out_valid;
    
    edid_ram_inst : entity work.DUAL_PORT_RAM
        generic map (
            WIDTH   => 8,
            DEPTH   => 128
        )
        port map (
            CLK         => edid_ram_clk,
            
            RD_ADDR     => edid_ram_rd_addr,
            WR_EN       => edid_ram_wr_en,
            WR_ADDR     => edid_ram_wr_addr,
            DIN         => edid_ram_din,
            
            DOUT    => edid_ram_dout
        );
    
    
end rtl;

