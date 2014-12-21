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
    
    type data_buffer_type is
        array(0 to 15) of
        std_ulogic_vector(23 downto 0);
    
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
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => CONTROL_PERIOD,
        encoding    => "000",
        cycle_count => (others => '0'),
        chs_ctl     => (others => "00"),
        chs_aux     => (others => x"0")
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal chs_aux  : chs_aux_type := (others => x"0");
    signal buf_di, buf_do   : std_ulogic_vector(23 downto 0) := x"000000";
    
begin
    
    buf_di  <= "000000000000000" & AUX when AUX_ENABLE='1' else RGB;
    
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
                RGB             => buf_do(ch_i*8+7 downto ch_i*8),
                AUX             => cur_reg.chs_aux(ch_i),
                ENCODING        => cur_reg.encoding,
                
                CHANNEL_OUT_P   => CHANNELS_OUT_P(ch_i),
                CHANNEL_OUT_N   => CHANNELS_OUT_N(ch_i)
            );
        
    end generate;
    
    DELAY_QUEUE_inst : entity work.DELAY_QUEUE
        generic map (
            CYCLES  => sel(DVI_MODE, 2, 12), -- 8 [Preamble] + 2 [guard band] + 2 [state machine]
            WIDTH   => 24
        )
        port map (
            CLK => PIX_CLK,
            RST => RST,
            
            DIN => buf_di,
            
            DOUT    => buf_do
        );
    
    stm_proc : process(cur_reg, RST, RGB_ENABLE, AUX_ENABLE, AUX, VSYNC, HSYNC, buf_do)
        alias cr is cur_reg;
        constant COUNT_BITS : natural := reg_type.cycle_count'length;
        variable r          : reg_type := reg_type_def;
    begin
        r               := cr;
        r.chs_ctl(0)    := VSYNC & HSYNC;
        r.chs_ctl(1)    := "01";
        r.chs_ctl(2)    := "00";
        r.chs_aux(0)    := "11" & VSYNC & HSYNC;
        r.chs_aux(1)    := buf_do(7 downto 4);
        r.chs_aux(2)    := buf_do(3 downto 0);
        
        r.cycle_count   := cr.cycle_count+1;
        
        case cr.state is
            
            when CONTROL_PERIOD =>
                r.encoding      := "000";
                r.cycle_count   := uns(1, COUNT_BITS);
                if DVI_MODE then
                    if RGB_ENABLE='1' then
                        r.state := VIDEO;
                    end if;
                else
                    if RGB_ENABLE='1' then
                        r.state := VIDEO_PREAMBLE;
                    end if;
                    if AUX_ENABLE='1' then
                        r.state := DATA_ISLAND_PREAMBLE;
                    end if;
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
                    r.state     := VIDEO;
                end if;
            
            when VIDEO =>
                r.encoding  := "010";
                if DVI_MODE then
                    if RGB_ENABLE='0' then
                        r.state := CONTROL_PERIOD;
                    end if;
                else
                    if RGB_ENABLE='0' then
                        if cr.cycle_count(4)='1' then
                            -- 10 cycles after RGB_ENABLE falling edge
                            -- (10 cycle pixel buffer is empty)
                            r.state     := CONTROL_PERIOD;
                        end if;
                    else
                        r.cycle_count   := uns(6, COUNT_BITS);
                    end if;
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
                    r.chs_aux(0)(3) := '1';
                    r.cycle_count   := (others => '0');
                    r.state         := DATA_ISLAND;
                end if;
            
            when DATA_ISLAND =>
                r.encoding  := "100";
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
