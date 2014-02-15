----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    18:41:53 02/07/2014
-- Module Name:    TMDS_CHANNEL_ENCODER - rtl
-- Description:    Encoder of a single TMDS channel compliant to the
--                 HDMI 1.4 specification
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--  ports:
--   ENCODING : 0 = Preamble
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
        DATA_IN         : in std_ulogic_vector(7 downto 0);
        ENCODING        : in std_ulogic_vector(2 downto 0);
        CHANNEL_OUT_P   : out std_ulogic := '0';
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
    signal din_uns              : unsigned(7 downto 0) := (others => '0');
    signal din_xor              : unsigned(8 downto 0) := (others => '0');
    signal din_xnor             : unsigned(8 downto 0) := (others => '0');
    signal din_ones_cnt         : unsigned(3 downto 0) := (others => '0');
    signal din_enc              : unsigned(8 downto 0) := (others => '0');
    signal din_enc_inv          : unsigned(8 downto 0) := (others => '0');
    signal din_enc_disp         : signed(3 downto 0) := (others => '0'); 
    signal total_disp           : signed(3 downto 0) := (others => '0');
    
    function terc4
    (
        din : unsigned(3 downto 0)
    )
        return unsigned
    is
        type terc4_table_type is array(0 to 15) of unsigned(9 downto 0);
        constant terc4_table    : terc4_table_type := (
            "1010011100", "1001100011", "1011100100", "1011100010",
            "0101110001", "0100011110", "0110001110", "0100111100",
            "1011001100", "0100111001", "0110011100", "1011000110",
            "1010001110", "1001110001", "0101100011", "1011000011"
        );
    begin
        return terc4_table(to_integer(din));
    end function;
    
begin
    
    din_uns <= unsigned(DATA_IN);
    
    din_xor(0)  <= DATA_IN(0);
    din_xor(1)  <= DATA_IN(1) xor DATA_IN(0);
    din_xor(2)  <= DATA_IN(2) xor din_xor(1);
    din_xor(3)  <= DATA_IN(3) xor din_xor(2);
    din_xor(4)  <= DATA_IN(4) xor din_xor(3);
    din_xor(5)  <= DATA_IN(5) xor din_xor(4);
    din_xor(6)  <= DATA_IN(6) xor din_xor(5);
    din_xor(7)  <= DATA_IN(7) xor din_xor(6);
    din_xor(8)  <= '1';
    
    din_xnor(0) <= DATA_IN(0);
    din_xnor(1) <= DATA_IN(1) xnor DATA_IN(0);
    din_xnor(2) <= DATA_IN(2) xnor din_xnor(1);
    din_xnor(3) <= DATA_IN(3) xnor din_xnor(2);
    din_xnor(4) <= DATA_IN(4) xnor din_xnor(3);
    din_xnor(5) <= DATA_IN(5) xnor din_xnor(4);
    din_xnor(6) <= DATA_IN(6) xnor din_xnor(5);
    din_xnor(7) <= DATA_IN(7) xnor din_xnor(6);
    din_xnor(8) <= '0';
    
    din_enc_inv <= not din_enc;
    
    din_ones_cnt    <=  to_unsigned(0, 4) +
                        din_uns(0 downto 0) + din_uns(1 downto 1) +
                        din_uns(2 downto 2) + din_uns(3 downto 3) +
                        din_uns(4 downto 4) + din_uns(5 downto 5) +
                        din_uns(6 downto 6) + din_uns(7 downto 7);
    
    -- disperity between ones and zeros of din_enc, 0 = equal number of '1's and '0's
    din_enc_disp    <=  to_signed(-4, 4) + signed("0000" +
                            din_enc(0 downto 0) + din_enc(1 downto 1) +
                            din_enc(2 downto 2) + din_enc(3 downto 3) +
                            din_enc(4 downto 4) + din_enc(5 downto 5) +
                            din_enc(6 downto 6) + din_enc(7 downto 7)
                        );
    
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
    
    enc_din_proc : process(din_ones_cnt, DATA_IN(0), din_xor, din_xnor)
    begin
        if din_ones_cnt > 4 or (din_ones_cnt = 4 and DATA_IN(0) = '0') then
            -- use xored data
            din_enc <= din_xor;
        else
            -- use xnored data
            din_enc <= din_xnor;
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
        variable data_out   : unsigned(9 downto 0) := (others => '0');
        variable ones       : unsigned(2 downto 0) := (others => '0');
        variable disp_out   : signed(3 downto 0) := (others => '0');
    begin
        if rising_edge(PIX_CLK) then
            -- reset disparity between video frames
            disp_out    := to_signed(0, total_disp'length);
            case ENCODING is
                
                when "000" =>
                    -- Preamble
                    case DATA_IN(1 downto 0) is
                        when "00" => data_out   := "1101010100";
                        when "01" => data_out   := "0010101011";
                        when "10" => data_out   := "0101010100";
                        when others => data_out := "1010101011";
                    end case;
                
                when "001" =>
                    -- Video Leading Guard Band
                    case CHANNEL_NUM is
                        when 0 => data_out  := "1011001100";
                        when 1 => data_out  := "0100110011";
                        when 2 => data_out  := "1011001100";
                    end case;
                
                when "010" =>
                    -- Video Data
                    if total_disp = 0 or din_enc_disp = 0 then
                        -- no disperity (previously or now), no need for correction
                        if din_enc(8) = '1' then
                            data_out    := "01" & din_enc(7 downto 0);
                            disp_out    := total_disp + din_enc_disp;
                        else
                            data_out    := "10" & din_enc_inv(7 downto 0);
                            disp_out    := total_disp - din_enc_disp;
                        end if;
                    else
                        if total_disp(total_disp'high) = din_enc_disp(din_enc_disp'high) then
                            -- either positive or negative disparity in both
                            -- the previoud transm. and the current data,
                            -- correction needed
                            data_out    := "1" & din_enc(8) & din_enc_inv(7 downto 0);
                            disp_out    :=  total_disp +
                                            signed("000" & din_enc(8 downto 8)) +
                                            signed("000" & din_enc(8 downto 8)) -
                                            din_enc_disp;
                        else
                            -- the current data is already correcting the
                            -- total disperity, don't change it
                            data_out    := "0" & din_enc;
                            disp_out    :=  total_disp -
                                            signed("000" & din_enc_inv(8 downto 8)) -
                                            signed("000" & din_enc_inv(8 downto 8)) +
                                            din_enc_disp;
                        end if;
                    end if;
                
                when "011" =>
                    -- Data Island Guard Band
                    case CHANNEL_NUM is
                        when 0 => data_out  := terc4("11" & din_uns(1 downto 0)); -- 0xC to 0xF
                        when 1 => data_out  := "0100110011";
                        when 2 => data_out  := "0100110011";
                    end case;
                
                when "100" =>
                    -- TERC4 encoded data
                    data_out    := terc4(din_uns(3 downto 0));
                
                when others =>
                    null;
                
            end case;
            gearbox_x1_data <= std_ulogic_vector(data_out);
            total_disp      <= disp_out;
        end if;
    end process;
    
end rtl;

