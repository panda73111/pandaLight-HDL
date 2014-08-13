----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    20:20:52 01/26/2014 
-- Design Name:    i2c-master
-- Module Name:    i2c-master-rtl
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--   This core implements the enhanced display data channel (1.1) in master mode
--   (100 kHz) and is compatible to DDC2B
-- Additional Comments:
--   Generic:
--     CLK_IN_PERIOD : clock period of CLK in nanoseconds
--     READ_ADDR     : 8bit read address of the DDC receiver, usually 0xA1
--     WRITE_ADDR    : 8bit write address of the DDC receiver, usually 0xA0
--     SEG_P_ADDR    : 8bit write address of the segment pointer, usually 0x30
--   Port:
--     CLK          : input clock, at least 400 kHz
--     RST          : active high reset
--     SDA          : DDC data line
--     SCL          : DDC clock line
--     START        : begin transmission using BLOCK_NUMBER
--     BLOCK_NUMBER : zero-based block number, 0 to 255
--     BUSY         : transmission is taking place, START is ignored
--     TRANSM_ERROR : when '1' (during busy='0'), the previous transmission was unsuccessful
--                    or the EDID block contained errornous/unsupported values
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity DDC_EDID_MASTER is
    generic (
        CLK_IN_PERIOD   : real;
        READ_ADDR       : std_ulogic_vector(7 downto 0) := x"A1";
        WRITE_ADDR      : std_ulogic_vector(7 downto 0) := x"A0";
        SEG_P_ADDR      : std_ulogic_vector(7 downto 0) := x"60"
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        SDA_IN  : in std_ulogic;
        SDA_OUT : out std_ulogic := '1';
        SCL_IN  : in std_ulogic;
        SCL_OUT : out std_ulogic := '1';
        
        START           : in std_ulogic;
        BLOCK_NUMBER    : in std_ulogic_vector(7 downto 0);
        
        BUSY            : out std_ulogic := '0';
        TRANSM_ERROR    : out std_ulogic := '0';
        DATA_OUT        : out std_ulogic_vector(7 downto 0) := (others => '0');
        DATA_OUT_VALID  : out std_ulogic := '0';
        BYTE_INDEX      : out std_ulogic_vector(6 downto 0) := (others => '0')
    );
end;

