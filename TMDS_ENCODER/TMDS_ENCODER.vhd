----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    18:49:46 12/20/2014 
-- Module Name:    TMDS_ENCODER - rtl 
-- Project Name:   TMDS_ENCODER
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--  
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity TMDS_ENCODER is
    generic (
        DVI_MODE    : boolean := false
    );
    port (
        PIX_CLK     : in std_ulogic;
        PIX_CLK_X2  : in std_ulogic;
        PIX_CLK_X10 : in std_ulogic;
        RST         : in std_ulogic;
        
        SERDESSTROBE    : in std_ulogic;
        CLK_LOCKED      : in std_ulogic;
        
        HSYNC       : in std_ulogic;
        VSYNC       : in std_ulogic;
        RGB         : in std_ulogic_vector(23 downto 0);
        RGB_ENABLE  : in std_ulogic;
        AUX         : in std_ulogic_vector(8 downto 0);
        AUX_ENABLE  : in std_ulogic;
        
        RGB_ACK : out std_ulogic := '0';
        AUX_ACK : out std_ulogic := '0';
        
        CHANNELS_OUT_P  : out std_ulogic_vector(2 downto 0) := "111";
        CHANNELS_OUT_N  : out std_ulogic_vector(2 downto 0) := "111"
    );
end TMDS_ENCODER;

architecture rtl of TMDS_ENCODER is
    
    type chs_ctl_type is
        array(0 to 2) of
        std_ulogic_vector(1 downto 0);
    
    type chs_aux_type is
        array(0 to 2) of
        std_ulogic_vector(3 downto 0);
    
    type state_type is (
        CONTROL_PERIOD,
        VIDEO_PREAMBLE,
        VIDEO_LEADING_GUARD_BAND,
        VIDEO,
        DATA_ISLAND_PREAMBLE,
        DATA_ISLAND_LEADING_GUARD_BAND,
        DATA_ISLAND,
        DATA_ISLAND_TRAILING_GUARD_BAND
    );
    
    type reg_type is record
        state       : state_type;
        encoding    : std_ulogic_vector(2 downto 0);
        cycle_count : unsigned(5 downto 0);
        chs_ctl     : chs_ctl_type;
        chs_aux     : chs_aux_type;
        rgb_ack     : std_ulogic;
        aux_ack     : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => CONTROL_PERIOD,
        encoding    => "000",
        cycle_count => (others => '0'),
        chs_ctl     => (others => "00"),
        chs_aux     => (others => x"0"),
        rgb_ack     => '0',
        aux_ack     => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal chs_aux  : chs_aux_type := (others => x"0");
    
begin
    
    RGB_ACK <= cur_reg.rgb_ack;
    AUX_ACK <= cur_reg.aux_ack;
    
    TMDS_CHANNEL_ENCODERs_generate : for ch_i in 0 to 2 generate
        
        TMDS_CHANNEL_ENCODER_inst : entity work.TMDS_CHANNEL_ENCODER
            generic map (
                CHANNEL_NUM => ch_i
            )
            port map (
                PIX_CLK     => PIX_CLK,
                PIX_CLK_X2  => PIX_CLK_X2,
                PIX_CLK_X10 => PIX_CLK_X10,
                RST         => RST,
                
                CLK_LOCKED      => CLK_LOCKED,
                SERDESSTROBE    => SERDESSTROBE,
                HSYNC           => HSYNC,
                VSYNC           => VSYNC,
                CTL             => cur_reg.chs_ctl(ch_i),
                RGB             => RGB(ch_i*8+7 downto ch_i*8),
                AUX             => cur_reg.chs_aux(ch_i),
                ENCODING        => cur_reg.encoding,
                
                CHANNEL_OUT_P   => CHANNELS_OUT_P(ch_i),
                CHANNEL_OUT_N   => CHANNELS_OUT_N(ch_i)
            );
        
    end generate;
    
    stm_proc : process(cur_reg, RST, RGB_ENABLE, AUX_ENABLE, AUX, VSYNC, HSYNC)
        alias cr is cur_reg;
        constant COUNT_BITS : natural := reg_type.cycle_count'length;
        variable r          : reg_type := reg_type_def;
    begin
        r               := cr;
        r.rgb_ack       := '0';
        r.aux_ack       := '0';
        r.chs_ctl(0)    := VSYNC & HSYNC;
        r.chs_ctl(1)    := "01";
        r.chs_ctl(2)    := "00";
        r.chs_aux(0)    := "11" & VSYNC & HSYNC;
        r.chs_aux(1)    := AUX(7 downto 4);
        r.chs_aux(2)    := AUX(3 downto 0);
        
        r.cycle_count   := cr.cycle_count+1;
        
        case cr.state is
            
            when CONTROL_PERIOD =>
                r.encoding      := "000";
                r.cycle_count   := uns(1, COUNT_BITS);
                if RGB_ENABLE='1' then
                    r.state := VIDEO_PREAMBLE;
                end if;
                if AUX_ENABLE='1' then
                    r.state := DATA_ISLAND_PREAMBLE;
                end if;
            
            when VIDEO_PREAMBLE =>
                r.encoding  := "000";
                if cr.cycle_count(3)='1' then
                    -- after 8 cycles
                    r.state := VIDEO_LEADING_GUARD_BAND;
                end if;
            
            when VIDEO_LEADING_GUARD_BAND =>
                r.encoding  := "001";
                if cr.cycle_count(1)='1' then
                    -- after 2 cycles
                    r.rgb_ack   := '1';
                    r.state     := VIDEO;
                end if;
            
            when VIDEO =>
                r.encoding  := "010";
                r.rgb_ack   := '1';
                if RGB_ENABLE='0' then
                    r.rgb_ack   := '0';
                    r.state     := CONTROL_PERIOD;
                end if;
            
            when DATA_ISLAND_PREAMBLE =>
                r.encoding      := "000";
                r.chs_ctl(2)(0) := '1';
                if cr.cycle_count(3)='1' then
                    -- after 8 cycles
                    r.state := DATA_ISLAND_LEADING_GUARD_BAND;
                end if;
            
            when DATA_ISLAND_LEADING_GUARD_BAND =>
                r.encoding  := "011";
                if cr.cycle_count(1)='1' then
                    -- after 2 cycles
                    r.aux_ack       := '1';
                    r.chs_aux(0)(3) := '1';
                    r.cycle_count   := (others => '0');
                    r.state         := DATA_ISLAND;
                end if;
            
            when DATA_ISLAND =>
                r.encoding  := "100";
                r.aux_ack   := '1';
                if cr.cycle_count(4)='1' then
                    -- after 32 cycles
                    r.cycle_count   := uns(1, COUNT_BITS);
                    if AUX_ENABLE='0' then
                        r.state := DATA_ISLAND_TRAILING_GUARD_BAND;
                    end if;
                end if;
            
            when DATA_ISLAND_TRAILING_GUARD_BAND =>
                r.encoding  := "011";
                if cr.cycle_count(1)='1' then
                    -- after 2 cycles
                    r.state := CONTROL_PERIOD;
                end if;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;
    
    stm_sync_proc : process(PIX_CLK, RST)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(PIX_CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;
