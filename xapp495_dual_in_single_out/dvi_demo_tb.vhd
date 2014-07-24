--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   14:09:00 24/07/2014
-- Module Name:   TMDS_CHANNEL_DECODER_tb
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: DVI_DEMO
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

ENTITY DVI_DEMO_tb IS
END DVI_DEMO_tb;

ARCHITECTURE rtl OF DVI_DEMO_tb IS 
    
    ----------------------------------
    ------ TMDS channel encoder ------
    ----------------------------------
    
    type decoders_data_type is
        array(0 to 2) of
        std_ulogic_vector(9 downto 0);
    
    -- Inputs
    signal dvi_rstbtn_n     : std_ulogic := '0';
    signal dvi_clk100       : std_ulogic := '0';
    signal dvi_rx0_tmds     : std_ulogic_vector(3 downto 0) := "0000";
    signal dvi_rx0_tmdsb    : std_ulogic_vector(3 downto 0) := "0000";
    signal dvi_rx1_tmds     : std_ulogic_vector(3 downto 0) := "0000";
    signal dvi_rx1_tmdsb    : std_ulogic_vector(3 downto 0) := "0000";
    signal dvi_sw           : std_ulogic := '0';

    -- Outputs
    signal dvi_tx0_tmds     : std_ulogic_vector(3 downto 0) := "0000";
    signal dvi_tx0_tmdsb    : std_ulogic_vector(3 downto 0) := "0000";
    signal dvi_led          : std_ulogic_vector(7 downto 0) := x"00";
    
    signal pix_clk_period   : time := 1 us;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    type dvi_phases_type is
        array(0 to 2) of
        real range 0.0 to 360.0;
    
    signal dvi_rx0_phases   : dvi_phases_type := (others => 0.0);
    signal dvi_rx0_tmds_del : std_ulogic_vector(2 downto 0) := "000";

BEGIN
    
    dvi_clk100      <= g_clk;
    dvi_rstbtn_n    <= not g_rst;
    dvi_rx0_tmdsb   <= not dvi_rx0_tmds;
    dvi_rx1_tmdsb   <= not dvi_rx1_tmds;
    
    dvi_rx0_tmds(3) <= not dvi_rx0_tmds(3) after pix_clk_period / 2;
    g_clk           <= not g_clk after 5 ns;
    
    dvi_rx_channel_delay_gen : for i in 0 to 2 generate
        
        dvi_rx0_tmds(i) <=
            dvi_rx0_tmds_del(i) after
            dvi_rx0_phases(i) / 360.0 * pix_clk_period;
        
    end generate;
    
    DVI_DEMO_inst : entity work.dvi_demo
        port map (
            rstbtn_n    => dvi_rstbtn_n,
            clk100      => dvi_clk100,
            RX0_TMDS    => dvi_rx0_tmds,
            RX0_TMDSB   => dvi_rx0_tmdsb,
            RX1_TMDS    => dvi_rx1_tmds,
            RX1_TMDSB   => dvi_rx1_tmdsb,

            TX0_TMDS    => dvi_tx0_tmds,
            TX0_TMDSB   => dvi_tx0_tmdsb,

            SW  => dvi_sw,

            LED => dvi_led
        );
    
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
            for bit_i in 0 to 9 loop
                -- shift out LSB first
                dvi_rx0_tmds_del(0)  <= ch0(bit_i);
                dvi_rx0_tmds_del(1)  <= ch1(bit_i);
                dvi_rx0_tmds_del(2)  <= ch2(bit_i);
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
        
        pix_clk_period      <= 13 ns; -- 75 MHz
        dvi_rx0_phases(0)   <= 10.0;
        dvi_rx0_phases(1)   <= 70.0;
        dvi_rx0_phases(2)   <= 25.0;
        
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