architecture rtl of DDC_EDID_MASTER is
    
    -- one 100 kHz cycle: scl_rise -> scl_high -> scl_fall -> scl_low
    -- cycle_ticks : how many rising edges of CLK fit in one 100 kHz period
    -- (the tick counter is basically a clock divider)
    
    -- _/~\_/~\_/~\_/~\_/~\_/~\_/~\_/~\_/~\_/~\_/~\_/~\_/~\_/~\_/  ticks of CLK
    --                                                           
    --      /~~~~~~~~~~~~~~~~~~~~~~\                        /~~~~  SCL_OUT
    -- ____/                        \______________________/     
    --      |          |           |            |                
    --   scl_rise   scl_high    scl_fall     scl_low             
    --                                                           
    --     |-----------------------------------------------|       scl cycle
    --                                                           
    --      0         1/4         1/2          3/4                 portion of cycle_ticks
    --                                                           
    -- ddc (=i2c) frequency: 100 kHz=10 000 ns => cycle_ticks=10_000 / CLK_PERIOD
    
    -- rise scl at tick counter=0 and fall at tick counter=half_cycle_ticks
    constant cycle_ticks            : positive := integer(10000.0 / CLK_IN_PERIOD);
    constant half_cycle_ticks       : positive := cycle_ticks / 2;
    -- probe sda when scl=high, in tick counter=(0..half_cycle_tick),
    -- sda change is allowed when scl=low, so in tick counter=(half_cycle_ticks..cycle_ticks-1),
    -- and we do probing exactly at 1/4 and changing at 3/4 of cycle_ticks
    constant one_qu_cycle_ticks     : positive := half_cycle_ticks / 2;
    constant three_qu_cycle_ticks   : positive := half_cycle_ticks+one_qu_cycle_ticks;
    -- (for simplicity, instability of the sda line is not taken into account!)
    
    constant FIRST_BLOCK_WORD_OFFS  : std_ulogic_vector(7 downto 0) := x"00";
    constant SECOND_BLOCK_WORD_OFFS : std_ulogic_vector(7 downto 0) := x"80";
    
    type state_type is (
        INIT,
        WAIT_FOR_START,
        WAIT_FOR_RECEIVER,
        WRITE_ACCESS_SEND_SEG_P_START,
        WRITE_ACCESS_SEND_SEG_P_ADDR,
        WRITE_ACCESS_IGNORE_SEG_P_ADDR_ACK,
        WRITE_ACCESS_SEND_SEG_P,
        WRITE_ACCESS_GET_SEG_P_ACK,
        WRITE_ACCESS_SEND_ADDR_START,
        WRITE_ACCESS_SEG_P_CLK_STRETCH,
        WRITE_ACCESS_SEND_ADDR,
        WRITE_ACCESS_GET_ADDR_ACK,
        WRITE_ACCESS_SEND_WORD_OFFS,
        WRITE_ACCESS_ADDR_CLK_STRETCH,
        WRITE_ACCESS_GET_WORD_OFFS_ACK,
        READ_ACCESS_SEND_START,
        READ_ACCESS_WORD_OFFS_CLK_STRETCH,
        READ_ACCESS_SEND_ADDR,
        READ_ACCESS_GET_ADDR_ACK,
        READ_ACCESS_GET_DATA,
        READ_ACCESS_DATA_CLK_STRETCH,
        READ_ACCESS_SEND_ACK,
        READ_ACCESS_SEND_NACK,
        SEND_STOP
    );
    
    type reg_type is record
        state           : state_type;
        sda_out         : std_ulogic;
        scl_out         : std_ulogic;
        tick_cnt        : natural range 0 to cycle_ticks-1; -- counts CLK cycles
        error           : std_ulogic;
        data_out        : std_ulogic_vector(7 downto 0);
        data_out_valid  : std_ulogic;
        clk_stretch     : boolean;              -- delaying until scl is released
        bit_index       : unsigned(2 downto 0); -- 0..7
        byte_count      : unsigned(6 downto 0); -- counts bytes of one EDID block (128 bytes)
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => INIT,
        sda_out         => '1',
        scl_out         => '1',
        tick_cnt        => 0,
        error           => '0',
        data_out        => x"00",
        data_out_valid  => '0',
        clk_stretch     => false,
        bit_index       => uns(7, 3),
        byte_count      => "0000000"
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal scl_rise, scl_fall   : boolean := false;
    signal scl_high, scl_low    : boolean := false;
    signal segment_pointer      : std_ulogic_vector(7 downto 0) := x"00";
    
