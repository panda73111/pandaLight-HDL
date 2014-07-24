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
        PIX_CLK_X10 : in std_ulogic;
        PIX_CLK_X2  : in std_ulogic;
        RST         : in std_ulogic;
        
        SERDESSTROBE    : in std_ulogic;
        CHANNEL_IN      : in std_ulogic;
        INCDEC          : in std_ulogic;
        INCDEC_VALID    : in std_ulogic;
        
        MASTER_DOUT : out std_ulogic := '0';
        SLAVE_DOUT  : out std_ulogic := '0'
    );
end TMDS_CHANNEL_IDELAY;

architecture rtl of TMDS_CHANNEL_IDELAY is
    
    -------------------------------------------------------
    ------ calibration state machine types & signals ------
    -------------------------------------------------------
    
    type cal_state_type is (
        INIT_FIRST_WAIT_FOR_READY,
        INIT_CALIBRATE,
        INIT_RESET,
        INIT_SECOND_WAIT_FOR_READY,
        IDLE,
        CALIBRATE_SLAVE,
        WAIT_FOR_SLAVE_CALIBRATE_ACK,
        WAIT_FOR_READY
    );
    
    type cal_reg_type is record
        state       : cal_state_type;
        counter     : unsigned(8 downto 0);
        enable      : boolean;
        master_cal  : std_ulogic;
        slave_cal   : std_ulogic;
        rst         : std_ulogic;
    end record;
    
    constant cal_reg_type_def : cal_reg_type := (
        state       => INIT_FIRST_WAIT_FOR_READY,
        counter     => to_unsigned(0, cal_reg_type.counter'length),
        enable      => false,
        master_cal  => '0',
        slave_cal   => '0',
        rst         => '0'
    );
    
    
    -----------------------------------
    ------ miscellaneous signals ------
    -----------------------------------
    
    signal cal_reg, next_cal_reg    : cal_reg_type := cal_reg_type_def;
    
    signal idelay_rst           : std_ulogic := '0';
    signal idelay_inc           : std_ulogic := '0';
    signal idelay_clk_en        : std_ulogic := '0';
    
    signal idelay_master_do     : std_ulogic := '0';
    signal idelay_master_cal    : std_ulogic := '0';
    
    signal idelay_slave_do      : std_ulogic := '0';
    signal idelay_slave_cal     : std_ulogic := '0';
    signal idelay_slave_busy    : std_ulogic := '0';
    
    signal pd_counter   : unsigned(4 downto 0) := "00000";
    signal inc_set      : boolean := false;
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    MASTER_DOUT <= idelay_master_do;
    SLAVE_DOUT  <= idelay_slave_do;
    
    idelay_master_cal   <= cal_reg.master_cal;
    idelay_slave_cal    <= cal_reg.slave_cal;
    
    idelay_rst  <= cal_reg.rst;
    
    
    -----------------------------
    --- entity instantiations ---
    -----------------------------
    
    IDELAY_master_inst : IODELAY2
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
            DATAOUT     => idelay_master_do,
            DATAOUT2    => open,
            IOCLK0      => PIX_CLK_X10,        -- High speed clock for calibration
            IOCLK1      => '0',
            CLK         => PIX_CLK_X2,         -- Fabric clock (GCLK) for control signals
            CAL         => idelay_master_cal,
            INC         => idelay_inc,
            CE          => idelay_clk_en,
            RST         => idelay_rst,
            BUSY        => open
        );
    
    IDELAY_slave_inst : IODELAY2
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
            ODATAIN     => '0',
            DATAOUT     => idelay_slave_do,
            DATAOUT2    => open,
            IOCLK0      => PIX_CLK_X10,
            IOCLK1      => '0',
            CLK         => PIX_CLK_X2,
            CAL         => idelay_slave_cal,
            INC         => idelay_inc,
            CE          => idelay_clk_en,
            RST         => idelay_rst,
            BUSY        => idelay_slave_busy
        );
    
    ---------------------------------------
    ------ calibration state machine ------
    ---------------------------------------
    
    calibration_stm_proc : process(RST, cal_reg)
        alias cr    : cal_reg_type is cal_reg;
        variable r  : cal_reg_type := cal_reg_type_def;
    begin
        r           := cr;
        r.counter   := cr.counter + 1;
        r.enable    := cr.counter(5) = '1';
        r.rst       := '0';
        
        if cr.counter(cr.counter'high)='1' then
            r.counter := (others => '0');
        end if;
        
        case cal_reg.state is
            
            when INIT_FIRST_WAIT_FOR_READY =>
                if cr.enable and idelay_slave_busy = '0' then
                    r.state := INIT_CALIBRATE;
                end if;
            
            when INIT_CALIBRATE =>
                -- needed only for simulation
                r.master_cal  := '1';
                r.slave_cal   := '1';
                if idelay_slave_busy = '1' then
                    -- calibration was acknowledged
                    r.state := INIT_RESET;
                end if;
            
            when INIT_RESET =>
                r.master_cal  := '0';
                r.slave_cal   := '0';
                if idelay_slave_busy = '0' then
                    r.rst   := '1';
                    r.state := INIT_SECOND_WAIT_FOR_READY;
                end if;
            
            when INIT_SECOND_WAIT_FOR_READY =>
                if idelay_slave_busy = '0' then
                    -- IDELAY is available
                    r.state := IDLE;
                end if;
            
            when IDLE =>
                if cr.counter(8) = '1' then
                    -- recalibrate once in a while
                    r.state := CALIBRATE_SLAVE;
                end if;
            
            when CALIBRATE_SLAVE =>
                if idelay_slave_busy = '0' then
                    r.slave_cal := '1';
                    r.state     := WAIT_FOR_SLAVE_CALIBRATE_ACK;
                end if;
            
            when WAIT_FOR_SLAVE_CALIBRATE_ACK =>
                if idelay_slave_busy = '1' then
                    -- calibration was acknowledged
                    r.slave_cal := '0';
                    r.state     := WAIT_FOR_READY;
                end if;
            
            when WAIT_FOR_READY =>
                if idelay_slave_busy = '0' then
                    -- calibration finished
                    r.state := IDLE;
                end if;
            
        end case;
        
        if RST = '1' then
            r   := cal_reg_type_def;
        end if;
        
        next_cal_reg    <= r;
    end process;
  
    calibration_stm_sync_proc : process(PIX_CLK_X2)
    begin
        if rising_edge(PIX_CLK_X2) then
            cal_reg <= next_cal_reg;
        end if;
    end process;
    
    
    -----------------------------
    ------ phase detection ------
    -----------------------------
    
    phase_detect_control_proc : process(RST, PIX_CLK_X2)
        alias cr    : cal_reg_type is cal_reg;
    begin
        if RST = '1' then
            idelay_clk_en   <= '0';
            inc_set         <= false;
            pd_counter      <= "00000";
        elsif rising_edge(PIX_CLK_X2) then
            if cr.state=WAIT_FOR_READY then
                inc_set <= false;
            end if;
            if cr.state/=IDLE or idelay_slave_busy = '1' then
                -- reset filter if state machine issues a cal command or unit is busy
                idelay_clk_en   <= '0';
                pd_counter      <= "00000";
            elsif not inc_set then
                if pd_counter="11111" then
                    -- filter has reached positive max, increment the tap count
                    idelay_inc      <= '1';
                    idelay_clk_en   <= '1';
                    pd_counter      <= "10000";
                    inc_set         <= true;
                elsif pd_counter="00000" then
                    -- filter has reached negative max, decrement the tap count
                    idelay_inc      <= '0';
                    idelay_clk_en   <= '1';
                    pd_counter      <= "10000";
                    inc_set         <= true;
                end if;
            elsif INCDEC_VALID='1' then
                -- increment filter
                idelay_clk_en   <= '0';
                if INCDEC='1' and pd_counter/="11111" then
                    pd_counter  <= pd_counter+1;
                elsif INCDEC='0' and pd_counter/="00000" then
                    -- decrement filter
                    pd_counter  <= pd_counter-1;
                end if;
            else
                idelay_clk_en   <= '0';
            end if;
        end if;
    end process;
    
end rtl;
