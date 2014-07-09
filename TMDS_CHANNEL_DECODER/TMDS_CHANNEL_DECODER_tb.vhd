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

ENTITY TMDS_CHANNEL_ENCODER_tb IS
END TMDS_CHANNEL_ENCODER_tb;

ARCHITECTURE rtl OF TMDS_CHANNEL_DECODER_tb IS 
    
    ----------------------------------
    ------ TMDS channel encoder ------
    ----------------------------------
    
    type
        decoders_data_out_type is
        array(0 to 2) of std_ulogic_vector(7 downto 0);
    
    type
        deoders_channel_in_type is
        array(0 to 2) of std_ulogic_vector(1 downto 0);
    
    -- Inputs
    signal decoders_pix_clk         : std_ulogic := '0';
    signal decoders_pix_clk_x2      : std_ulogic := '0';
    signal decoders_pix_clk_x10     : std_ulogic := '0';
    signal decoders_rst             : std_ulogic := '0';
    signal decoders_clk_locked      : std_ulogic := '0';
    signal decoders_serdesstrobe    : std_ulogic := '0';
    signal encoders_channel_in      : decoders_channel_in_type := (others => "00");

    -- Outputs
    signal decoders_data_out        : encoders_data_out_type := (others => x"00");
    signal decoders_encoding        : std_ulogic_vector(2 downto 0) := "000";
    
    
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
    
    
    -- Clock period definitions
    constant g_clk_period       : time := 10 ns; -- 100 MHz
    constant g_clk_period_real  : real := real(g_clk_period / 1 ps) / real(1 ns / 1 ps);
    
    -- 720p: 75 MHz pixel clock = 100 MHz * 3 / 4
    constant pix_clk_mult   : natural := 3;
    constant pix_clk_div    : natural := 4;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    type
        decoders_deser_data_type is
        array(0 to 2) of std_ulogic_vector(9 downto 0);
    
    type
        decoders_enc_vid_data_type is
        array(0 to 2) of std_ulogic_vector(7 downto 0);
    
    signal decoders_deser_data
        : decoders_deser_data_type
        := (others => (others => '0'));
        
    signal decoders_enc_vid_data
        : decoders_enc_vid_data_type
        := (others => (others => '0'));

BEGIN
    
    decoders_pix_clk        <= clk_man_clk_out0;
    decoders_pix_clk_x2     <= clk_man_clk_out1;
    decoders_pix_clk_x10    <= clk_man_ioclk_out;
    decoders_rst            <= g_rst;
    decoders_clk_locked     <= clk_man_ioclk_locked;
    decoders_serdesstrobe   <= clk_man_serdesstrobe;
    
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
                CHANNEL_IN_P    => decoders_channel_in(i)(0),
                CHANNEL_IN_N    => decoders_channel_in(i)(1)
                
                DATA_OUT        => decoders_data_out(i),
                ENCODING        => decoders_encoding,
            );
    end generate;
    
    clk_man_clk_in  <= g_clk;
    
    ISERDES_CLK_MAN_inst : entity work.ISERDES2_CLK_MAN
        generic map (
            CLK_IN_PERIOD   => g_clk_period_real,
            MULTIPLIER      => pix_clk_mult * 10,
            PREDIVISOR      => pix_clk_div,
            DIVISOR0        => 10, -- pixel clock
            DIVISOR1        => 5,  -- serdes clock = pixel clock * 2
            DIVISOR2        => 1,  -- bit clock
            DATA_CLK_SELECT => 1,  -- clock out 1
            IO_CLK_SELECT   => 2   -- clock out 2
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
    
    
    g_clk   <= not g_clk after g_clk_period / 2;

    -- Stimulus process
    stim_proc: process
    begin		
        -- hold reset state for 100 ns.
        g_rst   <= '1';
        wait for 100 ns;
        g_rst   <= '0';

        wait for g_clk_period*10;
        wait until rising_edge(g_clk);

        -- insert stimulus here
        
        
        wait;
    end process;

END;