begin
    
    SDA_OUT <= cur_reg.sda_out;
    SCL_OUT <= cur_reg.scl_out;
    
    BUSY            <= '0' when cur_reg.state=WAIT_FOR_START else '1';
    TRANSM_ERROR    <= cur_reg.error;
    
    DATA_OUT        <= cur_reg.data_out;
    DATA_OUT_VALID  <= cur_reg.data_out_valid;
    BYTE_INDEX      <= stdulv(cur_reg.byte_count-1);
    
    scl_rise    <= cur_reg.tick_cnt=0;
    scl_high    <= cur_reg.tick_cnt=one_qu_cycle_ticks;
    scl_fall    <= cur_reg.tick_cnt=half_cycle_ticks;
    scl_low     <= cur_reg.tick_cnt=three_qu_cycle_ticks;
    
    -- divide by two, every segment contains two blocks
    segment_pointer <= '0' & BLOCK_NUMBER(7 downto 1);
    
    finite_state_machine : process(RST, cur_reg, START, SDA_IN, SCL_IN,
        BLOCK_NUMBER, scl_rise, scl_high, scl_fall, scl_low, segment_pointer)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cr;
        
        r.data_out_valid    := '0';
        
        -- pause while the receiver is holding scl low, else go on
        if cr.state=WAIT_FOR_RECEIVER or cr.tick_cnt=cycle_ticks-1 then
            r.tick_cnt  := 0;
        elsif not cr.clk_stretch then
            r.tick_cnt  := cr.tick_cnt+1;
        end if;
        
        case cr.state is
            
            when INIT =>
                r.bit_index     := uns(7, 3);
                r.byte_count    := "0000000";
                r.state         := WAIT_FOR_START;
            
            when WAIT_FOR_START =>
                if START='1' then
                    r.error := '0';
                    r.state := WAIT_FOR_RECEIVER;
                end if;
            
            when WAIT_FOR_RECEIVER =>
                if SCL_IN='1' then
                    r.state := WRITE_ACCESS_SEND_SEG_P_START;
                end if;
            
            when WRITE_ACCESS_SEND_SEG_P_START =>
                if scl_high then
                    r.sda_out   := '0';
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.state     := WRITE_ACCESS_SEND_SEG_P_ADDR;
                end if;
              
            when WRITE_ACCESS_SEND_SEG_P_ADDR =>
                if scl_low then
                    r.sda_out   := SEG_P_ADDR(int(cr.bit_index));
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.bit_index := cr.bit_index-1;
                    if cr.bit_index=0 then
                        -- sent 8 bits and clock pulses
                        r.state := WRITE_ACCESS_IGNORE_SEG_P_ADDR_ACK;
                    end if;
                end if;
            
            when WRITE_ACCESS_IGNORE_SEG_P_ADDR_ACK =>
                if scl_low then
                    r.sda_out   := '1'; -- release sda
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.state := WRITE_ACCESS_SEND_SEG_P;
                end if;
            
            when WRITE_ACCESS_SEND_SEG_P =>
                if scl_low then
                    r.sda_out   := segment_pointer(int(cr.bit_index));
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.bit_index := cr.bit_index-1;
                    if cr.bit_index=0 then
                        -- sent 8 bits and clock pulses
                        r.state := WRITE_ACCESS_GET_SEG_P_ACK;
                    end if;
                end if;
            
            when WRITE_ACCESS_GET_SEG_P_ACK =>
                if scl_low then
                    r.sda_out   := '1'; -- release sda
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if SDA_IN='1' and BLOCK_NUMBER /= x"00" then
                        -- If the receiver is not E-EDID compliant, this NACK can be
                        -- ignored if the requested block number is 0, since the first
                        -- block will always be available. If the BLOCK_NUMBER is greater
                        -- than 0 however, that block should have been available but
                        -- is not, and this NACK is an error.
                        r.error := '1';
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    if cr.error='1' then
                        r.state := SEND_STOP;
                    else
                        r.state := WRITE_ACCESS_SEND_ADDR_START;
                    end if;
                end if;
            
            when WRITE_ACCESS_SEND_ADDR_START =>
                if scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if SCL_IN='0' then
                        -- scl is being held low by receiver, wait,
                        -- THEN send the start condition
                        r.clk_stretch   := true;
                        r.state         := WRITE_ACCESS_SEG_P_CLK_STRETCH;
                    else
                        r.sda_out   := '0';
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.state     := WRITE_ACCESS_SEND_ADDR;
                end if;
            
            when WRITE_ACCESS_SEG_P_CLK_STRETCH =>
                if SCL_IN='1' then
                    -- scl was released
                    r.clk_stretch   := false;
                    r.state         := WRITE_ACCESS_SEND_ADDR_START;
                end if;
            
            when WRITE_ACCESS_SEND_ADDR =>
                if scl_low then
                    r.sda_out   := WRITE_ADDR(int(cr.bit_index));
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.bit_index := cr.bit_index-1;
                    if cr.bit_index=0 then
                        -- sent 8 bits and clock pulses
                        r.state := WRITE_ACCESS_GET_ADDR_ACK;
                    end if;
                end if;
            
            when WRITE_ACCESS_GET_ADDR_ACK =>
                if scl_low then
                    r.sda_out   := '1'; -- release sda
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if SDA_IN='1' then
                        -- not acknowledged
                        r.error := '1';
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    if cr.error='1' then
                        r.state := SEND_STOP;
                    else
                        r.state := WRITE_ACCESS_SEND_WORD_OFFS;
                    end if;
                end if;
            
            when WRITE_ACCESS_SEND_WORD_OFFS =>
                if scl_low then
                    if BLOCK_NUMBER(0)='1' then
                        -- second block of segment BLOCK_NUMBER/2
                        r.sda_out   := SECOND_BLOCK_WORD_OFFS(int(cr.bit_index));
                    else
                        r.sda_out   := FIRST_BLOCK_WORD_OFFS(int(cr.bit_index));
                    end if;
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if cr.bit_index=7 and SCL_IN='0' then
                        -- scl is being held low by receiver, wait
                        r.clk_stretch   := true;
                        r.state         := WRITE_ACCESS_ADDR_CLK_STRETCH;
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.bit_index := cr.bit_index-1;
                    if cr.bit_index=0 then
                        -- sent 8 bits and clock pulses
                        r.state := WRITE_ACCESS_GET_WORD_OFFS_ACK;
                    end if;
                end if;
            
            when WRITE_ACCESS_ADDR_CLK_STRETCH =>
                if SCL_IN='1' then
                    -- scl was released
                    r.clk_stretch   := false;
                    r.state         := WRITE_ACCESS_SEND_WORD_OFFS;
                end if;
            
            when WRITE_ACCESS_GET_WORD_OFFS_ACK =>
                if scl_low then
                    r.sda_out   := '1'; -- release sda
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if SDA_IN='1' then
                        -- not acknowledged
                        r.error := '1';
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    if cr.error='1' then
                        r.state := SEND_STOP;
                    else
                        r.state := READ_ACCESS_SEND_START;
                    end if;
                end if;
            
            when READ_ACCESS_SEND_START =>
                if scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if SCL_IN='0' then
                        -- scl is being held low by receiver, wait,
                        -- THEN send the start condition
                        r.clk_stretch   := true;
                        r.state         := READ_ACCESS_WORD_OFFS_CLK_STRETCH;
                    else
                        r.sda_out   := '0';
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.state     := READ_ACCESS_SEND_ADDR;
                end if;
            
            when READ_ACCESS_WORD_OFFS_CLK_STRETCH =>
                if SCL_IN='1' then
                    -- scl was released
                    r.clk_stretch   := false; -- continue counting ticks
                end if;
                if scl_high then
                    r.sda_out   := '0';
                    r.state     := READ_ACCESS_SEND_START;
                end if;
            
            when READ_ACCESS_SEND_ADDR  =>
                if scl_low then
                    r.sda_out   := READ_ADDR(int(cr.bit_index));
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.bit_index := cr.bit_index-1;
                    if cr.bit_index=0 then
                        -- sent 8 bits and clock pulses
                        r.state := READ_ACCESS_GET_ADDR_ACK;
                    end if;
                end if;
            
            when READ_ACCESS_GET_ADDR_ACK =>
                if scl_low then
                    r.sda_out   := '1'; -- release sda
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if SDA_IN='1' then
                        -- not acknowledged
                        r.error := '1';
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    if cr.error='1' then
                        r.state := SEND_STOP;
                    else
                        r.state := READ_ACCESS_GET_DATA;
                    end if;
                end if;
            
            when READ_ACCESS_GET_DATA =>
                if scl_low then
                    r.sda_out   := '1'; -- release sda
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_high then
                    if cr.bit_index=7 and SCL_IN='0' then
                        -- scl is being held low by receiver, wait,
                        -- THEN take over the transmitted bit
                        r.clk_stretch   := true;
                        r.state         := READ_ACCESS_DATA_CLK_STRETCH;
                    else
                        r.data_out(int(cr.bit_index))   := SDA_IN;
                    end if;
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.bit_index := cr.bit_index-1;
                    if cr.bit_index=0 then
                        -- read 8 bits
                        r.byte_count        := cr.byte_count+1;
                        r.data_out_valid    := '1';
                        if cr.byte_count=127 then
                            -- completed one EDID block
                            r.state := READ_ACCESS_SEND_NACK;
                        else
                            r.state := READ_ACCESS_SEND_ACK;
                        end if;
                    end if;
                end if;
            
            when READ_ACCESS_DATA_CLK_STRETCH =>
                if SCL_IN='1' then
                    -- scl was released
                    r.clk_stretch   := false; -- continue counting ticks
                end if;
                if scl_high then
                    r.data_out(int(cr.bit_index))   := SDA_IN;
                    r.state                         := READ_ACCESS_GET_DATA;
                end if;
            
            when READ_ACCESS_SEND_ACK =>
                if scl_low then
                    r.sda_out   := '0';
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_fall then
                    r.scl_out   := '0';
                    -- receive the next byte
                    r.state     := READ_ACCESS_GET_DATA;
                end if;
            
            when READ_ACCESS_SEND_NACK =>
                if scl_low then
                    r.sda_out   := '1'; -- release sda
                elsif scl_rise then
                    r.scl_out   := '1';
                elsif scl_fall then
                    r.scl_out   := '0';
                    r.state     := SEND_STOP;
                end if;
            
            when SEND_STOP =>
                if scl_low then
                    r.sda_out   := '0';
                elsif scl_rise then
                    r.scl_out   := '1'; -- release scl
                elsif scl_high then
                    r.sda_out   := '1'; -- stop condition
                elsif scl_fall then
                    r.state := INIT;
                end if;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;

    sync_stm : process(RST, CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
end;

