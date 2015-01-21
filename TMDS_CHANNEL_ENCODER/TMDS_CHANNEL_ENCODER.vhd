----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    18:41:53 02/07/2014
-- Module Name:    TMDS_CHANNEL_ENCODER - rtl
-- Description:    Encoder of a single TMDS channel compliant to the
--                 HDMI 1.4 specification
--
-- Additional Comments: 
--  ports:
--   ENCODING : 0 = Control,
--              1 = Video Leading Guard Band,
--              2 = Video Data,
--              3 = Data Island Guard Band,
--              4 = TERC4 encoded data
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity TMDS_CHANNEL_ENCODER is
    generic (
        CHANNEL_NUM : natural range 0 to 2
    );
    port (
        PIX_CLK         : in std_ulogic;
        PIX_CLK_X2      : in std_ulogic;
        PIX_CLK_X10     : in std_ulogic;
        RST             : in std_ulogic;
        
        CLK_LOCKED      : in std_ulogic;
        SERDESSTROBE    : in std_ulogic;
        HSYNC           : in std_ulogic;
        VSYNC           : in std_ulogic;
        CTL             : in std_ulogic_vector(1 downto 0);
        RGB             : in std_ulogic_vector(7 downto 0);
        AUX             : in std_ulogic_vector(3 downto 0);
        ENCODING        : in std_ulogic_vector(2 downto 0);
        
        CHANNEL_OUT_P   : out std_ulogic := '1';
        CHANNEL_OUT_N   : out std_ulogic := '1'
    );
end TMDS_CHANNEL_ENCODER;

architecture rtl of TMDS_CHANNEL_ENCODER is
    
    signal oserdes_shift_d_m_in     : std_ulogic := '0';
    signal oserdes_shift_d_m_out    : std_ulogic := '0';
    signal oserdes_channel_out      : std_ulogic := '0';
    
    signal gearbox_data_select  : std_ulogic := '0';
    signal gearbox_x2_data      : std_ulogic_vector(4 downto 0) := (others => '0');
    signal gearbox_x1_data      : std_ulogic_vector(9 downto 0) := (others => '0');
    signal rgb_uns              : unsigned(7 downto 0) := (others => '0');
    signal rgb_xor              : unsigned(8 downto 0) := (others => '0');
    signal rgb_xnor             : unsigned(8 downto 0) := (others => '0');
    signal rgb_ones_cnt         : unsigned(3 downto 0) := (others => '0');
    signal rgb_enc              : unsigned(8 downto 0) := (others => '0');
    signal rgb_enc_inv          : unsigned(8 downto 0) := (others => '0');
    signal rgb_enc_disp         : signed(3 downto 0) := (others => '0'); 
    signal total_disp           : signed(3 downto 0) := (others => '0');
    
    function terc4 (din : unsigned(3 downto 0)) return unsigned is
    begin
        case din is
            when "0000" =>  return "1010011100";
            when "0001" =>  return "1001100011";
            when "0010" =>  return "1011100100";
            when "0011" =>  return "1011100010";
            when "0100" =>  return "0101110001";
            when "0101" =>  return "0100011110";
            when "0110" =>  return "0110001110";
            when "0111" =>  return "0100111100";
            when "1000" =>  return "1011001100";
            when "1001" =>  return "0100111001";
            when "1010" =>  return "0110011100";
            when "1011" =>  return "1011000110";
            when "1100" =>  return "1010001110";
            when "1101" =>  return "1001110001";
            when "1110" =>  return "0101100011";
            when others =>  return "1011000011";
        end case;
    end function;
    
