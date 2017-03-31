--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   15:04:00 12/27/2014
-- Module Name:   tmds_test_encoder
-- Description:
--  
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

ARCHITECTURE behavioral OF test_tmds_encoder IS 
    
    constant VP : video_profile_type := VIDEO_PROFILES(PROFILE);
    
    constant TOTAL_VER_LINES    : natural := VP.v_sync_lines + VP.v_front_porch + VP.height +
                                                VP.v_back_porch;
    
    constant TOTAL_HOR_PIXELS   : natural := VP.h_sync_cycles + VP.h_front_porch + VP.width +
                                                VP.h_back_porch;
    
    constant V_SYNC_END     : natural := VP.v_sync_lines;
    constant V_RGB_START    : natural := VP.v_sync_lines+VP.v_front_porch;
    constant V_RGB_END      : natural := VP.v_sync_lines+VP.v_front_porch+VP.height;
    
    constant H_SYNC_END     : natural := VP.h_sync_cycles;
    constant H_RGB_START    : natural := VP.h_sync_cycles+VP.h_front_porch;
    constant H_RGB_END      : natural := VP.h_sync_cycles+VP.h_front_porch+VP.width;
    
    type decoder_enc_data_type is
        array(0 to 2) of
        std_ulogic_vector(9 downto 0);
    
    constant data_island_gb : decoder_enc_data_type := (
        "0000000000", "0100110011", "0100110011"
        );
    constant video_data_gb : decoder_enc_data_type := (
        "1011001100", "0100110011", "1011001100"
        );
    
    constant PIX_CLK_PERIOD : time := VP.pixel_period;
    
    signal pix_clk  : std_ulogic := '0';
    signal chs_out, chs_out_delayed : std_ulogic_vector(2 downto 0) := "111";
    
    signal pos_hsync, pos_vsync : std_ulogic := '0';
    signal hsync, vsync         : std_ulogic;
    
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
    
    function tmds8to10 (din : std_ulogic_vector(7 downto 0))
        return std_ulogic_vector
    is
        variable ones_count : unsigned(2 downto 0);
        variable dout       : std_ulogic_vector(9 downto 0);
    begin
        -- simplified TMDS encoding,
        -- doesn't take previous data into account
        -- and just sends more ones than zeros
        ones_count  := uns(0, 3)+
            din(0)+din(1)+din(2)+din(3)+
            din(4)+din(5)+din(6)+din(7);
        dout(0) := din(0);
        if ones_count>4 then
            dout(1) := din(1) xnor din(0);
            dout(2) := din(2) xnor dout(1);
            dout(3) := din(3) xnor dout(2);
            dout(4) := din(4) xnor dout(3);
            dout(5) := din(5) xnor dout(4);
            dout(6) := din(6) xnor dout(5);
            dout(7) := din(7) xnor dout(6);
            dout(8) := '0';
        else
            dout(1) := din(1) xor din(0);
            dout(2) := din(2) xor dout(1);
            dout(3) := din(3) xor dout(2);
            dout(4) := din(4) xor dout(3);
            dout(5) := din(5) xor dout(4);
            dout(6) := din(6) xor dout(5);
            dout(7) := din(7) xor dout(6);
            dout(8) := '1';
        end if;
        ones_count  := uns(0, 3)+
            dout(0)+dout(1)+dout(2)+dout(3)+
            dout(4)+dout(5)+dout(6)+dout(7)+
            dout(8);
        if ones_count>4 then
            dout(9) := '0';
        else
            dout(9) := '1';
            dout(7 downto 0)    := not dout(7 downto 0);
        end if;
        return dout;
    end function;

BEGIN
    
    CHANNELS_OUT_P(2 downto 0)  <= chs_out_delayed;
    CHANNELS_OUT_N(2 downto 0)  <= not chs_out_delayed;
    
    CHANNELS_OUT_P(3)   <= pix_clk;
    CHANNELS_OUT_N(3)   <= not pix_clk;
    
    chs_out_delayed(0)   <= transport chs_out(0) after CH0_PHASE / 360.0 * pix_clk_period;
    chs_out_delayed(1)   <= transport chs_out(1) after CH1_PHASE / 360.0 * pix_clk_period;
    chs_out_delayed(2)   <= transport chs_out(2) after CH2_PHASE / 360.0 * pix_clk_period;
    
    pix_clk <= not pix_clk after PIX_CLK_PERIOD/2;
    
    hsync   <= not pos_hsync when VP.negative_hsync else pos_hsync;
    vsync   <= not pos_vsync when VP.negative_vsync else pos_vsync;
    
    process
        
        procedure shift_out (constant ch0, ch1, ch2 : in std_ulogic_vector) is
        begin
            -- shift out LSB first
            for bit_i in ch0'reverse_range loop
                chs_out(0)  <= ch0(bit_i);
                chs_out(1)  <= ch1(bit_i);
                chs_out(2)  <= ch2(bit_i);
                wait for PIX_CLK_PERIOD / 10;
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
        variable r, g, b    : std_ulogic_vector(7 downto 0);
        
    begin
        assert not VP.interlaced
            report "Interlaced profiles are not yet supported by this testbench!"
            severity FAILURE;
        
        -- send some noise
        wait for 0.7 * PIX_CLK_PERIOD;
        shift_out("10101110", "11001010", "00101010", 2);
        
        loop
            
            pos_vsync   <= '1';
            
            for y in 1 to TOTAL_VER_LINES loop
                
                report "line " & natural'image(y);
                
                if y > V_SYNC_END then
                    pos_vsync   <= '0';
                end if;
                
                -- control period, hsync
                pos_hsync   <= '1';
                shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.h_sync_cycles);
                
                -- horizontal front porch
                pos_hsync   <= '0';
                shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.h_front_porch-10);
                
                if y > V_RGB_START and y <= V_RGB_END then
                    
                    -- video data
                    
                    -- preamble
                    shift_out(ctrl(vsync & hsync), ctrl("10"), ctrl("10"), 8);
                    -- video data leading guard band
                    packet  := video_data_gb;
                    shift_out(packet, 2);
                    
                    for x in 1 to VP.width loop
                        r   := stdulv(x mod 256, 8);
                        g   := stdulv(y mod 256, 8);
                        b   := stdulv((x mod 128) + (y mod 128), 8);
                        -- apply simplified TMDS encoding
                        shift_out(tmds8to10(r), tmds8to10(g), tmds8to10(b));
                    end loop;
                    
                else
                    
                    -- control period, vblank
                    shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.width+10);
                    
                end if;
                
                -- horizontal back porch (minimum length of 12 pixels)
                shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), 12);
                
                if VP.h_back_porch>12+8+2+32+2 then
                    
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
                    
                    -- control period, rest of hblank
                    shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.h_back_porch-12-8-2-32-2);
                    
                else
                    
                    -- no time for a null packet
                    shift_out(ctrl(vsync & hsync), ctrl("00"), ctrl("00"), VP.h_back_porch-12);
                    
                end if;
                
            end loop;
        end loop;
        
    end process;

END;
