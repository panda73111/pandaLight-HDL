--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   15:04:00 12/27/2014
-- Module Name:   tmds_test_encoder
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: TMDS_DECODER
-- 
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments:
--
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.txt_util.all;
use work.help_funcs.all;
use work.video_profiles.all;

ENTITY test_tmds_encoder IS
    generic (
        PROFILE     : natural range 0 to VIDEO_PROFILE_COUNT-1 := 0;
        CH0_PHASE   : real range 0.0 to 360.0 := 10.0;
        CH1_PHASE   : real range 0.0 to 360.0 := 70.0;
        CH2_PHASE   : real range 0.0 to 360.0 := 25.0
    );
    port (
        CHANNELS_OUT_P  : out std_ulogic_vector(3 downto 0) := "1111";
        CHANNELS_OUT_N  : out std_ulogic_vector(3 downto 0) := "1111"
    );
END test_tmds_encoder;

ARCHITECTURE rtl OF test_tmds_encoder IS 
    
    constant VP : video_profile_type := VIDEO_PROFILES(PROFILE);
    
    signal pix_clk  : std_ulogic := '0';
    
    signal pix_clk_period   : time := 10 ns * VP.clk10_mult / VP.clk10_div;
    signal chs_out, chs_out_delayed : std_ulogic_vector(2 downto 0) := "111";
    
    signal pos_hsync, pos_vsync : std_ulogic;
    signal hsync, vsync         : std_ulogic;

BEGIN
    
    CHANNELS_OUT_P(2 downto 0)  <= chs_out_delayed;
    CHANNELS_OUT_N(2 downto 0)  <= not chs_out_delayed;
    
    CHANNELS_OUT_P(3)   <= pix_clk;
    CHANNELS_OUT_N(3)   <= not pix_clk;
    
    chs_out_delayed(0)   <= transport chs_out(0) after CH0_PHASE / 360.0 * pix_clk_period;
    chs_out_delayed(1)   <= transport chs_out(1) after CH1_PHASE / 360.0 * pix_clk_period;
    chs_out_delayed(2)   <= transport chs_out(2) after CH2_PHASE / 360.0 * pix_clk_period;
    
    pix_clk <= not pix_clk after pix_clk_period/2;
    
    hsync   <= not pos_hsync when VP.negative_hsync else pos_hsync;
    vsync   <= not pos_vsync when VP.negative_vsync else pos_vsync;
    
    process
        
        constant TOTAL_VER_LINES    : natural := VP.v_sync_lines + VP.v_front_porch + VP.top_border + VP.height +
                                                    VP.bottom_border + VP.v_back_porch;
        
        constant TOTAL_HOR_PIXELS   : natural := VP.h_sync_cycles + VP.h_front_porch + VP.left_border + VP.width +
                                                    VP.right_border + VP.h_back_porch;
        
        constant V_SYNC_END     : natural := VP.v_sync_lines;
        constant V_RGB_START    : natural := VP.v_sync_lines+VP.v_front_porch+VP.top_border;
        constant V_RGB_END      : natural := VP.v_sync_lines+VP.v_front_porch+VP.top_border+VP.height;
        
        constant H_SYNC_END     : natural := VP.h_sync_cycles;
        constant H_RGB_START    : natural := VP.h_sync_cycles+VP.h_front_porch+VP.left_border;
        constant H_RGB_END      : natural := VP.h_sync_cycles+VP.h_front_porch+VP.left_border+VP.width;
        
        type decoder_enc_data_type is
            array(0 to 2) of
            std_ulogic_vector(9 downto 0);
        
        constant data_island_gb : decoder_enc_data_type := (
            "0000000000", "0100110011", "0100110011"
            );
        constant video_data_gb : decoder_enc_data_type := (
            "1011001100", "0100110011", "1011001100"
            );
        
        function ctrl (din : std_ulogic_vector(1 downto 0))
            return std_ulogic_vector is
        begin
            case din is
                when "00"   => return "1101010100";
                when "01"   => return "0010101011";
                when "10"   => return "0101010100";
                when others => return "1010101011";
            end case;
        end function;
        
        function terc4 (din : std_ulogic_vector(3 downto 0))
            return std_ulogic_vector is
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
        
        procedure shift_out (constant ch0, ch1, ch2 : in std_ulogic_vector) is
        begin
