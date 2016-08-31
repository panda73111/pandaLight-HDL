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
use work.help_funcs.all;

entity CONFIGURATOR is
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CALCULATE           : in std_ulogic;
        CONFIGURE_LEDEX     : in std_ulogic;
        CONFIGURE_LEDCOR    : in std_ulogic;
        
        FRAME_WIDTH     : in std_ulogic_vector(15 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(15 downto 0);
        
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
    
    constant BUF_I_HOR_LED_CNT              : std_ulogic_vector(9 downto 0) := "0000000000";
    constant BUF_I_HOR_LED_WIDTH_HIGH_BYTE  : std_ulogic_vector(9 downto 0) := "0000000001";
    constant BUF_I_HOR_LED_WIDTH_LOW_BYTE   : std_ulogic_vector(9 downto 0) := "0000000010";
    constant BUF_I_HOR_LED_HEIGHT_HIGH_BYTE : std_ulogic_vector(9 downto 0) := "0000000011";
    constant BUF_I_HOR_LED_HEIGHT_LOW_BYTE  : std_ulogic_vector(9 downto 0) := "0000000100";
    constant BUF_I_HOR_LED_STEP_HIGH_BYTE   : std_ulogic_vector(9 downto 0) := "0000000101";
    constant BUF_I_HOR_LED_STEP_LOW_BYTE    : std_ulogic_vector(9 downto 0) := "0000000110";
    constant BUF_I_HOR_LED_PAD_HIGH_BYTE    : std_ulogic_vector(9 downto 0) := "0000000111";
    constant BUF_I_HOR_LED_PAD_LOW_BYTE     : std_ulogic_vector(9 downto 0) := "0000001000";
    constant BUF_I_HOR_LED_OFFS_HIGH_BYTE   : std_ulogic_vector(9 downto 0) := "0000001001";
    constant BUF_I_HOR_LED_OFFS_LOW_BYTE    : std_ulogic_vector(9 downto 0) := "0000001010";
    constant BUF_I_VER_LED_CNT              : std_ulogic_vector(9 downto 0) := "0000001011";
    constant BUF_I_VER_LED_WIDTH_HIGH_BYTE  : std_ulogic_vector(9 downto 0) := "0000001100";
    constant BUF_I_VER_LED_WIDTH_LOW_BYTE   : std_ulogic_vector(9 downto 0) := "0000001101";
    constant BUF_I_VER_LED_HEIGHT_HIGH_BYTE : std_ulogic_vector(9 downto 0) := "0000001110";
    constant BUF_I_VER_LED_HEIGHT_LOW_BYTE  : std_ulogic_vector(9 downto 0) := "0000001111";
    constant BUF_I_VER_LED_STEP_HIGH_BYTE   : std_ulogic_vector(9 downto 0) := "0000010000";
    constant BUF_I_VER_LED_STEP_LOW_BYTE    : std_ulogic_vector(9 downto 0) := "0000010001";
    constant BUF_I_VER_LED_PAD_HIGH_BYTE    : std_ulogic_vector(9 downto 0) := "0000010010";
    constant BUF_I_VER_LED_PAD_LOW_BYTE     : std_ulogic_vector(9 downto 0) := "0000010011";
    constant BUF_I_VER_LED_OFFS_HIGH_BYTE   : std_ulogic_vector(9 downto 0) := "0000010100";
    constant BUF_I_VER_LED_OFFS_LOW_BYTE    : std_ulogic_vector(9 downto 0) := "0000010101";
    constant BUF_I_START_LED_NUM            : std_ulogic_vector(9 downto 0) := "0000010110";
    constant BUF_I_FRAME_DELAY              : std_ulogic_vector(9 downto 0) := "0000010111";
    constant BUF_I_RGB_MODE                 : std_ulogic_vector(9 downto 0) := "0000011000";
    constant BUF_I_LED_CONTROL_MODE         : std_ulogic_vector(9 downto 0) := "0000011001";
    constant BUF_I_LED_LOOKUP_TABLES        : std_ulogic_vector(9 downto 0) := "0100000000";
    
    type state_type is (
        WAITING_FOR_START,
        CALCULATING_ABSOLUTE_HOR_VALUES_HIGH_BYTE,
        CALCULATING_ABSOLUTE_HOR_VALUES_LOW_BYTE,
        CALCULATING_WAIT_FOR_ABSOLUTE_HOR_VALUE,
        CALCULATING_GETTING_ABSOLUTE_HOR_VALUE_LOW_BYTE,
        CALCULATING_ABSOLUTE_VER_VALUES_HIGH_BYTE,
        CALCULATING_ABSOLUTE_VER_VALUES_LOW_BYTE,
        CALCULATING_WAIT_FOR_ABSOLUTE_VER_VALUE,
        CALCULATING_GETTING_ABSOLUTE_VER_VALUE_LOW_BYTE,
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
        multiplier_multiplicand : std_ulogic_vector(15 downto 0);
        multiplier_multiplier   : std_ulogic_vector(15 downto 0);
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
        multiplier_multiplicand => x"0000",
        multiplier_multiplier   => x"0000",
        led_count               => x"00",
        buf_rd_p                => (others => '0'),
        buf_wr_p                => (others => '0'),
        buf_di                  => x"00",
        buf_wr_en               => '0',
        scaled_buf_wr_en        => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal multiplier_valid     : std_ulogic := '0';
    signal multiplier_result    : std_ulogic_vector(31 downto 0) := x"0000_0000";
    
    type settings_buf_type is
        array(0 to 1023) of
        std_ulogic_vector(7 downto 0);
    
    signal settings_buf : settings_buf_type := (others => x"00");
    
    type scaled_settings_buf_type is
        array(0 to 15) of
        std_ulogic_vector(7 downto 0);
    
    signal scaled_settings_buf  : scaled_settings_buf_type := (others => x"00");
    
    signal buf_do           : std_ulogic_vector(7 downto 0) := x"00";
    signal scaled_buf_do    : std_ulogic_vector(7 downto 0) := x"00";
    
begin
    
    SETTINGS_DOUT   <= buf_do;
    CFG_SEL_LEDEX   <= cur_reg.cfg_sel_ledex;
    CFG_SEL_LEDCOR  <= cur_reg.cfg_sel_ledcor;
    CFG_ADDR        <= cur_reg.cfg_addr;
    CFG_WR_EN       <= cur_reg.cfg_wr_en;
    CFG_DATA        <= cur_reg.cfg_data;
    BUSY            <= '1' when cur_reg.state/=WAITING_FOR_START else '0';
    
    ITERATIVE_MULTIPLIER_inst : entity work.ITERATIVE_MULTIPLIER
        generic map (
            WIDTH   => 16
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
            do  <= scaled_settings_buf(int(rd_p(3 downto 0)));
            if wr_en='1' then
                scaled_settings_buf(int(wr_p(3 downto 0)))  <= di;
            end if;
            if wr_en='1' and rd_p=wr_p then
                do  <= di;
            end if;
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, CALCULATE, CONFIGURE_LEDEX, CONFIGURE_LEDCOR,
        SETTINGS_ADDR, SETTINGS_WR_EN, SETTINGS_DIN, FRAME_WIDTH, FRAME_HEIGHT,
        multiplier_valid, multiplier_result, buf_do, scaled_buf_do)
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
                    r.buf_wr_en := '1';
                    r.buf_wr_p  := SETTINGS_ADDR;
                    r.buf_di    := SETTINGS_DIN;
                end if;
                if CALCULATE='1' then
                    r.buf_rd_p  := BUF_I_HOR_LED_WIDTH_HIGH_BYTE;
                    r.state     := CALCULATING_ABSOLUTE_HOR_VALUES_HIGH_BYTE;
                end if;
                if CONFIGURE_LEDEX='1' then
                    r.buf_rd_p  := BUF_I_HOR_LED_CNT;
                    r.state     := CONFIGURING_LEDEX;
                end if;
                if CONFIGURE_LEDCOR='1' then
                    r.state := CONFIGURING_LEDCOR;
                end if;
            
            when CALCULATING_ABSOLUTE_HOR_VALUES_HIGH_BYTE =>
                r.multiplier_multiplicand           := FRAME_WIDTH;
                r.multiplier_multiplier(7 downto 0) := buf_do;
                r.buf_rd_p                          := cr.buf_rd_p+1;
                r.state                             := CALCULATING_ABSOLUTE_HOR_VALUES_LOW_BYTE;
            
            when CALCULATING_ABSOLUTE_HOR_VALUES_LOW_BYTE =>
                r.multiplier_multiplier(15 downto 8)    := buf_do;
                r.buf_wr_p                              := cr.buf_rd_p;
                case cr.buf_rd_p is
                    when BUF_I_HOR_LED_WIDTH_LOW_BYTE   =>  r.buf_rd_p  := BUF_I_HOR_LED_STEP_HIGH_BYTE;
                    when BUF_I_HOR_LED_STEP_LOW_BYTE    =>  r.buf_rd_p  := BUF_I_HOR_LED_OFFS_HIGH_BYTE;
                    when BUF_I_HOR_LED_OFFS_LOW_BYTE    =>  r.buf_rd_p  := BUF_I_VER_LED_WIDTH_HIGH_BYTE;
                    when others                         =>  r.buf_rd_p  := BUF_I_VER_LED_PAD_HIGH_BYTE;
                end case;
                r.multiplier_start  := '1';
                r.state             := CALCULATING_WAIT_FOR_ABSOLUTE_HOR_VALUE;
            
            when CALCULATING_WAIT_FOR_ABSOLUTE_HOR_VALUE =>
                r.scaled_buf_wr_en  := '1';
                r.buf_di            := multiplier_result(31 downto 24);
                if multiplier_valid='1' then
                    r.state := CALCULATING_GETTING_ABSOLUTE_HOR_VALUE_LOW_BYTE;
                end if;
            
            when CALCULATING_GETTING_ABSOLUTE_HOR_VALUE_LOW_BYTE =>
                r.scaled_buf_wr_en  := '1';
                r.buf_di            := multiplier_result(23 downto 16);
                r.buf_wr_p          := cr.buf_rd_p;
                r.state := CALCULATING_ABSOLUTE_HOR_VALUES_HIGH_BYTE;
                if cr.buf_wr_p=BUF_I_VER_LED_PAD_LOW_BYTE then
                    r.buf_rd_p  := BUF_I_VER_LED_HEIGHT_HIGH_BYTE;
                    r.state     := CALCULATING_ABSOLUTE_VER_VALUES_HIGH_BYTE;
                end if;
            
            when CALCULATING_ABSOLUTE_VER_VALUES_HIGH_BYTE =>
                r.multiplier_multiplicand           := FRAME_HEIGHT;
                r.multiplier_multiplier(7 downto 0) := buf_do;
                r.buf_rd_p                          := cr.buf_rd_p+1;
                r.state                             := CALCULATING_ABSOLUTE_VER_VALUES_LOW_BYTE;
            
            when CALCULATING_ABSOLUTE_VER_VALUES_LOW_BYTE =>
                r.multiplier_multiplier(15 downto 8)    := buf_do;
                r.buf_wr_p                              := cr.buf_rd_p;
                case cr.buf_rd_p is
                    when BUF_I_VER_LED_HEIGHT_LOW_BYTE  =>  r.buf_rd_p  := BUF_I_VER_LED_STEP_HIGH_BYTE;
                    when BUF_I_VER_LED_STEP_LOW_BYTE    =>  r.buf_rd_p  := BUF_I_VER_LED_OFFS_HIGH_BYTE;
                    when BUF_I_VER_LED_OFFS_LOW_BYTE    =>  r.buf_rd_p  := BUF_I_HOR_LED_HEIGHT_HIGH_BYTE;
                    when others                         =>  r.buf_rd_p  := BUF_I_HOR_LED_PAD_HIGH_BYTE;
                end case;
                r.multiplier_start  := '1';
                r.state             := CALCULATING_WAIT_FOR_ABSOLUTE_VER_VALUE;
            
            when CALCULATING_WAIT_FOR_ABSOLUTE_VER_VALUE =>
                r.scaled_buf_wr_en  := '1';
                r.buf_di            := multiplier_result(31 downto 24);
                if multiplier_valid='1' then
                    r.state := CALCULATING_GETTING_ABSOLUTE_VER_VALUE_LOW_BYTE;
                end if;
            
            when CALCULATING_GETTING_ABSOLUTE_VER_VALUE_LOW_BYTE =>
                r.scaled_buf_wr_en  := '1';
                r.buf_di            := multiplier_result(23 downto 16);
                r.buf_wr_p          := cr.buf_rd_p;
                r.state := CALCULATING_ABSOLUTE_VER_VALUES_HIGH_BYTE;
                if cr.buf_wr_p=BUF_I_HOR_LED_PAD_LOW_BYTE then
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
                case r.cfg_addr is
                    when "0000000000"   =>  r.cfg_data  := buf_do;          r.buf_rd_p  := BUF_I_HOR_LED_WIDTH_HIGH_BYTE;  -- hor. LED count
                    when "0000000001"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_WIDTH_LOW_BYTE;   -- hor. LED width
                    when "0000000010"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_HEIGHT_HIGH_BYTE;
                    when "0000000011"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_HEIGHT_LOW_BYTE;  -- hor. LED height
                    when "0000000100"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_STEP_HIGH_BYTE;
                    when "0000000101"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_STEP_LOW_BYTE;    -- hor. LED step
                    when "0000000110"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_PAD_HIGH_BYTE;
                    when "0000000111"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_PAD_LOW_BYTE;     -- hor. LED padding
                    when "0000001000"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_OFFS_HIGH_BYTE;
                    when "0000001001"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_HOR_LED_OFFS_LOW_BYTE;    -- hor. LED offset
                    when "0000001010"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_CNT;
                    when "0000001011"   =>  r.cfg_data  := buf_do;          r.buf_rd_p  := BUF_I_VER_LED_WIDTH_HIGH_BYTE;  -- ver. LED count
                    when "0000001100"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_WIDTH_LOW_BYTE;   -- ver. LED width
                    when "0000001101"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_HEIGHT_HIGH_BYTE;
                    when "0000001110"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_HEIGHT_LOW_BYTE;  -- ver. LED height
                    when "0000001111"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_STEP_HIGH_BYTE;
                    when "0000010000"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_STEP_LOW_BYTE;    -- ver. LED step
                    when "0000010001"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_PAD_HIGH_BYTE;
                    when "0000010010"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_PAD_LOW_BYTE;     -- ver. LED padding
                    when "0000010011"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_OFFS_HIGH_BYTE;
                    when "0000010100"   =>  r.cfg_data  := scaled_buf_do;   r.buf_rd_p  := BUF_I_VER_LED_OFFS_LOW_BYTE;    -- ver. LED offset
                    when "0000010101"   =>  r.cfg_data  := scaled_buf_do;
                    when "0000010110"   =>  r.cfg_data  := FRAME_WIDTH(15 downto 8);
                    when "0000010111"   =>  r.cfg_data  := FRAME_WIDTH(7 downto 0);
                    when "0000011000"   =>  r.cfg_data  := FRAME_HEIGHT(15 downto 8);
                    when others         =>  r.cfg_data  := FRAME_HEIGHT(7 downto 0);
                                            r.state     := WAITING_FOR_START;
                end case;
            
            when CONFIGURING_LEDCOR =>
                r.cfg_sel_ledcor    := '1';
                r.cfg_wr_en         := '1';
                r.cfg_addr          := cr.cfg_addr+1;
                r.cfg_data          := (others => '0');
                case r.cfg_addr is
                    when "0000000000"   =>  r.cfg_data(7 downto 0)  := cr.led_count;    r.buf_rd_p  := BUF_I_START_LED_NUM;
                    when "0000000001"   =>  r.cfg_data              := buf_do;          r.buf_rd_p  := BUF_I_FRAME_DELAY;
                    when "0000000010"   =>  r.cfg_data              := buf_do;          r.buf_rd_p  := BUF_I_RGB_MODE;
                    when "0000000011"   =>  r.cfg_data              := buf_do;          r.buf_rd_p  := BUF_I_LED_LOOKUP_TABLES;
                    when "0000000100"   =>  r.cfg_data              := buf_do;          r.buf_rd_p  := cr.buf_rd_p+1;           r.cfg_addr  := BUF_I_LED_LOOKUP_TABLES;
                    when "1111111111"   =>  r.cfg_data              := buf_do;
                                            r.state                 := WAITING_FOR_START;
                    when others         =>  r.cfg_data              := buf_do;          r.buf_rd_p  := cr.buf_rd_p+1; -- lookup table entry
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
