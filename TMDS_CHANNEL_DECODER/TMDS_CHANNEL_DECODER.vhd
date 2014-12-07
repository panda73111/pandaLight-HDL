----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    09:40:21 02/07/2014 
-- Module Name:    TMDS_CHANNEL_DECODER - rtl
-- Description:    Decoder of a single TMDS channel compliant to the
--                 HDMI 1.4 specification
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

entity TMDS_CHANNEL_DECODER is
    generic (
        CHANNEL         : natural range 0 to 2;
        SIM_TAP_DELAY   : natural range 20 to 100 := 50
    );
    port (
        PIX_CLK         : in std_ulogic;
        PIX_CLK_X2      : in std_ulogic;
        PIX_CLK_X10     : in std_ulogic;
        RST             : in std_ulogic;
        
        SERDESSTROBE    : in std_ulogic;
        CHANNEL_IN      : in std_ulogic;
        
        SYNCED          : out std_ulogic := '0';
        RAW_DATA        : out std_ulogic_vector(9 downto 0) := (others => '0');
        RAW_DATA_X2     : out std_ulogic_vector(4 downto 0) := "00000";
        RGB             : out std_ulogic_vector(7 downto 0) := (others => '0');
        RGB_VALID       : out std_ulogic := '0';
        CTL             : out std_ulogic_vector(1 downto 0) := "00";
        CTL_VALID       : out std_ulogic := '0';
        AUX_DATA        : out std_ulogic_vector(3 downto 0) := "0000";
        AUX_DATA_VALID  : out std_ulogic := '0';
        GUARDBAND_VALID : out std_ulogic := '0'
    );
end TMDS_CHANNEL_DECODER;

architecture rtl of TMDS_CHANNEL_DECODER is
    
    signal rst_iserdes          : std_ulogic := '0';
    signal bitslip              : std_ulogic := '0';
    signal idelay_incdec        : std_ulogic := '0';
    signal master_d, slave_d    : std_ulogic := '0';
    signal incdec_valid         : std_ulogic := '0';
    
    signal gearbox_data_select  : std_ulogic := '0';
    signal gearbox_x2_data      : std_ulogic_vector(4 downto 0) := (others => '0');
    signal gearbox_x2_data_q    : std_ulogic_vector(4 downto 0) := (others => '0');
    signal gearbox_x1_data      : std_ulogic_vector(9 downto 0) := (others => '0');
    signal flip_gear            : std_ulogic := '0';
    
    subtype ctl_type is std_ulogic_vector(9 downto 0);
    subtype terc4_type is std_ulogic_vector(9 downto 0);
    
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
    
    ---------------------
    --- static routes ---
    ---------------------
    
    RAW_DATA    <= gearbox_x1_data;
    RAW_DATA_X2 <= gearbox_x2_data;
    
    
    -----------------------------
    --- entity instantiations ---
    -----------------------------
    
    TMDS_CHANNEL_ISERDES_inst : entity work.TMDS_CHANNEL_ISERDES
        port map (
            PIX_CLK_X10 => PIX_CLK_X10,
            PIX_CLK_X2  => PIX_CLK_X2,
            RST         => RST,
            
            MASTER_DIN      => master_d,
            SLAVE_DIN       => slave_d,
            SERDESSTROBE    => SERDESSTROBE,
            BITSLIP         => bitslip,
            
            DOUT            => gearbox_x2_data,
            INCDEC          => idelay_incdec,
            INCDEC_VALID    => incdec_valid
        );
    
    TMDS_CHANNEL_IDELAY_inst : entity work.TMDS_CHANNEL_IDELAY
        generic map (
            SIM_TAP_DELAY   => SIM_TAP_DELAY
        )
        port map (
            PIX_CLK_X10 => PIX_CLK_X10,
            PIX_CLK_X2  => PIX_CLK_X2,
            RST         => RST,
            
            CHANNEL_IN      => CHANNEL_IN,
            INCDEC          => idelay_incdec,
            INCDEC_VALID    => incdec_valid,
            
            MASTER_DOUT => master_d,
            SLAVE_DOUT  => slave_d
        );
    
    TMDS_CHANNEL_BITSYNC_inst : entity work.TMDS_CHANNEL_BITSYNC
        port map (
            PIX_CLK_X2  => PIX_CLK_X2,
            PIX_CLK     => PIX_CLK,
            RST         => RST,
            
            DIN         => gearbox_x1_data,
            
            BITSLIP     => bitslip,
            FLIP_GEAR   => flip_gear,
            SYNCED      => SYNCED
        );
    
    
    -----------------
    --- processes ---
    -----------------
    
    decode_proc : process(PIX_CLK)
    begin
        if rising_edge(PIX_CLK) then
            CTL_VALID       <= '0';
            AUX_DATA_VALID  <= '0';
            RGB_VALID       <= '0';
            GUARDBAND_VALID <= '0';
            RGB             <= tmds10to8(gearbox_x1_data);
            
            case gearbox_x1_data is
                
                when CTL_00     => CTL_VALID        <= '1'; CTL         <= "00";
                when CTL_01     => CTL_VALID        <= '1'; CTL         <= "01";
                when CTL_10     => CTL_VALID        <= '1'; CTL         <= "10";
                when CTL_11     => CTL_VALID        <= '1'; CTL         <= "11";
                when TERC4_0000 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0000";
                when TERC4_0001 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0001";
                when TERC4_0010 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0010";
                when TERC4_0011 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0011";
                when TERC4_0100 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0100";
                when TERC4_0101 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0101";
                when TERC4_0110 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0110";
                when TERC4_0111 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "0111";
                when TERC4_1000 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1000";
                when TERC4_1001 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1001";
                when TERC4_1010 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1010";
                when TERC4_1011 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1011";
                when TERC4_1100 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1100";
                when TERC4_1101 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1101";
                when TERC4_1110 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1110";
                when TERC4_1111 => AUX_DATA_VALID   <= '1'; AUX_DATA    <= "1111";
                when "0100110011"   => if CHANNEL=1 then GUARDBAND_VALID <= '1'; end if;
                when others         => RGB_VALID    <= '1';
                
            end case;
        end if;
    end process;
    
    
    -----------------------
    --- 5 to 10 gearbox ---
    -----------------------
    
    gearbox_proc : process(PIX_CLK_X2)
    begin
        if rising_edge(PIX_CLK_X2) then
            -- concat previous five bits with the current ones
            gearbox_x2_data_q   <= gearbox_x2_data;
            if gearbox_data_select/=flip_gear then
                gearbox_x1_data <= gearbox_x2_data & gearbox_x2_data_q;
            end if;
            gearbox_data_select <= not gearbox_data_select;
        end if;
    end process;
    
end rtl;

