----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    10:43:54 07/28/2014 
-- Module Name:    TMDS_DECODER - rtl 
-- Project Name:   TMDS_DECODER
-- Tool versions:  Xilinx ISE 14.7
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
use work.help_funcs.all;

entity TMDS_DECODER is
    port (
        PIX_CLK         : in std_ulogic;
        PIX_CLK_X2      : in std_ulogic;
        PIX_CLK_X10     : in std_ulogic;
        RST             : in std_ulogic;
        
        SERDESSTROBE    : in std_ulogic;
        
        CHANNELS_IN     : in std_ulogic_vector(2 downto 0);
        
        RAW_DATA        : out std_ulogic_vector(14 downto 0) := (others => '0');
        RAW_DATA_VALID  : out std_ulogic := '0';
        
        VSYNC       : out std_ulogic := '0';
        HSYNC       : out std_ulogic := '0';
        RGB         : out std_ulogic_vector(23 downto 0) := x"000000";
        RGB_VALID   : out std_ulogic := '0';
        AUX         : out std_ulogic_vector(8 downto 0) := (others => '0');
        AUX_VALID   : out std_ulogic := '0'
    );
end TMDS_DECODER;

architecture rtl of TMDS_DECODER is
    
    type chs_data_type is
        array(0 to 2) of
        std_ulogic_vector(9 downto 0);
    
    type chs_data_x2_type is
        array(0 to 2) of
        std_ulogic_vector(4 downto 0);
    
    type chs_terc4_type is
        array(0 to 2) of
        std_ulogic_vector(3 downto 0);
    
    type chs_ctl_type is
        array(0 to 2) of
        std_ulogic_vector(1 downto 0);
    
    type chs_rgb_type is
        array(0 to 2) of
        std_ulogic_vector(7 downto 0);
    
    type state_type is (
        RESET_CHANNEL_DECODERS,
        WAIT_FOR_SYNC,
        WAIT_FOR_CONTROL,
        CONTROL,
        VIDEO_LGB,
        VIDEO_TGB,
        VIDEO,
        DATA_PACKET_LGB,
        DATA_PACKET_TGB,
        DATA_PACKET
        );
    
    type reg_type is record
        state       : state_type;
        resync      : std_ulogic;
        hsync       : std_ulogic;
        vsync       : std_ulogic;
        rgb_valid   : std_ulogic;
        aux_valid   : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAIT_FOR_SYNC,
        resync      => '1',
        hsync       => '0',
        vsync       => '0',
        rgb_valid   => '0',
        aux_valid   => '0'
        );
    
    signal chs_data         : chs_data_type := (others => (others => '0'));
    signal chs_data_x2      : chs_data_x2_type := (others => "00000");
    signal chs_data_valid   : std_ulogic_vector(2 downto 0) := "000";
    signal chs_terc4        : chs_terc4_type := (others => (others => '0'));
    signal chs_ctl          : chs_ctl_type := (others => (others => '0'));
    signal chs_rgb          : chs_rgb_type := (others => (others => '0'));
    signal is_ch_ctl        : std_ulogic_vector(2 downto 0) := "000";
    signal is_ch_terc4      : std_ulogic_vector(2 downto 0) := "000";
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    signal watchdog             : unsigned(13 downto 0) := (others => '0');
    
    subtype ctl_type is std_ulogic_vector(9 downto 0);
    subtype terc4_type is std_ulogic_vector(9 downto 0);
    subtype gb_type is std_ulogic_vector(9 downto 0);
    
    constant CTL_00 : ctl_type := "1101010100";
    constant CTL_01 : ctl_type := "0010101011";
    constant CTL_10 : ctl_type := "0101010100";
    constant CTL_11 : ctl_type := "1010101011";
    
    constant TERC4_0000 : terc4_type := "1010011100";
    constant TERC4_0001 : terc4_type := "1001100011";
    constant TERC4_0010 : terc4_type := "1011100100";
    constant TERC4_0011 : terc4_type := "1011100010";
    constant TERC4_0100 : terc4_type := "0101110001";
    constant TERC4_0101 : terc4_type := "0100011110";
    constant TERC4_0110 : terc4_type := "0110001110";
    constant TERC4_0111 : terc4_type := "0100111100";
    constant TERC4_1000 : terc4_type := "1011001100";
    constant TERC4_1001 : terc4_type := "0100111001";
    constant TERC4_1010 : terc4_type := "0110011100";
    constant TERC4_1011 : terc4_type := "1011000110";
    constant TERC4_1100 : terc4_type := "1010001110";
    constant TERC4_1101 : terc4_type := "1001110001";
    constant TERC4_1110 : terc4_type := "0101100011";
    constant TERC4_1111 : terc4_type := "1011000011";
    
    constant DATA_ISLAND_GB     : gb_type   := "0100110011";
    constant VIDEO_GB_CH0_CH2   : gb_type   := "1011001100";
    constant VIDEO_GB_CH1       : gb_type   := "0100110011";
    
    function isDataIslandGb(chs_in : chs_data_type) return boolean is
    begin
        return
            chs_in(1)=DATA_ISLAND_GB and
            chs_in(2)=DATA_ISLAND_GB;
    end function;
    
    function isVideoGb(chs_in : chs_data_type) return boolean is
    begin
        return
            chs_in(0)=VIDEO_GB_CH0_CH2 and
            chs_in(1)=VIDEO_GB_CH1 and
            chs_in(2)=VIDEO_GB_CH0_CH2;
    end function;
    
    function tmds10to8 (din : std_ulogic_vector) return std_ulogic_vector is
        variable t  : std_ulogic_vector(7 downto 0);
    begin
        t   := din(7 downto 0);
        if din(9)='1' then
            t   := not t;
        end if;
        if din(8)='1' then
            return
                ( t(7) xor t(6) ) &
                ( t(6) xor t(5) ) &
                ( t(5) xor t(4) ) &
                ( t(4) xor t(3) ) &
                ( t(3) xor t(2) ) &
                ( t(2) xor t(1) ) &
                ( t(1) xor t(0) ) &
                ( t(0) );
        else
            return
                ( t(7) xnor t(6) ) &
                ( t(6) xnor t(5) ) &
                ( t(5) xnor t(4) ) &
                ( t(4) xnor t(3) ) &
                ( t(3) xnor t(2) ) &
                ( t(2) xnor t(1) ) &
                ( t(1) xnor t(0) ) &
                ( t(0) );
        end if;
    end function;

