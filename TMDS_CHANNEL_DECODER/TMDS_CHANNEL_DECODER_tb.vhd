--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   18:12:00 06/28/2014
-- Module Name:   TMDS_CHANNEL_DECODER_tb
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: TMDS_CHANNEL_DECODER
-- 
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments:
--
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
library work;
use work.txt_util.all;
use work.help_funcs.all;

ENTITY TMDS_CHANNEL_DECODER_tb IS
END TMDS_CHANNEL_DECODER_tb;

ARCHITECTURE rtl OF TMDS_CHANNEL_DECODER_tb IS 
    
    ----------------------------------
    ------ TMDS channel encoder ------
    ----------------------------------
    
    type decoders_data_type is
        array(0 to 2) of
        std_ulogic_vector(9 downto 0);
    
    -- Inputs
    signal decoders_pix_clk         : std_ulogic := '0';
    signal decoders_pix_clk_x2      : std_ulogic := '0';
    signal decoders_pix_clk_x10     : std_ulogic := '0';
    signal decoders_rst             : std_ulogic := '0';
    signal decoders_clk_locked      : std_ulogic := '0';
    signal decoders_serdesstrobe    : std_ulogic := '0';
    signal decoders_channel_in      : std_ulogic_vector(2 downto 0) := "000";

    -- Outputs
    signal decoders_data_out        : decoders_data_type := (others => (others => '0'));
    signal decoders_data_valid      : std_ulogic_vector(2 downto 0) := "000";
    
    
    ------------------------------
    ------ clock generation ------
    ------------------------------
    
    -- Inputs
    signal clk_man_clk_in   : std_ulogic := '0';
    
    -- Outputs
    signal clk_man_clk_out0     : std_ulogic := '0';
    signal clk_man_clk_out1     : std_ulogic := '0';
    signal clk_man_clk_out2     : std_ulogic := '0';
    signal clk_man_clk_out3     : std_ulogic := '0';
    signal clk_man_clk_out4     : std_ulogic := '0';
    signal clk_man_clk_out5     : std_ulogic := '0';
    signal clk_man_ioclk_out    : std_ulogic := '0';
    signal clk_man_ioclk_locked : std_ulogic := '0';
    signal clk_man_serdesstrobe : std_ulogic := '0';
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal decoders_channel_in_n    : std_ulogic_vector(2 downto 0) := "111";
    
    type decoders_dec_data_type is
        array(0 to 2) of
        std_ulogic_vector(9 downto 0);
    
    type decoders_enc_data_type is
        array(0 to 2) of
        std_ulogic_vector(7 downto 0);
    
    signal decoders_dec_data
        : decoders_dec_data_type
        := (others => (others => '0'));
        
    signal decoders_enc_data
        : decoders_enc_data_type
        := (others => (others => '0'));
    
    signal pix_clk_period   : time := 1 us;
    
    type decoders_channel_phases_type is
        array(0 to 2) of
        real range 0.0 to 360.0;
    
    signal decoders_channel_phases  : decoders_channel_phases_type := (others => 0.0);
    signal decoders_channel_in_del  : std_ulogic_vector(2 downto 0) := "000";