--            report hstr(ch0) & " | " & hstr(ch1) & " | " & hstr(ch2);
            -- shift out LSB first
            for bit_i in ch0'reverse_range loop
                chs_out(0)  <= ch0(bit_i);
                chs_out(1)  <= ch1(bit_i);
                chs_out(2)  <= ch2(bit_i);
                wait for pix_clk_period / 10;
            end loop;
        end procedure;
        
        procedure shift_out (constant ch0, ch1, ch2 : in std_ulogic_vector; n : natural) is
        begin
            for i in 1 to n loop
                shift_out(ch0, ch1, ch2);
            end loop;
        end procedure;
        
        procedure shift_out (variable pkt : in decoder_enc_data_type) is
        begin
            shift_out(pkt(0), pkt(1), pkt(2));
        end procedure;
        
        procedure shift_out (variable pkt : in decoder_enc_data_type; n : natural) is
        begin
            for i in 1 to n loop
                shift_out(pkt);
            end loop;
        end procedure;
        
        variable packet : decoder_enc_data_type;
        
    begin
        assert not VP.interlaced
            report "Interlaced profiles are not yet supported by this testbench!"
            severity FAILURE;
        
        -- send some noise
        wait for 0.7 * pix_clk_period;
        shift_out("10101110", "11001010", "00101010", 2);
        
        loop
            
            pos_vsync   <= '1';
            
            for y in 1 to TOTAL_VER_LINES loop
                
                if y >= V_SYNC_END then
                    pos_vsync   <= '0';
                end if;
                
                -- control period (minimum length of 12 pixels)
                pos_hsync   <= '1';
                shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), 12);
                
                -- one null packet
                
                -- preamble
                shift_out(ctrl(vsync & hsync), ctrl("10"), ctrl("10"), 8);
                -- data island leading guard band
                packet      := data_island_gb;
                packet(0)   := terc4("11" & vsync & hsync);
                shift_out(packet, 2);
                
                -- packet header and body
                packet(0)   := terc4("00" & vsync & hsync);
                packet(1)   := terc4("0000");
                packet(2)   := terc4("0000");
                shift_out(packet);
                packet(0)   := terc4("10" & vsync & hsync);
                for pkt_i in 1 to 31 loop
                    shift_out(packet);
                end loop;
                
                -- data island trailing guard band
                packet      := data_island_gb;
                packet(0)   := terc4("11" & vsync & hsync);
                shift_out(packet, 2);
                
                -- control period, hblank
                shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.h_sync_cycles-12-8-2-32-2);
                
                -- horizontal front porch
                pos_hsync   <= '0';
                shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.h_front_porch+VP.top_border-10);
                
                if y >= V_RGB_START then
                    
                    -- video data
                    
                    -- preamble
                    shift_out(ctrl(vsync & hsync), ctrl("10"), ctrl("10"), 8);
                    -- video data leading guard band
                    packet  := video_data_gb;
                    shift_out(packet, 2);
                    
                    -- TMDS encoded black pixels
                    for i in 1 to VP.width/5 loop
                        shift_out("1111111111", "1111111111", "1111111111");
                        shift_out("0100000000", "0100000000", "0100000000");
                        shift_out("1111111111", "1111111111", "1111111111");
                        shift_out("0100000000", "0100000000", "0100000000");
                        shift_out("0100000000", "0100000000", "0100000000");
                    end loop;
                    for i in 1 to VP.width mod 5 loop
                        shift_out("1111111111", "1111111111", "1111111111");
                    end loop;
                    
                else
                    
                    -- control period, vblank
                    shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.width);
                    
                end if;
                
                -- control period, horizontal back porch
                shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.bottom_border+VP.h_back_porch);
                
            end loop;
        end loop;
        
    end process;

END;
