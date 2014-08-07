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
use work.help_funcs.all;

entity TMDS_MUX_DECODER is
    port (
        PIX_CLK         : in std_ulogic;
        PIX_CLK_X2      : in std_ulogic;
        PIX_CLK_X10     : in std_ulogic;
        RST             : in std_ulogic;
        
        CLK_LOCKED      : in std_ulogic;
        SERDESSTROBE    : in std_ulogic;
        
        RX_SELECT       : in std_ulogic;
        RX0_CHANNELS_IN : in std_ulogic_vector(2 downto 0);
        RX1_CHANNELS_IN : in std_ulogic_vector(2 downto 0);
        
        ENC_DATA        : out std_ulogic_vector(14 downto 0) := (others => '0');
        ENC_DATA_VALID  : out std_ulogic := '0';
        
        VSYNC           : out std_ulogic := '0';
        HSYNC           : out std_ulogic := '0';
        RGB             : out std_ulogic_vector(23 downto 0) := x"000000";
        AUX_DATA        : out std_ulogic_vector(8 downto 0) := (others => '0');
        AUX_DATA_VALID  : out std_ulogic := '0'
    );
end TMDS_MUX_DECODER;

architecture rtl of TMDS_MUX_DECODER is
    
    type chs_data_type is
        array(0 to 2) of
        std_ulogic_vector(9 downto 0);
    
    type chs_data_x2_type is
        array(0 to 2) of
        std_ulogic_vector(4 downto 0);
    
    type state_type is (
        WAIT_FOR_SYNC,
        WAIT_FOR_VBLANK,
        CONTROL,
        VIDEO_DATA_LGB,
        VIDEO_DATA_TGB,
        VIDEO_DATA,
        DATA_PACKET_LGB,
        DATA_PACKET_TGB,
        DATA_PACKET
        );
    
    type reg_type is record
        state           : state_type;
        hsync           : std_ulogic;
        vsync           : std_ulogic;
        rgb             : std_ulogic_vector(23 downto 0);
        rgb_valid       : std_ulogic;
        aux_data_header : std_ulogic;
        aux_data        : std_ulogic_vector(7 downto 0);
        aux_data_valid  : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => WAIT_FOR_SYNC,
        hsync           => '0',
        vsync           => '0',
        rgb             => (others => '0'),
        rgb_valid       => '0',
        aux_data_header => '0',
        aux_data        => x"00",
        aux_data_valid  => '0'
        );
    
    signal chs_data             : chs_data_type := (others => (others => '0'));
    signal rx0_chs_data         : chs_data_type := (others => (others => '0'));
    signal rx1_chs_data         : chs_data_type := (others => (others => '0'));
    
    signal chs_data_x2          : chs_data_x2_type := (others => "00000");
    signal rx0_chs_data_x2      : chs_data_x2_type := (others => "00000");
    signal rx1_chs_data_x2      : chs_data_x2_type := (others => "00000");
    
    signal chs_data_valid       : std_ulogic_vector(2 downto 0) := "000";
    signal rx0_chs_data_valid   : std_ulogic_vector(2 downto 0) := "000";
    signal rx1_chs_data_valid   : std_ulogic_vector(2 downto 0) := "000";
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal rx_switched  : std_ulogic := '0';
    signal rst_decoder  : std_ulogic := '0';
    signal rx_select_q  : std_ulogic := '0';
    
    function ctrl (din : std_ulogic_vector) return std_ulogic_vector
    is
        type ctrl_enc_table_type is array(0 to 3) of std_ulogic_vector(9 downto 0);    
        -- two to ten bit encoding lookup table
        constant ctrl_enc_table : ctrl_enc_table_type := (
            "1101010100", "0010101011", "0101010100", "1010101011"
            );
    begin
        return ctrl_enc_table(int(din));
    end function;
    
    function de_ctrl (din : std_ulogic_vector) return std_ulogic_vector is
    begin
        case din is
            when "1101010100" =>    return "00";
            when "0010101011" =>    return "01";
            when "0101010100" =>    return "10";
            when others =>          return "11";
        end case;
    end function;
    
    function de_terc4 (din : std_ulogic_vector) return std_ulogic_vector is
    begin
        case din is
            when "1010011100" =>    return "0000";
            when "1001100011" =>    return "0001";
            when "1011100100" =>    return "0010";
            when "1011100010" =>    return "0011";
            when "0101110001" =>    return "0100";
            when "0100011110" =>    return "0101";
            when "0110001110" =>    return "0110";
            when "0100111100" =>    return "0111";
            when "1011001100" =>    return "1000";
            when "0100111001" =>    return "1001";
            when "0110011100" =>    return "1010";
            when "1011000110" =>    return "1011";
            when "1010001110" =>    return "1100";
            when "1001110001" =>    return "1101";
            when "0101100011" =>    return "1110";
            when others =>          return "1111";
        end case;
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
    
    ENC_DATA        <= chs_data_x2(2) & chs_data_x2(1) & chs_data_x2(0);
    ENC_DATA_VALID  <= '1' when chs_data_valid="111" else '0';
    
    RGB             <= cur_reg.rgb;
    HSYNC           <= cur_reg.hsync and cur_reg.rgb_valid;
    VSYNC           <= cur_reg.vsync;
    AUX_DATA        <= cur_reg.aux_data & cur_reg.aux_data_header;
    AUX_DATA_VALID  <= cur_reg.aux_data_valid;
    
    rst_decoder <= RST or rx_switched;
    rx_switched <= RX_SELECT xor rx_select_q;
    
    chs_data_x2     <= rx1_chs_data_x2    when RX_SELECT='1' else rx0_chs_data_x2;
    chs_data        <= rx1_chs_data       when RX_SELECT='1' else rx0_chs_data;
    chs_data_valid  <= rx1_chs_data_valid when RX_SELECT='1' else rx0_chs_data_valid;
    
    TMDS_CHANNEL_DECODERs_gen : for i in 0 to 2 generate
        
        rx0_TMDS_CHANNEL_DECODER_inst : entity work.TMDS_CHANNEL_DECODER
            port map (
                PIX_CLK     => PIX_CLK,
                PIX_CLK_X2  => PIX_CLK_X2,
                PIX_CLK_X10 => PIX_CLK_X10,
                RST         => rst_decoder,
                
                CLK_LOCKED      => CLK_LOCKED,
                SERDESSTROBE    => SERDESSTROBE,
                CHANNEL_IN      => RX0_CHANNELS_IN(i),
                
                DATA_OUT_X2     => rx0_chs_data_x2(i),
                DATA_OUT        => rx0_chs_data(i),
                DATA_OUT_VALID  => rx0_chs_data_valid(i)
            );
        
        rx1_TMDS_CHANNEL_DECODER_inst : entity work.TMDS_CHANNEL_DECODER
            port map (
                PIX_CLK     => PIX_CLK,
                PIX_CLK_X2  => PIX_CLK_X2,
                PIX_CLK_X10 => PIX_CLK_X10,
                RST         => rst_decoder,
                
                CLK_LOCKED      => CLK_LOCKED,
                SERDESSTROBE    => SERDESSTROBE,
                CHANNEL_IN      => RX1_CHANNELS_IN(i),
                
                DATA_OUT_X2     => rx1_chs_data_x2(i),
                DATA_OUT        => rx1_chs_data(i),
                DATA_OUT_VALID  => rx1_chs_data_valid(i)
            );
        
    end generate;
    
    stm_proc : process(rst_decoder, cur_reg, chs_data, chs_data_valid)
        alias cr    : reg_type is cur_reg;
        variable r  : reg_type;
        variable t2     : std_ulogic_vector(1 downto 0);
        variable t4     : std_ulogic_vector(3 downto 0);
        variable t24    : std_ulogic_vector(23 downto 0);
    begin
        r   := cr;
        
        case cr.state is
            
            when WAIT_FOR_SYNC =>
                if chs_data_valid="111" then
                    -- all channels have valid signals
                    r.state := WAIT_FOR_VBLANK;
                end if;
            
            when WAIT_FOR_VBLANK =>
                if chs_data(0)=ctrl("00") then
                    -- control period, vsync=hsync=0
                    r.state := CONTROL;
                end if;
            
            when CONTROL =>
                t2      := de_ctrl(chs_data(0));
                r.vsync := t2(1);
                r.hsync := t2(0);
                if chs_data(1)="0100110011" and chs_data(2)="0100110011" then
                    -- data island leading guard band
                    r.state := DATA_PACKET_LGB;
                end if;
                if chs_data=("1011001100", "0100110011", "1011001100") then
                    -- video data leading guard band
                    r.state := VIDEO_DATA_LGB;
                end if;
            
            when VIDEO_DATA_LGB =>
                r.state := VIDEO_DATA;
            
            when VIDEO_DATA =>
                r.rgb_valid         := '1';
                t24(23 downto 16)   := tmds10to8(chs_data(2));
                t24(15 downto 8)    := tmds10to8(chs_data(1));
                t24(7 downto 0)     := tmds10to8(chs_data(0));
                r.rgb               := t24;
                if chs_data=("1011001100", "0100110011", "1011001100") then
                    -- video data trailing guard band
                    r.rgb_valid := '0';
                    r.state     := VIDEO_DATA_TGB;
                end if;
            
            when VIDEO_DATA_TGB =>
                r.state := CONTROL;
            
            when DATA_PACKET_LGB =>
                r.state := DATA_PACKET;
            
            when DATA_PACKET =>
                r.aux_data_valid        := '1';
                t4                      := de_terc4(chs_data(0));
                r.aux_data_header       := t4(2);
                r.aux_data(7 downto 4)  := de_terc4(chs_data(2));
                r.aux_data(3 downto 0)  := de_terc4(chs_data(1));
                if chs_data(1)="0100110011" and chs_data(2)="0100110011" then
                    -- data island trailing guard band
                    r.aux_data_valid    := '0';
                    r.state             := DATA_PACKET_TGB;
                end if;
            
            when DATA_PACKET_TGB =>
                r.state := CONTROL;
            
        end case;
        
        if rst_decoder='1' then
            r   := reg_type_def;
        end if;
        next_reg    <= r;
    end process;
    
    sync_stm_proc : process(rst_decoder, PIX_CLK)
    begin
        if rst_decoder='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(PIX_CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
    process(PIX_CLK)
    begin
        if rising_edge(PIX_CLK) then
            rx_select_q <= RX_SELECT;
        end if;
    end process;
    
end rtl;