begin
    
    RAW_DATA        <= chs_data_x2(2) & chs_data_x2(1) & chs_data_x2(0);
    RAW_DATA_VALID  <= '1' when chs_data_valid="111" else '0';
    
    HSYNC       <= cur_reg.hsync;
    VSYNC       <= cur_reg.vsync;
    RGB         <= chs_rgb(2) & chs_rgb(1) & chs_rgb(0);
    AUX         <= chs_terc4(0)(2) & chs_terc4(1) & chs_terc4(2);
    RGB_VALID   <= cur_reg.rgb_valid;
    AUX_VALID   <= cur_reg.aux_valid;
    
    TMDS_CHANNEL_DECODERs_gen : for i in 0 to 2 generate
        
        TMDS_CHANNEL_DECODER_inst : entity work.TMDS_CHANNEL_DECODER
            port map (
                PIX_CLK     => PIX_CLK,
                PIX_CLK_X2  => PIX_CLK_X2,
                PIX_CLK_X10 => PIX_CLK_X10,
                RST         => cur_reg.resync,
                
                SERDESSTROBE    => SERDESSTROBE,
                CHANNEL_IN      => CHANNELS_IN(i),
                
                DATA_OUT_X2     => chs_data_x2(i),
                DATA_OUT        => chs_data(i),
                DATA_OUT_VALID  => chs_data_valid(i)
            );
        
    end generate;
    
    chs_data_decode_gen : for i in 0 to 2 generate
        
        with chs_data(i) select
            chs_ctl(i)  <=  "00" when CTL_00,
                            "01" when CTL_01,
                            "10" when CTL_10,
                            "11" when others;
        
        with chs_data(i) select
            chs_terc4(i)    <=  "0000" when TERC4_0000,
                                "0001" when TERC4_0001,
                                "0010" when TERC4_0010,
                                "0011" when TERC4_0011,
                                "0100" when TERC4_0100,
                                "0101" when TERC4_0101,
                                "0110" when TERC4_0110,
                                "0111" when TERC4_0111,
                                "1000" when TERC4_1000,
                                "1001" when TERC4_1001,
                                "1010" when TERC4_1010,
                                "1011" when TERC4_1011,
                                "1100" when TERC4_1100,
                                "1101" when TERC4_1101,
                                "1110" when TERC4_1110,
                                "1111" when others;
        
        chs_rgb(i)  <= tmds10to8(chs_data(i));
        
        with chs_data(i) select
            is_ch_ctl(i)    <=  '1' when CTL_00, '1' when CTL_01,
                                '1' when CTL_10, '1' when CTL_11,
                                '0' when others;
        
        with chs_data(i) select
            is_ch_terc4(i)  <=  '1' when TERC4_0000, '1' when TERC4_0001,
                                '1' when TERC4_0010, '1' when TERC4_0011,
                                '1' when TERC4_0100, '1' when TERC4_0101,
                                '1' when TERC4_0110, '1' when TERC4_0111,
                                '1' when TERC4_1000, '1' when TERC4_1001,
                                '1' when TERC4_1010, '1' when TERC4_1011,
                                '1' when TERC4_1100, '1' when TERC4_1101,
                                '1' when TERC4_1110, '1' when TERC4_1111,
                                '0' when others;
        
    end generate;
    
    stm_proc : process(RST, cur_reg, chs_data, chs_data_valid, chs_ctl, chs_terc4, is_ch_ctl)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r   := cr;
        
        case cr.state is
            
            when RESET_CHANNEL_DECODERS =>
                r.resync    := '1';
                r.vsync     := '0';
                r.hsync     := '0';
                r.state     := WAIT_FOR_SYNC;
            
            when WAIT_FOR_SYNC =>
                r.resync    := '0';
                if chs_data_valid="111" then
                    -- all channels have valid signals
                    r.state := WAIT_FOR_CONTROL;
                end if;
            
            when WAIT_FOR_CONTROL =>
                if is_ch_ctl(0)='1' then
                    -- control period
                    r.state := CONTROL;
                end if;
            
            when CONTROL =>
                if isDataIslandGb(chs_data) then
                    -- data island leading guard band
                    r.state := DATA_PACKET_LGB;
                elsif isVideoGb(chs_data) then
                    -- video data leading guard band
                    r.state := VIDEO_LGB;
                elsif is_ch_ctl(0)='0' then
                    -- DVI mode, no guard bands
                    r.rgb_valid := '1';
                    r.state     := VIDEO;
                else
                    -- control period
                    r.vsync := chs_ctl(0)(1);
                    r.hsync := chs_ctl(0)(0);
                end if;
            
            when VIDEO_LGB =>
                r.state := VIDEO;
            
            when VIDEO =>
                if isVideoGb(chs_data) then
                    -- video data trailing guard band
                    r.state     := VIDEO_TGB;
                elsif is_ch_ctl(0)='1' then
                    -- DVI mode, no guard bands
                    r.rgb_valid := '0';
                    r.vsync     := chs_ctl(0)(1);
                    r.hsync     := chs_ctl(0)(0);
                    r.state     := CONTROL;
                else
                    -- video pixel
                    r.rgb_valid := '1';
                end if;
            
            when VIDEO_TGB =>
                r.state := CONTROL;
            
            when DATA_PACKET_LGB =>
                r.state := DATA_PACKET;
            
            when DATA_PACKET =>
                if isDataIslandGb(chs_data) then
                    -- data island trailing guard band
                    r.aux_valid := '0';
                    r.state     := DATA_PACKET_TGB;
                else
                    -- auxiliary data
                    r.aux_valid := '1';
                    r.vsync     := chs_terc4(0)(1);
                    r.hsync     := chs_terc4(0)(0);
                end if;
            
            when DATA_PACKET_TGB =>
                r.state := CONTROL;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        next_reg    <= r;
    end process;
    
    sync_stm_proc : process(RST, PIX_CLK)
    begin
        if RST='1' then
            cur_reg     <= reg_type_def;
            watchdog    <= (others => '0');
        elsif rising_edge(PIX_CLK) then
            cur_reg <= next_reg;
            
            -- synchronisation watchdog
            if
                cur_reg.state/=RESET_CHANNEL_DECODERS and
                cur_reg.state/=WAIT_FOR_SYNC
            then
                watchdog    <= watchdog+1;
                if chs_data_valid/="111" then
                    cur_reg <= reg_type_def;
                end if;
            end if;
            
            if watchdog(watchdog'high)='1' then
                cur_reg <= reg_type_def;
            end if;
            
            if is_ch_ctl="111" then
                watchdog    <= (others => '0');
            end if;
        end if;
    end process;
    
end;
