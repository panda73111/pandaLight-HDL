----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    11:00:32 02/21/2014 
-- Module Name:    TMDS_CHANNEL_IDELAY - rtl 
-- Description: 
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity TMDS_CHANNEL_IDELAY is
    generic (
        SIM_TAP_DELAY   : integer range 20 to 100 := 50
    );
    port (
        PIX_CLK     : in std_ulogic;
        PIX_CLK_X2  : in std_ulogic;
        RST         : in std_ulogic;
        
        CHANNEL_IN      : in std_ulogic;
        INCDEC          : in std_ulogic;
        INCDEC_VALID    : in std_ulogic;
        
        BUSY    : out std_ulogic := '0'
    );
end TMDS_CHANNEL_IDELAY;

architecture rtl of TMDS_CHANNEL_IDELAY is
    
    -------------------------------------------------------
    ------ calibration state machine types & signals ------
    -------------------------------------------------------
    
    type delay_state_type is (
        INIT_FIRST_WAIT_FOR_READY,
        INIT_CALIBRATE,
        INIT_RESET,
        INIT_SECOND_WAIT_FOR_READY,
        IDLE,
        CALIBRATE_SLAVE,
        WAIT_FOR_SLAVE_CALIBRATE_ACK,
        WAIT_FOR_READY
    );
    
    type delay_reg_type is record
        state               : delay_state_type;
        counter             : unsigned(8 downto 0);
        enable              : boolean;
        calibrate_master    : std_ulogic;
        calibrate_slave     : std_ulogic;
        rst                 : std_ulogic;
    end record;
    
    constant delay_reg_type_def : delay_reg_type := (
        state               => INIT_FIRST_WAIT_FOR_READY,
        counter             => to_unsigned(0, delay_reg_type.counter'length),
        enable              => false,
        calibrate_master    => '0',
        calibrate_slave     => '0',
        rst                 => '0'
    );
    
    
    -----------------------------------
    ------ miscellaneous signals ------
    -----------------------------------
    
    signal delay_reg, next_delay_reg    : delay_reg_type := delay_reg_type_def;
    
    signal idelay_rst               : std_ulogic := '0';
    signal idelay_increment         : std_ulogic := '0';
    signal idelay_clock_enable      : std_ulogic := '0';
    
    signal idelay_master_data_out   : std_ulogic := '0';
    signal idelay_master_calibrate  : std_ulogic := '0';
    
    signal idelay_slave_data_out    : std_ulogic := '0';
    signal idelay_slave_calibrate   : std_ulogic := '0';
    signal idelay_slave_busy        : std_ulogic := '0';
    
    signal pd_counter   : unsigned(5 downto 0) := (others => '0');
    
begin
    
    BUSY                <= slave_busy;
    
    idelay_master_calibrate <= calibrate_reg.calibrate_master;
    idelay_slave_calibrate  <= calibrate_reg.calibrate_slave;
    
    IDELAY_master_inst : IDELAY
        generic map (
            DATA_RATE           => "SDR",
            IDELAY_VALUE        => 0,
            IDELAY2_VALUE       => 0,
            IDELAY_MODE         => "NORMAL",
            ODELAY_VALUE        => 0,
            IDELAY_TYPE         => "DIFF_PHASE_DETECTOR",
            COUNTER_WRAPAROUND  => "STAY_AT_LIMIT",
            DELAY_SRC           => "IDATAIN",
            SERDES_MODE         => "MASTER",
            SIM_TAPDELAY_VALUE  => SIM_TAP_DELAY
        )
        port map (
            IDATAIN     => CHANNEL_IN,
            TOUT        => open,
            DOUT        => open,
            T           => '1',
            ODATAIN     => '0',
            DATAOUT     => idelay_master_data_out,
            DATAOUT2    => open,
            IOCLK0      => PIX_CLK_X10,        -- High speed clock for calibration
            IOCLK1      => '0',
            CLK         => PIX_CLK_X2,         -- Fabric clock (GCLK) for control signals
            CAL         => idelay_master_calibrate,
            INC         => idelay_increment,
            CE          => indelay_clock_enable,
            RST         => idelay_rst,
            BUSY        => open
        );
    
    IDELAY_slave_inst : IDELAY
        generic map (
            DATA_RATE               => "SDR",
            IDELAY_VALUE            => 0,
            IDELAY2_VALUE           => 0,
            IDELAY_MODE             => "NORMAL",
            ODELAY_VALUE            => 0,
            IDELAY_TYPE             => "DIFF_PHASE_DETECTOR",
            COUNTER_WRAPAROUND      => "WRAPAROUND",
            DELAY_SRC               => "IDATAIN",
            SERDES_MODE             => "SLAVE",
            SIM_TAPDELAY_VALUE      => SIM_TAP_DELAY
        )
        port map (
            IDATAIN     => CHANNEL_IN,
            TOUT        => open,
            DOUT        => open,
            T           => '1',
            ODATA_IN    => '0',
            DATAOUT     => idelay_slave_data_out,
            DATAOUT2    => open,
            IOCLK0      => PIX_CLK_X10,
            IOCLK1      => '0',
            CLK         => PIX_CLK_X2,
            CAL         => idelay_slave_calibrate,
            INC         => idelay_increment,
            CE          => indelay_clock_enable,
            RST         => idelay_rst,
            BUSY        => idelay_slave_busy
        );
    
    ---------------------------------------
    ------ calibration state machine ------
    ---------------------------------------
    
    calibration_stm_proc : process(RST, delay_reg)
        variable r  : delay_reg_type := delay_reg_type_def;
    begin
        r           := delay_reg;
        r.counter   := delay_reg.counter + 1;
        r.enable    := delay_reg.counter(5) = '1';
        r.rst       := '0';
        
        case delay_reg.state is
            
            when INIT_FIRST_WAIT_FOR_READY =>
                if delay_reg.enable and idelay_slave_busy = '0' then
                    r.state := INIT_CALIBRATE;
                end if;
            
            when INIT_CALIBRATE =>
                r.calibrate_master  := '1';
                r.calibrate_slave   := '1';
                if idelay_slave_busy = '1' then
                    -- calibration was acknowledged
                    r.state := INIT_RESET;
                end if;
            
            when INIT_RESET =>
                r.calibrate_master  := '0';
                r.calibrate_slave   := '0';
                if idelay_slave_busy = '0' then
                    r.rst   := '1';
                    r.state := INIT_SECOND_WAIT_FOR_READY;
                end if;
            
            when INIT_SECOND_WAIT_FOR_READY =>
                if idelay_slave_busy = '0' then
                    r.state := IDLE;
                end if;
            
            when IDLE =>
                if delay_reg.counter(8) = '1' then
                    -- recalibrate once in a while
                    r.state := CALIBRATE_SLAVE;
                end if;
            
            when CALIBRATE_SLAVE =>
                if idelay_slave_busy = '0' then
                    r.calibrate_slave   := '1';
                    r.state             := WAIT_FOR_SLAVE_CALIBRATE_ACK;
                end if;
            
            when WAIT_FOR_SLAVE_CALIBRATE_ACK =>
                if idelay_slave_busy = '1' then
                    -- calibration was acknowledged
                    r.calibrate_slave   := '0';
                    r.state := WAIT_FOR_READY;
                end if;
            
            when WAIT_FOR_READY =>
                if idelay_slave_busy = '0' then
                    r.state := READY_FOR_ENABLE;
                end if;
            
        end case;
        
        if RST = '1' then
            next_delay_reg  <= delay_reg_type_def;
        end if;
        
        next_delay_reg  <= r;
    end process;
  
    calibration_stm_sync_proc : process(RST, PIX_CLK_X2)
    begin
        if RST = '1' then
            delay_reg   <= delay_reg_type_def;
        elsif rising_edge(PIX_CLK_X2) then
            delay_reg   <= next_delay_reg;
        end if;
    end process;
    
    
    -----------------------------
    ------ phase detection ------
    -----------------------------
    
    phase_detect_control_proc : process(RST, PIX_CLK_X2)
    begin
        if RST = '1' then
            pd_counter  <= (others => '0');
        elsif rising_edge(PIX_CLK_X2) then
            idelay_clock_enable <= '0';
            if delay_reg.calibrate_slave = '1' or idelay_slave_busy = '1' then
                -- Reset filter if state machine issues a cal command or unit is busy
                pd_counter  <= (others => '0');
            elsif pd_counter = (pd_counter'range => '1') and 
            end if;
        end if;
    end process;
    
end rtl;