BEGIN
    
    decoders_pix_clk        <= clk_man_clk_out2;
    decoders_pix_clk_x2     <= clk_man_clk_out1;
    decoders_pix_clk_x10    <= clk_man_ioclk_out;
    decoders_rst            <= g_rst;
    decoders_clk_locked     <= clk_man_ioclk_locked;
    decoders_serdesstrobe   <= clk_man_serdesstrobe;
    decoders_channel_in_n   <= not decoders_channel_in;
    
    TMDS_CHANNEL_DECODERS_gen : for i in 0 to 2 generate
        TMDS_CHANNEL_DECODER_inst : entity work.TMDS_CHANNEL_DECODER
            generic map (
                CHANNEL_NUM => i
            )
            port map (
                PIX_CLK         => decoders_pix_clk,
                PIX_CLK_X2      => decoders_pix_clk_x2,
                PIX_CLK_X10     => decoders_pix_clk_x10,
                RST             => decoders_rst,
                CLK_LOCKED      => decoders_clk_locked,
                SERDESSTROBE    => decoders_serdesstrobe,
                CHANNEL_IN_P    => decoders_channel_in(i),
                CHANNEL_IN_N    => decoders_channel_in_n(i),
                
                DATA_OUT        => decoders_data_out(i),
                DATA_OUT_VALID  => decoders_data_valid(i)
            );
    end generate;
    
    clk_man_clk_in  <= g_clk;
    
    ISERDES_CLK_MAN_inst : entity work.ISERDES2_CLK_MAN
        generic map (
            MULTIPLIER      => 10,
            CLK_IN_PERIOD   => 13.0, -- only for testing
            DIVISOR0        => 1,    -- pixel clock
            DIVISOR1        => 5,    -- serdes clock = pixel clock * 2
            DIVISOR2        => 10,   -- bit clock
            DATA_CLK_SELECT => 1,    -- clock out 1
            IO_CLK_SELECT   => 0     -- clock out 0
        )
        port map (
            CLK_IN          => clk_man_clk_in,
            CLK_OUT0        => clk_man_clk_out0,
            CLK_OUT1        => clk_man_clk_out1,
            CLK_OUT2        => clk_man_clk_out2,
            CLK_OUT3        => clk_man_clk_out3,
            CLK_OUT4        => clk_man_clk_out4,
            CLK_OUT5        => clk_man_clk_out5,
            IOCLK_OUT       => clk_man_ioclk_out,
            IOCLK_LOCKED    => clk_man_ioclk_locked,
            SERDESSTROBE    => clk_man_serdesstrobe
        );
    
    g_clk   <= not g_clk after pix_clk_period / 2;
    
    decoders_channel_delay_gen : for i in 0 to 2 generate
        
        decoders_channel_in(i)  <=
            decoders_channel_in_del(i) after
            decoders_channel_phases(i) / 360.0 * pix_clk_period;
        
    end generate;
    
    -- Stimulus process
    stim_proc: process
        
        constant width  : natural := 1280;
        constant height : natural := 720;
        
        constant data_island_gb : decoders_data_type := (
            "0000000000", "0100110011", "0100110011"
            );
        constant video_island_gb : decoders_data_type := (
            "1011001100", "0100110011", "1011001100"
            );
        
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
        
        function terc4 (din : std_ulogic_vector) return std_ulogic_vector
        is
            type terc4_table_type is array(0 to 15) of std_ulogic_vector(9 downto 0);
            -- terc4 encoding lookup table
            constant terc4_table    : terc4_table_type := (
                "1010011100", "1001100011", "1011100100", "1011100010",
                "0101110001", "0100011110", "0110001110", "0100111100",
                "1011001100", "0100111001", "0110011100", "1011000110",
                "1010001110", "1001110001", "0101100011", "1011000011"
            );
        begin
            return terc4_table(int(din));
        end function;
        
        procedure shift_out (constant ch0, ch1, ch2 : in std_ulogic_vector) is
        begin
            report str(ch0) & " | " & str(ch1) & " | " & str(ch2);
            for bit_i in 0 to 9 loop
                -- shift out LSB first
                decoders_channel_in_del(0)  <= ch0(bit_i);
                decoders_channel_in_del(1)  <= ch1(bit_i);
                decoders_channel_in_del(2)  <= ch2(bit_i);
                wait for pix_clk_period / 10;
            end loop;
        end procedure;
        
        procedure shift_out (constant ch0, ch1, ch2 : in std_ulogic_vector; n : natural) is
        begin
            for i in 1 to n loop
                shift_out(ch0, ch1, ch2);
            end loop;
        end procedure;
        
        procedure shift_out (variable pkt : in decoders_data_type) is
        begin
            shift_out(pkt(0), pkt(1), pkt(2));
        end procedure;
        
        procedure shift_out (variable pkt : in decoders_data_type; n : natural) is
        begin
            for i in 1 to n loop
                shift_out(pkt);
            end loop;
        end procedure;
        
        variable packet : decoders_data_type;
        variable vsync  : std_ulogic;
        
    begin		
        -- hold reset state for 100 ns.
        g_rst   <= '1';
        wait for 100 ns;
        g_rst   <= '0';

        wait for 200 ns;

        -- insert stimulus here
        
        pix_clk_period              <= 13 ns; -- 75 MHz
        decoders_channel_phases(0)  <= 10.0;
        decoders_channel_phases(1)  <= 70.0;
        decoders_channel_phases(2)  <= 25.0;
        
        wait for pix_clk_period;
        wait until rising_edge(g_clk);
        
        while true loop
            
            for total_y in 1 to 750 loop
                
                vsync   := '0';
                if total_y > 5 then
                    vsync   := '1';
                end if;
                
                -- control period, hsync=1
                shift_out(ctrl(vsync & '1'), ctrl("00"), ctrl("00"), 4);
                
                -- one null packet
                
                -- preamble
                shift_out(ctrl(vsync & '1'), ctrl("10"), ctrl("10"), 8);
                -- data island leading guard band
                packet      := data_island_gb;
                packet(0)   := terc4("11" & vsync & '1');
                shift_out(packet);
                shift_out(packet);
                
                -- packet header and body
                packet(0)   := terc4("00" & vsync & '1');
                packet(1)   := terc4("0000");
                packet(2)   := terc4("0000");
                shift_out(packet);
                packet(0)   := terc4("10" & vsync & '1');
                for pkt_i in 1 to 31 loop
                    shift_out(packet);
                end loop;
                
                -- data island trailing guard band
                packet      := data_island_gb;
                packet(0)   := terc4("11" & vsync & '1');
                shift_out(packet);
                shift_out(packet);
                
                -- control period, hblank
                shift_out(ctrl(vsync & '1'), ctrl("00"), ctrl("00"), 162);
                
                if total_y > 30 then
                    
                    -- video data
                    
                    -- preamble
                    shift_out(ctrl(vsync & '1'), ctrl("10"), ctrl("10"), 8);
                    -- video island leading guard band
                    packet  := video_island_gb;
                    shift_out(packet);
                    shift_out(packet);
                    
                    -- 1280 TMDS encoded black pixels
                    for i in 1 to 256 loop
                        shift_out("1111111111", "1111111111", "1111111111");
                        shift_out("0100000000", "0100000000", "0100000000");
                        shift_out("1111111111", "1111111111", "1111111111");
                        shift_out("0100000000", "0100000000", "0100000000");
                        shift_out("0100000000", "0100000000", "0100000000");
                    end loop;
                    
                    -- video island trailing guard band
                    packet  := video_island_gb;
                    shift_out(packet);
                    shift_out(packet);
                    
                else
                    
                    -- control period, vblank
                    shift_out(ctrl(vsync & '1'), ctrl("00"), ctrl("00"), 1292);
                    
                end if;
                
                -- control period, rest of hblank
                shift_out(ctrl(vsync & '1'), ctrl("00"), ctrl("00"), 110);
                -- hsync=0
                shift_out(ctrl(vsync & '0'), ctrl("00"), ctrl("00"), 40);
                
            end loop;
            
        end loop;
        
    end process;

END;
