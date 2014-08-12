----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    13:17:27 08/12/2014 
-- Module Name:    E_DDC_SLAVE - rtl 
-- Project Name:   E_DDC_SLAVE
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--   This core implements the enhanced display data channel (1.1) in slave mode
--   (100 kHz) and is compatible to DDC2B
-- Additional Comments:
--   Generic:
--     CLK_IN_PERIOD : clock period of CLK in nanoseconds
--     READ_ADDR     : 8bit read address of the DDC receiver, usually 0xA1
--     WRITE_ADDR    : 8bit write address of the DDC receiver, usually 0xA0
--     SEG_P_ADDR    : 8bit write address of the segment pointer, usually 0x60
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity E_DDC_SLAVE is
    generic (
        CLK_IN_PERIOD   : real;
        READ_ADDR       : std_ulogic_vector(7 downto 0) := x"A1";
        WRITE_ADDR      : std_ulogic_vector(7 downto 0) := x"A0";
        SEG_P_ADDR      : std_ulogic_vector(7 downto 0) := x"60"
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        DATA_IN_ADDR    : in std_ulogic_vector(15 downto 0);
        DATA_IN_WR_EN   : in std_ulogic;
        DATA_IN         : in std_ulogic_vector(7 downto 0);
        
        SDA_IN  : in std_ulogic;
        SDA_OUT : out std_ulogic := '1';
        SCL_IN  : in std_ulogic;
        SCL_OUT : out std_ulogic := '1';
        
        BUSY            : out std_ulogic := '0';
        TRANSM_ERROR    : out std_ulogic := '0'
    );
end E_DDC_SLAVE;

architecture rtl of E_DDC_SLAVE is
    
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
    -- ddc (=i2c) frequency: 100 kHz = 10 000 ns => cycle_ticks = 10_000 / CLK_PERIOD
    
    -- rise scl at tick counter=0 and fall at tick counter=half_cycle_ticks
    constant cycle_ticks            : positive := integer(10000.0 / CLK_IN_PERIOD);
    constant half_cycle_ticks       : positive := cycle_ticks / 2;
    -- probe sda when scl=high, in tick counter=(0..half_cycle_tick),
    -- sda change is allowed when scl=low, so in tick counter=(half_cycle_ticks..cycle_ticks-1),
    -- and we do probing exactly at 1/4 and changing at 3/4 of cycle_ticks
    constant one_qu_cycle_ticks     : positive := half_cycle_ticks / 2;
    constant three_qu_cycle_ticks   : positive := half_cycle_ticks + one_qu_cycle_ticks;
    -- (for simplicity, instability of the sda line is not taken into account!)
    
    constant FIRST_BLOCK_WORD_OFFS  : std_ulogic_vector(7 downto 0) := x"00";
    constant SECOND_BLOCK_WORD_OFFS : std_ulogic_vector(7 downto 0) := x"80";
    
    type state_type is (
        INIT,
        WAIT_FOR_START
    );
    
    type reg_type is record
        state           : state_type;
        sda_out         : std_ulogic;
        scl_out         : std_ulogic;
        tick_cnt        : natural range 0 to cycle_ticks-1; -- counts CLK cycles
        seg_p           : unsigned(7 downto 0);
        error           : std_ulogic;
        data_out        : std_ulogic_vector(7 downto 0);
        data_out_valid  : std_ulogic;
        bit_index       : unsigned(2 downto 0); -- 0..7
        byte_index      : unsigned(6 downto 0); -- counts bytes of one EDID block (128 bytes)
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => INIT,
        sda_out         => '1',
        scl_out         => '1',
        tick_cnt        => 0,
        seg_p           => uns(0, reg_type.seg_p'length),
        error           => '0',
        data_out        => (others => '0'),
        data_out_valid  => '0',
        bit_index       => uns(7, reg_type.bit_index'length),
        byte_index      => uns(127, reg_type.byte_index'length)
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal scl_rise, scl_fall   : boolean := false;
    signal scl_high, scl_low    : boolean := false;
    signal segment_pointer      : std_ulogic_vector(7 downto 0) := x"00";
    
    signal ram_rd_addr  : std_ulogic_vector(15 downto 0) := x"0000";
    signal ram_dout     : std_ulogic_vector(7 downto 0) := x"00";
    
begin
    
    SDA_OUT <= cur_reg.sda_out;
    SCL_OUT <= cur_reg.scl_out;
    
    BUSY            <= '0' when cur_reg.state = WAIT_FOR_START else '1';
    TRANSM_ERROR    <= cur_reg.error;
    
    DATA_OUT        <= cur_reg.data_out;
    DATA_OUT_VALID  <= cur_reg.data_out_valid;
    BYTE_INDEX      <= stdulv(cur_reg.byte_index);
    
    scl_rise    <= cur_reg.tick_cnt = 0;
    scl_high    <= cur_reg.tick_cnt = one_qu_cycle_ticks;
    scl_fall    <= cur_reg.tick_cnt = half_cycle_ticks;
    scl_low     <= cur_reg.tick_cnt = three_qu_cycle_ticks;
    
    DUAL_PORT_RAM_inst : entity work.DUAL_PORT_RAM
        generic map (
            WIDTH   => 8,
            DEPTH   => 256*128
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            RD_ADDR => ram_rd_addr,
            WR_EN   => DATA_IN_WR_EN,
            WR_ADDR => DATA_IN_ADDR,
            DIN     => DATA_IN,
            
            DOUT    => ram_dout
        );
    
    finite_state_machine : process(RST, cur_reg, START, SDA_IN, SCL_IN,
        BLOCK_NUMBER, scl_rise, scl_high, scl_fall, scl_low, segment_pointer)
        variable r  : reg_type := reg_type_def;
    begin
        r   := cur_reg;
        
        r.data_out_valid    := '0';
        
        case cur_reg.state is
            
            when INIT =>
                r.bit_index     := uns(7, reg_type.bit_index'length);
                r.byte_index    := uns(127, reg_type.byte_index'length);
                r.state         := WAIT_FOR_START;
            
            when WAIT_FOR_START =>
                if START='1' then
                    r.error := '0';
                    r.state := WAIT_FOR_SENDER;
                end if;
            
            when WAIT_FOR_SENDER =>
                if SCL_IN='1' then
                    r.state := SEG_P_START;
                end if;
            
            when SEG_P_START =>
                
            
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
