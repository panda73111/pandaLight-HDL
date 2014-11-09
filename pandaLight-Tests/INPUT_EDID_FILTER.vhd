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
        INIT,
        WAIT_FOR_TX_CONN
    );
    
    type reg_type is record
        state       : state_type;
        rx_en       : std_ulogic;
        tx_en       : std_ulogic;
        m_start     : std_ulogic;
        m_block_num : std_ulogic_vector(7 downto 0);
    end record;
    
    signal cur_reg, next_reg    : reg_type_def := (
        state       => INIT,
        rx_en       => '0',
        tx_en       => '0',
        m_start     => '0',
        m_block_num => '0'
    );
    
begin
    
    RX_EN   <= cur_reg.rx_en;
    TX_EN   <= cur_reg.tx_en;
    
    eddc_m_start    <= cur_reg.m_start;
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    E_DDC_MASTER_inst : entity work.E_DDC_MASTER
        generic map (
            CLK_IN_PERIOD   => CLK_PERIOD
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            SDA_IN  => TX_SDA_IN,
            SDA_OUT => TX_SDA_OUT,
            SCL_IN  => TX_SCL_IN,
            SCL_OUT => TX_SCLK_OUT,
            
            START           => eddc_m_start,
            BLOCK_NUMBER    => eddc_m_block_number,
            
            BUSY            => eddc_m_busy,
            TRANSM_ERROR    => eddc_m_transm_error,
            DATA_OUT        => eddc_m_data_out,
            DATA_OUT_VALID  => eddc_m_data_out_valid,
            BYTE_INDEX      => eddc_m_byte_index
        );
    
    
    -----------------------------------
    ------ E-DDC (E-)EDID Slave ------
    -----------------------------------
    
    E_DDC_SLAVE_inst : entity work.E_DDC_SLAVE
        port map (
            CLK => CLK,
            RST => RST,
            
            SDA_IN  => RX_SDA_IN,
            SDA_OUT => RX_SDA_OUT,
            SCL_IN  => RX_SCL_IN,
            SCL_OUT => RX_SCLK_OUT,
            
            DATA_IN_ADDR    => eddc_s_data_in_addr,
            DATA_IN_WR_EN   => eddc_s_data_in_wr_en,
            DATA_IN         => eddc_s_data_in,
            BLOCK_VALID     => eddc_s_block_valid,
            BLOCK_INVALID   => eddc_s_block_invalid,
            
            BLOCK_CHECK     => eddc_s_block_check,
            BLOCK_REQUEST   => eddc_s_block_request,
            BLOCK_NUMBER    => eddc_s_block_number,
            BUSY            => eddc_s_busy
        );
    
    
    ---------------------
    --- state machine ---
    ---------------------
    
    stm_proc : process(cur_reg, RST, RX_DET, TX_DET, eddc_s_busy)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.tx_en     := '1';
        r.m_start   := '0';
        
        case cr.state is
            
            when INIT =>
                r.state             := WAIT_FOR_TX_CON;
            
            when WAIT_FOR_RX_CONN =>
                -- wait for a receiver connection at the TX port
                -- (which has the EDID data)
                if TX_DET='1' then
                    r.state := WAIT_FOR_RX_CON;
                end if;
            
            when WAIT_FOR_TX_CON =>
                -- activate the RX port,
                -- wait for a sender connection
                r.rx_en := '1';
                if RX_DET='1' then
                    r.state := WAIT_FOR_TX_ACTIVITY;
                end if;
            
            when WAIT_FOR_TX_ACTIVITY =>
                if eddc_s_busy='1' then
                    r.state := READ_BYTE;
                end if;
            
            when READ_BLOCK =>
                r.m_start   := '1';
                r.state     := WAIT_FOR_BYTE;
            
            when WAIT_FOR_BYTE =>
                if m_data_out_valid='1' then
                    r.state <= EVAL_BYTE;
                end if;
                if m_transm_error='1' then
                    -- TODO: read block again?
                    r.state <= INIT;
                end if;
            
            when EVAL_BYTE =>
                
            
        end case;
        
        if RST='1' or TX_DET='0' then
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

