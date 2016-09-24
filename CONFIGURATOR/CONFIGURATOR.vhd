----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    15:32:18 12/10/2014 
-- Module Name:    CONFIGURATOR - rtl 
-- Project Name:   pandaLight-Tests
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
-- 
-- Additional Comments:
--  Dimension Bits = 11. Used for all LED and frame dimensions
--  
--  Absolute horizontal value = [fraction] * [frame  width]
--  Absolute   vertical value = [fraction] * [frame height]
--  
--  Horizontal values, multiplied by frame width:
--    - horizontal LED width
--    - horizontal LED step
--    - horizontal LED offset
--    - vertical LED width
--    - vertical LED pad
--  
--  Vertical values, multiplied by frame height:
--    - horizontal LED height
--    - horizontal LED pad
--    - vertical LED height
--    - vertical LED step
--    - vertical LED offset
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_MISC.ALL;
use work.help_funcs.all;

entity CONFIGURATOR is
    generic (
        DIM_BITS    : natural range 9 to 16 := 11
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CALCULATE           : in std_ulogic;
        CONFIGURE_LEDEX     : in std_ulogic;
        CONFIGURE_LEDCOR    : in std_ulogic;
        
        FRAME_WIDTH     : in std_ulogic_vector(DIM_BITS-1 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(DIM_BITS-1 downto 0);
        
        SETTINGS_ADDR   : in std_ulogic_vector(9 downto 0);
        SETTINGS_WR_EN  : in std_ulogic;
        SETTINGS_DIN    : in std_ulogic_vector(7 downto 0);
        SETTINGS_DOUT   : out std_ulogic_vector(7 downto 0) := x"00";
        
        CFG_SEL_LEDEX   : out std_ulogic := '0';
        CFG_SEL_LEDCOR  : out std_ulogic := '0';
        
        CFG_ADDR    : out std_ulogic_vector(9 downto 0) := (others => '0');
        CFG_WR_EN   : out std_ulogic := '0';
        CFG_DATA    : out std_ulogic_vector(7 downto 0) := (others => '0');
        
        BUSY    : out std_ulogic := '0'
    );
end CONFIGURATOR;

architecture rtl of CONFIGURATOR is
    
    constant BUF_I_HOR_LED_CNT          : std_ulogic_vector(9 downto 0) := "0000000000";
    constant BUF_I_HOR_LED_WIDTH_H      : std_ulogic_vector(9 downto 0) := "0000000001";
    constant BUF_I_HOR_LED_WIDTH_L      : std_ulogic_vector(9 downto 0) := "0000000010";
    constant BUF_I_HOR_LED_HEIGHT_H     : std_ulogic_vector(9 downto 0) := "0000000011";
    constant BUF_I_HOR_LED_HEIGHT_L     : std_ulogic_vector(9 downto 0) := "0000000100";
    constant BUF_I_HOR_LED_STEP_H       : std_ulogic_vector(9 downto 0) := "0000000101";
    constant BUF_I_HOR_LED_STEP_L       : std_ulogic_vector(9 downto 0) := "0000000110";
    constant BUF_I_HOR_LED_PAD_H        : std_ulogic_vector(9 downto 0) := "0000000111";
    constant BUF_I_HOR_LED_PAD_L        : std_ulogic_vector(9 downto 0) := "0000001000";
    constant BUF_I_HOR_LED_OFFS_H       : std_ulogic_vector(9 downto 0) := "0000001001";
    constant BUF_I_HOR_LED_OFFS_L       : std_ulogic_vector(9 downto 0) := "0000001010";
    constant BUF_I_VER_LED_CNT          : std_ulogic_vector(9 downto 0) := "0000001011";
    constant BUF_I_VER_LED_WIDTH_H      : std_ulogic_vector(9 downto 0) := "0000001100";
    constant BUF_I_VER_LED_WIDTH_L      : std_ulogic_vector(9 downto 0) := "0000001101";
    constant BUF_I_VER_LED_HEIGHT_H     : std_ulogic_vector(9 downto 0) := "0000001110";
    constant BUF_I_VER_LED_HEIGHT_L     : std_ulogic_vector(9 downto 0) := "0000001111";
    constant BUF_I_VER_LED_STEP_H       : std_ulogic_vector(9 downto 0) := "0000010000";
    constant BUF_I_VER_LED_STEP_L       : std_ulogic_vector(9 downto 0) := "0000010001";
    constant BUF_I_VER_LED_PAD_H        : std_ulogic_vector(9 downto 0) := "0000010010";
    constant BUF_I_VER_LED_PAD_L        : std_ulogic_vector(9 downto 0) := "0000010011";
    constant BUF_I_VER_LED_OFFS_H       : std_ulogic_vector(9 downto 0) := "0000010100";
    constant BUF_I_VER_LED_OFFS_L       : std_ulogic_vector(9 downto 0) := "0000010101";
    constant BUF_I_START_LED_NUM        : std_ulogic_vector(9 downto 0) := "0001000000";
    constant BUF_I_LED_LOOKUP_TABLES    : std_ulogic_vector(9 downto 0) := "0100000000";
    
    type state_type is (
        WAITING_FOR_START,
        CALCULATING_ABSOLUTE_HOR_VALUES_H,
        CALCULATING_ABSOLUTE_HOR_VALUES_L,
        CALCULATING_WAIT_FOR_ABSOLUTE_HOR_VALUE,
        CALCULATING_GETTING_ABSOLUTE_HOR_VALUE_L,
        CALCULATING_ABSOLUTE_VER_VALUES_H,
        CALCULATING_ABSOLUTE_VER_VALUES_L,
        CALCULATING_WAIT_FOR_ABSOLUTE_VER_VALUE,
        CALCULATING_GETTING_ABSOLUTE_VER_VALUE_L,
        ADDING_HOR_LED_COUNT,
        ADDING_VER_LED_COUNT,
        CONFIGURING_LEDEX,
        CONFIGURING_LEDCOR
    );
    
    type reg_type is record
        state                   : state_type;
        cfg_sel_ledex           : std_ulogic;
        cfg_sel_ledcor          : std_ulogic;
        cfg_addr                : std_ulogic_vector(9 downto 0);
        cfg_wr_en               : std_ulogic;
        cfg_data                : std_ulogic_vector(7 downto 0);
        multiplier_start        : std_ulogic;
        multiplier_multiplicand : std_ulogic_vector(DIM_BITS-1 downto 0);
        multiplier_multiplier   : std_ulogic_vector(DIM_BITS-1 downto 0);
        led_count               : std_ulogic_vector(7 downto 0);
        buf_rd_p                : std_ulogic_vector(9 downto 0);
        buf_wr_p                : std_ulogic_vector(9 downto 0);
        buf_di                  : std_ulogic_vector(7 downto 0);
        buf_wr_en               : std_ulogic;
        scaled_buf_wr_en        : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state                   => WAITING_FOR_START,
        cfg_sel_ledex           => '0',
        cfg_sel_ledcor          => '0',
        cfg_addr                => (others => '1'),
        cfg_wr_en               => '0',
        cfg_data                => x"00",
        multiplier_start        => '0',
        multiplier_multiplicand => (others => '0'),
        multiplier_multiplier   => (others => '0'),
        led_count               => x"00",
        buf_rd_p                => (others => '0'),
        buf_wr_p                => (others => '0'),
        buf_di                  => x"00",
        buf_wr_en               => '0',
        scaled_buf_wr_en        => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal multiplier_valid         : std_ulogic := '0';
    signal multiplier_result        : std_ulogic_vector(2*DIM_BITS-1 downto 0) := (others => '0');
    signal div_multiplier_result    : std_ulogic_vector(DIM_BITS-1 downto 0) := (others => '0');
    
    type settings_buf_type is
        array(0 to 1023) of
        std_ulogic_vector(7 downto 0);
    
    signal settings_buf : settings_buf_type := (others => x"00");
    
    type scaled_settings_buf_type is
        array(0 to 31) of
        std_ulogic_vector(7 downto 0);
    
    signal scaled_settings_buf  : scaled_settings_buf_type := (others => x"00");
    
    signal buf_do           : std_ulogic_vector(7 downto 0) := x"00";
    signal scaled_buf_do    : std_ulogic_vector(7 downto 0) := x"00";
    
    signal is_led_dimension_settings    : std_ulogic := '0';
    
begin
    
    SETTINGS_DOUT   <= buf_do;
    CFG_SEL_LEDEX   <= cur_reg.cfg_sel_ledex;
    CFG_SEL_LEDCOR  <= cur_reg.cfg_sel_ledcor;
    CFG_ADDR        <= cur_reg.cfg_addr;
    CFG_WR_EN       <= cur_reg.cfg_wr_en;
    CFG_DATA        <= cur_reg.cfg_data;
    BUSY            <= '1' when cur_reg.state/=WAITING_FOR_START else '0';
    
    div_multiplier_result       <= multiplier_result(2*DIM_BITS-1 downto DIM_BITS) + multiplier_result(DIM_BITS-1); -- round
    is_led_dimension_settings   <= not or_reduce(SETTINGS_ADDR(9 downto 5)); -- within address range 0..32
    
    ITERATIVE_MULTIPLIER_inst : entity work.ITERATIVE_MULTIPLIER
        generic map (
            WIDTH   => DIM_BITS
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            START   => cur_reg.multiplier_start,
            
            MULTIPLICAND    => cur_reg.multiplier_multiplicand,
            MULTIPLIER      => cur_reg.multiplier_multiplier,
            
            VALID   => multiplier_valid,
            RESULT  => multiplier_result
        );
    
    -- ensure block RAM usage
    settings_buf_proc : process(CLK)
        alias rd_p  is next_reg.buf_rd_p;
        alias wr_p  is next_reg.buf_wr_p;
        alias di    is next_reg.buf_di;
        alias do    is buf_do;
        alias wr_en is next_reg.buf_wr_en;
    begin
        if rising_edge(CLK) then
            -- write first mode
            do  <= settings_buf(int(rd_p));
            if wr_en='1' then
                settings_buf(int(wr_p)) <= di(7 downto 0);
            end if;
            if wr_en='1' and rd_p=wr_p then
                do  <= di(7 downto 0);
            end if;
        end if;
    end process;
    
    scaled_settings_buf_proc : process(CLK)
        alias rd_p  is next_reg.buf_rd_p;
        alias wr_p  is next_reg.buf_wr_p;
        alias di    is next_reg.buf_di;
        alias do    is scaled_buf_do;
        alias wr_en is next_reg.scaled_buf_wr_en;
    begin
        if rising_edge(CLK) then
            -- write first mode
            do  <= scaled_settings_buf(int(rd_p(4 downto 0)));
            if wr_en='1' then
                scaled_settings_buf(int(wr_p(4 downto 0)))  <= di;
            end if;
            if wr_en='1' and rd_p=wr_p then
                do  <= di;
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, CALCULATE, CONFIGURE_LEDEX, CONFIGURE_LEDCOR,
        SETTINGS_ADDR, SETTINGS_WR_EN, SETTINGS_DIN, FRAME_WIDTH, FRAME_HEIGHT,
        multiplier_valid, div_multiplier_result, buf_do, scaled_buf_do, is_led_dimension_settings)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r                   := cr;
        r.cfg_sel_ledex     := '0';
        r.cfg_sel_ledcor    := '0';
        r.cfg_wr_en         := '0';
        r.multiplier_start  := '0';
        r.buf_wr_en         := '0';
        r.scaled_buf_wr_en  := '0';
        
        case cr.state is
            
            when WAITING_FOR_START =>
                r.cfg_addr  := (others => '1');
                r.buf_wr_p  := (others => '0');
                r.buf_rd_p  := SETTINGS_ADDR;
                if SETTINGS_WR_EN='1' then
                    r.buf_wr_en         := '1';
                    r.scaled_buf_wr_en  := is_led_dimension_settings;
                    r.buf_wr_p          := SETTINGS_ADDR;
                    r.buf_di            := SETTINGS_DIN;
                end if;
                if CALCULATE='1' then
                    r.buf_rd_p  := BUF_I_HOR_LED_WIDTH_H;
                    r.state     := CALCULATING_ABSOLUTE_HOR_VALUES_H;
                end if;
                if CONFIGURE_LEDEX='1' then
                    r.buf_rd_p  := BUF_I_HOR_LED_CNT;
                    r.state     := CONFIGURING_LEDEX;
                end if;
                if CONFIGURE_LEDCOR='1' then
                    r.buf_rd_p  := BUF_I_START_LED_NUM-1;
                    r.state     := CONFIGURING_LEDCOR;
                end if;
            
            when CALCULATING_ABSOLUTE_HOR_VALUES_H =>
                r.multiplier_multiplicand                       := FRAME_WIDTH;
                r.multiplier_multiplier(DIM_BITS-1 downto 8)    := buf_do(DIM_BITS-9 downto 0);
                r.buf_rd_p                                      := cr.buf_rd_p+1;
                r.buf_wr_p                                      := cr.buf_rd_p;
                r.state                                         := CALCULATING_ABSOLUTE_HOR_VALUES_L;
            
            when CALCULATING_ABSOLUTE_HOR_VALUES_L =>
                r.multiplier_multiplier(7 downto 0) := buf_do;
                case cr.buf_rd_p is
                    when BUF_I_HOR_LED_WIDTH_L  =>  r.buf_rd_p  := BUF_I_HOR_LED_STEP_H;
                    when BUF_I_HOR_LED_STEP_L   =>  r.buf_rd_p  := BUF_I_HOR_LED_OFFS_H;
                    when BUF_I_HOR_LED_OFFS_L   =>  r.buf_rd_p  := BUF_I_VER_LED_WIDTH_H;
                    when others                 =>  r.buf_rd_p  := BUF_I_VER_LED_PAD_H;
                end case;
                r.multiplier_start  := '1';
                r.state             := CALCULATING_WAIT_FOR_ABSOLUTE_HOR_VALUE;
            
            when CALCULATING_WAIT_FOR_ABSOLUTE_HOR_VALUE =>
                r.scaled_buf_wr_en              := '1';
                r.buf_di                        := x"00";
                r.buf_di(DIM_BITS-9 downto 0)   := div_multiplier_result(DIM_BITS-1 downto 8);
                if multiplier_valid='1' then
                    r.state := CALCULATING_GETTING_ABSOLUTE_HOR_VALUE_L;
                end if;
            
            when CALCULATING_GETTING_ABSOLUTE_HOR_VALUE_L =>
                r.scaled_buf_wr_en  := '1';
                r.buf_di            := div_multiplier_result(7 downto 0);
                r.buf_wr_p          := cr.buf_wr_p+1;
                r.state := CALCULATING_ABSOLUTE_HOR_VALUES_H;
                if cr.buf_wr_p=BUF_I_VER_LED_PAD_H then
                    r.buf_rd_p  := BUF_I_VER_LED_HEIGHT_H;
                    r.state     := CALCULATING_ABSOLUTE_VER_VALUES_H;
                end if;
            
            when CALCULATING_ABSOLUTE_VER_VALUES_H =>
                r.multiplier_multiplicand                       := FRAME_HEIGHT;
                r.multiplier_multiplier(DIM_BITS-1 downto 8)    := buf_do(DIM_BITS-9 downto 0);
                r.buf_rd_p                                      := cr.buf_rd_p+1;
                r.buf_wr_p                                      := cr.buf_rd_p;
                r.state                                         := CALCULATING_ABSOLUTE_VER_VALUES_L;
            
            when CALCULATING_ABSOLUTE_VER_VALUES_L =>
                r.multiplier_multiplier(7 downto 0) := buf_do;
                case cr.buf_rd_p is
                    when BUF_I_VER_LED_HEIGHT_L =>  r.buf_rd_p  := BUF_I_VER_LED_STEP_H;
                    when BUF_I_VER_LED_STEP_L   =>  r.buf_rd_p  := BUF_I_VER_LED_OFFS_H;
                    when BUF_I_VER_LED_OFFS_L   =>  r.buf_rd_p  := BUF_I_HOR_LED_HEIGHT_H;
                    when others                 =>  r.buf_rd_p  := BUF_I_HOR_LED_PAD_H;
                end case;
                r.multiplier_start  := '1';
                r.state             := CALCULATING_WAIT_FOR_ABSOLUTE_VER_VALUE;
            
            when CALCULATING_WAIT_FOR_ABSOLUTE_VER_VALUE =>
                r.scaled_buf_wr_en              := '1';
                r.buf_di                        := x"00";
                r.buf_di(DIM_BITS-9 downto 0)   := div_multiplier_result(DIM_BITS-1 downto 8);
                if multiplier_valid='1' then
                    r.state := CALCULATING_GETTING_ABSOLUTE_VER_VALUE_L;
                end if;
            
            when CALCULATING_GETTING_ABSOLUTE_VER_VALUE_L =>
                r.scaled_buf_wr_en  := '1';
                r.buf_di            := div_multiplier_result(7 downto 0);
                r.buf_wr_p          := cr.buf_wr_p+1;
                r.state := CALCULATING_ABSOLUTE_VER_VALUES_H;
                if cr.buf_wr_p=BUF_I_HOR_LED_PAD_H then
                    r.buf_rd_p  := BUF_I_HOR_LED_CNT;
                    r.state     := ADDING_HOR_LED_COUNT;
                end if;
            
            when ADDING_HOR_LED_COUNT =>
                r.led_count := buf_do;
                r.buf_rd_p  := BUF_I_VER_LED_CNT;
                r.state     := ADDING_VER_LED_COUNT;
            
            when ADDING_VER_LED_COUNT =>
                -- 2 * ver. count = left + right
                -- 2 * hor. count = top + bottom
                -- LED count = 2 * (hor. count + ver. count)
                r.led_count := cr.led_count+buf_do;
                r.led_count := r.led_count(6 downto 0) & "0"; -- * 2
                r.state     := WAITING_FOR_START;
            
            when CONFIGURING_LEDEX =>
                r.cfg_sel_ledex := '1';
                r.cfg_wr_en     := '1';
                r.cfg_addr      := cr.cfg_addr+1;
                r.cfg_data      := scaled_buf_do;
                r.buf_rd_p      := cr.buf_rd_p+1;
                case r.cfg_addr(4 downto 0) is
                    when "10110"    =>  r.cfg_data  := x"00";   r.cfg_data(DIM_BITS-9 downto 0) := FRAME_WIDTH(DIM_BITS-1 downto 8);
                    when "10111"    =>                          r.cfg_data                      := FRAME_WIDTH(7 downto 0);
                    when "11000"    =>  r.cfg_data  := x"00";   r.cfg_data(DIM_BITS-9 downto 0) := FRAME_HEIGHT(DIM_BITS-1 downto 8);
                    when "11001"    =>                          r.cfg_data                      := FRAME_HEIGHT(7 downto 0);
                                        r.state     := WAITING_FOR_START;
                    when others     =>  null;
                end case;
            
            when CONFIGURING_LEDCOR =>
                r.cfg_sel_ledcor    := '1';
                r.cfg_wr_en         := '1';
                r.cfg_addr          := cr.cfg_addr+1;
                r.cfg_data          := buf_do;
                r.buf_rd_p          := cr.buf_rd_p+1;
                case r.cfg_addr is
                    when "0000000000"   =>  r.cfg_data  := cr.led_count;
                    when "0000000011"   =>  r.buf_rd_p  := BUF_I_LED_LOOKUP_TABLES;
                    when "0000000100"   =>  r.cfg_addr  := BUF_I_LED_LOOKUP_TABLES;
                    when "1111111111"   =>  r.state     := WAITING_FOR_START;
                    when others         =>  null;
                end case;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;
    
    stm_sync_proc : process(RST, CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg     <= next_reg;
        end if;
    end process;
    
end rtl;