begin
    
    rgb_uns <= uns(RGB);
    
    rgb_xor(0)  <= RGB(0);
    rgb_xor(1)  <= RGB(1) xor RGB(0);
    rgb_xor(2)  <= RGB(2) xor rgb_xor(1);
    rgb_xor(3)  <= RGB(3) xor rgb_xor(2);
    rgb_xor(4)  <= RGB(4) xor rgb_xor(3);
    rgb_xor(5)  <= RGB(5) xor rgb_xor(4);
    rgb_xor(6)  <= RGB(6) xor rgb_xor(5);
    rgb_xor(7)  <= RGB(7) xor rgb_xor(6);
    rgb_xor(8)  <= '1';
    
    rgb_xnor(0) <= RGB(0);
    rgb_xnor(1) <= RGB(1) xnor RGB(0);
    rgb_xnor(2) <= RGB(2) xnor rgb_xnor(1);
    rgb_xnor(3) <= RGB(3) xnor rgb_xnor(2);
    rgb_xnor(4) <= RGB(4) xnor rgb_xnor(3);
    rgb_xnor(5) <= RGB(5) xnor rgb_xnor(4);
    rgb_xnor(6) <= RGB(6) xnor rgb_xnor(5);
    rgb_xnor(7) <= RGB(7) xnor rgb_xnor(6);
    rgb_xnor(8) <= '0';
    
    rgb_enc_inv <= not rgb_enc;
    
    rgb_ones_cnt    <=  uns(0, 4) +
                        RGB(0) + RGB(1) +
                        RGB(2) + RGB(3) +
                        RGB(4) + RGB(5) +
                        RGB(6) + RGB(7);
    
    -- disperity between ones and zeros of rgb_enc, 0 = equal number of '1's and '0's
    rgb_enc_disp    <=  sig(-4, 4) +
                        rgb_enc(0) + rgb_enc(1) +
                        rgb_enc(2) + rgb_enc(3) +
                        rgb_enc(4) + rgb_enc(5) +
                        rgb_enc(6) + rgb_enc(7);
    
    OBUFDS_inst : OBUFDS
        port map (
            I   => oserdes_channel_out,
            O   => CHANNEL_OUT_P,
            OB  => CHANNEL_OUT_N
        );

    OSERDES2_master_inst : OSERDES2
        generic map (
            DATA_RATE_OQ    => "SDR",
            DATA_RATE_OT    => "SDR",
            DATA_WIDTH      => 5,
            OUTPUT_MODE     => "SINGLE_ENDED",
            SERDES_MODE     => "MASTER"
        )
        port map (
            CLK0        => PIX_CLK_X10,
            CLK1        => '0',
            OCE         => CLK_LOCKED,
            CLKDIV      => PIX_CLK_X2,
            RST         => RST,
            IOCE        => SERDESSTROBE,
            TRAIN       => '0',
            D1          => gearbox_x2_data(4),
            D2          => '0',
            D3          => '0',
            D4          => '0',
            TCE         => '0',
            T1          => '0',
            T2          => '0',
            T3          => '0',
            T4          => '0',
            SHIFTIN1    => '0',
            SHIFTIN2    => '0',
            SHIFTIN3    => oserdes_shift_d_m_in,
            SHIFTIN4    => '0',
            SHIFTOUT1   => oserdes_shift_d_m_out,
            SHIFTOUT2   => open,
            SHIFTOUT3   => open,
            SHIFTOUT4   => open,
            OQ          => oserdes_channel_out,
            TQ          => open
        );
    
    OSERDES2_slave_inst : OSERDES2
        generic map (
            DATA_RATE_OQ    => "SDR",
            DATA_RATE_OT    => "SDR",
            DATA_WIDTH      => 5,
            OUTPUT_MODE     => "SINGLE_ENDED",
            SERDES_MODE     => "SLAVE"
        )
        port map (
            CLK0        => PIX_CLK_X10,
            CLK1        => '0',
            OCE         => CLK_LOCKED,
            CLKDIV      => PIX_CLK_X2,
            RST         => RST,
            IOCE        => SERDESSTROBE,
            TRAIN       => '0',
            D1          => gearbox_x2_data(0),
            D2          => gearbox_x2_data(1),
            D3          => gearbox_x2_data(2),
            D4          => gearbox_x2_data(3),
            TCE         => '0',
            T1          => '0',
            T2          => '0',
            T3          => '0',
            T4          => '0',
            SHIFTIN1    => oserdes_shift_d_m_out,
            SHIFTIN2    => '0',
            SHIFTIN3    => '0',
            SHIFTIN4    => '0',
            SHIFTOUT1   => open,
            SHIFTOUT2   => open,
            SHIFTOUT3   => oserdes_shift_d_m_in,
            SHIFTOUT4   => open,
            OQ          => open,
            TQ          => open
        );
    
    enc_din_proc : process(rgb_ones_cnt, RGB(0), rgb_xor, rgb_xnor)
    begin
        if rgb_ones_cnt > 4 or (rgb_ones_cnt = 4 and RGB(0) = '0') then
            -- use xnored data
            rgb_enc <= rgb_xnor;
        else
            -- use xored data
            rgb_enc <= rgb_xor;
        end if;
    end process;
    
    gearbox_proc : process(PIX_CLK_X2)
    begin
        if rising_edge(PIX_CLK_X2) then
            -- less significant 5 bits first
            if gearbox_data_select = '0' then
                gearbox_x2_data <= gearbox_x1_data(4 downto 0);
            else
                gearbox_x2_data <= gearbox_x1_data(9 downto 5);
            end if;
            gearbox_data_select <= not gearbox_data_select;
        end if;
    end process;
    
    encoding_eval_proc : process(PIX_CLK)
        variable data_out       : unsigned(9 downto 0) := (others => '0');
        variable ones           : unsigned(2 downto 0) := "000";
        variable disp_out       : signed(3 downto 0) := x"0";
    begin
        if rising_edge(PIX_CLK) then
            -- reset disparity between video frames
            disp_out    := to_signed(0, total_disp'length);
            case ENCODING is
                
                when "000" =>
                    -- Control
                    case CTL is
                        when "00"   =>  data_out    := "1101010100";
                        when "01"   =>  data_out    := "0010101011";
                        when "10"   =>  data_out    := "0101010100";
                        when others =>  data_out    := "1010101011";
                    end case;
                
                when "001" =>
                    -- Video Leading Guard Band
                    case CHANNEL_NUM is
                        when 0  => data_out := "1011001100";
                        when 1  => data_out := "0100110011";
                        when 2  => data_out := "1011001100";
                    end case;
                
                when "010" =>
                    -- Video Data
                    if total_disp = 0 or rgb_enc_disp = 0 then
                        -- no disperity (previously or now), no need for correction
                        if rgb_enc(8) = '1' then
                            data_out    := "01" & rgb_enc(7 downto 0);
                            disp_out    := total_disp + rgb_enc_disp;
                        else
                            data_out    := "10" & rgb_enc_inv(7 downto 0);
                            disp_out    := total_disp - rgb_enc_disp;
                        end if;
                    else
                        if total_disp(total_disp'high) = rgb_enc_disp(rgb_enc_disp'high) then
                            -- either positive or negative disparity in both
                            -- the previous transm. and the current data,
                            -- correction needed
                            data_out    := "1" & rgb_enc(8) & rgb_enc_inv(7 downto 0);
                            disp_out    :=  total_disp +
                                            signed("000" & rgb_enc(8 downto 8)) +
                                            signed("000" & rgb_enc(8 downto 8)) -
                                            rgb_enc_disp;
                        else
                            -- the current data is already correcting the
                            -- total disperity, don't change it
                            data_out    := "0" & rgb_enc;
                            disp_out    :=  total_disp -
                                            signed("000" & rgb_enc_inv(8 downto 8)) -
                                            signed("000" & rgb_enc_inv(8 downto 8)) +
                                            rgb_enc_disp;
                        end if;
                    end if;
                
                when "011" =>
                    -- Data Island Guard Band
                    case CHANNEL_NUM is
                        when 0 => data_out  := terc4("11" & VSYNC & HSYNC); -- 0xC to 0xF
                        when 1 => data_out  := "0100110011";
                        when 2 => data_out  := "0100110011";
                    end case;
                
                when "100" =>
                    -- TERC4 encoded data
                    data_out    := terc4(rgb_uns(3 downto 0));
                
                when others =>
                    data_out    := (others => '0');
                
            end case;
            gearbox_x1_data <= std_ulogic_vector(data_out);
            total_disp      <= disp_out;
        end if;
    end process;
    
end rtl;

