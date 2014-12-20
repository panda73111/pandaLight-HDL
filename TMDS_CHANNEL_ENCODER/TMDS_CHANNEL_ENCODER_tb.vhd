--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   14:30:44 02/08/2014
-- Module Name:   TMDS_CHANNEL_ENCODER_tb
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: TMDS_CHANNEL_ENCODER
-- 
-- Additional Comments:
--
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;

ENTITY TMDS_CHANNEL_ENCODER_tb IS
END TMDS_CHANNEL_ENCODER_tb;

ARCHITECTURE rtl OF TMDS_CHANNEL_ENCODER_tb IS 
    
    ----------------------------------
    ------ TMDS channel encoder ------
    ----------------------------------
    
    type encoders_rgb_type is
        array(0 to 2)
        of std_ulogic_vector(7 downto 0);
    
    type encoders_ctl_type is
        array(0 to 2)
        of std_ulogic_vector(1 downto 0);
    
    type encoders_aux_type is
        array(0 to 2)
        of std_ulogic_vector(3 downto 0);
        
    type encoders_channel_out_type is
        array(0 to 2)
        of std_ulogic_vector(1 downto 0);
    
    -- Inputs
    signal encoders_pix_clk         : std_ulogic := '0';
    signal encoders_pix_clk_x2      : std_ulogic := '0';
    signal encoders_pix_clk_x10     : std_ulogic := '0';
    signal encoders_rst             : std_ulogic := '0';
    
    signal encoders_clk_locked      : std_ulogic := '0';
    signal encoders_serdesstrobe    : std_ulogic := '0';
    
    signal encoders_hsync           : std_ulogic_vector(2 downto 0) := "000";
    signal encoders_vsync           : std_ulogic_vector(2 downto 0) := "000";
    signal encoders_rgb             : encoders_rgb_type := (others => x"00");
    signal encoders_ctl             : encoders_ctl_type := (others => "00");
    signal encoders_aux             : encoders_aux_type := (others => x"0");
    signal encoders_encoding        : std_ulogic_vector(2 downto 0) := "000";

    -- Outputs
    signal encoders_channel_out : encoders_channel_out_type := (others => "00");
    
    
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
    
    type encoders_deser_data_type is array(0 to 2) of std_ulogic_vector(9 downto 0);
    type encoders_dec_vid_data_type is array(0 to 2) of std_ulogic_vector(7 downto 0);
    signal encoders_deser_data      : encoders_deser_data_type := (others => (others => '0'));
    signal encoders_dec_vid_data    : encoders_dec_vid_data_type := (others => (others => '0'));
    
    signal chs_synchronized : std_ulogic_vector(2 downto 0) := "000";

BEGIN
    
    encoders_pix_clk        <= clk_man_clk_out1;
    encoders_pix_clk_x2     <= clk_man_clk_out2;
    encoders_pix_clk_x10    <= clk_man_ioclk_out;
    encoders_rst            <= g_rst;
    encoders_clk_locked     <= clk_man_ioclk_locked;
    encoders_serdesstrobe   <= clk_man_serdesstrobe;
    
    TMDS_CHANNEL_ENCODERS_gen : for i in 0 to 2 generate
        TMDS_CHANNEL_ENCODER_inst : entity work.TMDS_CHANNEL_ENCODER
            generic map (
                CHANNEL_NUM => i
            )
            port map (
                PIX_CLK         => encoders_pix_clk,
                PIX_CLK_X2      => encoders_pix_clk_x2,
                PIX_CLK_X10     => encoders_pix_clk_x10,
                RST             => encoders_rst,
                CLK_LOCKED      => encoders_clk_locked,
                SERDESSTROBE    => encoders_serdesstrobe,
                HSYNC           => encoders_hsync(i),
                VSYNC           => encoders_vsync(i),
                CTL             => encoders_ctl(i),
                RGB             => encoders_rgb(i),
                AUX             => encoders_aux(i),
                ENCODING        => encoders_encoding,
                
                CHANNEL_OUT_P   => encoders_channel_out(i)(0),
                CHANNEL_OUT_N   => encoders_channel_out(i)(1)
            );
    end generate;
    
    clk_man_clk_in  <= g_clk;
    
    OSERDES_CLK_MAN_inst : entity work.OSERDES2_CLK_MAN
        generic map (
            CLK_IN_PERIOD   => g_clk_period_real,
            MULTIPLIER      => pix_clk_mult * 10,
            PREDIVISOR      => pix_clk_div,
            DIVISOR0        => 1,  -- bit clock
            DIVISOR1        => 10, -- pixel clock
            DIVISOR2        => 5,  -- serdes clock = pixel clock * 2
            DATA_CLK_SELECT => 2,  -- clock out 1
            IO_CLK_SELECT   => 0   -- clock out 2
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
        
        wait until clk_man_ioclk_locked = '1' and rising_edge(g_clk);
        
        -- synchronisation using control period
        encoders_encoding   <= "000";
        while chs_synchronized/="111" loop
            wait until rising_edge(encoders_pix_clk);
        end loop;
        
        -- dummy pixel values
        encoders_encoding   <= "010";
        for i in -255 to 255 loop
            for ch_i in 0 to 2 loop
                encoders_rgb(ch_i)  <= stdulv(abs i, 8);
            end loop;
            wait until rising_edge(encoders_pix_clk);
        end loop;
        
        wait for 10 us;
        report "NONE. All tests finished successfully."
            severity FAILURE;
    end process;
    
    ch_deser_procs_gen : for ch_i in 0 to 2 generate
        
        deser_proc : process
            constant CTL_00         : std_ulogic_vector(9 downto 0) := "1101010100";
            variable temp_data      : std_ulogic_vector(9 downto 0) := (others => '0');
            variable temp_dec_data  : std_ulogic_vector(7 downto 0) := (others => '0');
            variable counter        : signed(8 downto 0) := (others => '0');
            procedure read_data is
            begin
                for bit_i in 0 to 9 loop
                    temp_data(bit_i)    := encoders_channel_out(ch_i)(0);
                    wait until rising_edge(encoders_pix_clk_x10);
                end loop;
            end procedure;
        begin
            read_data;
            while temp_data/=CTL_00 loop
                -- bitslip
                wait until rising_edge(encoders_pix_clk_x10);
                read_data;
            end loop;
            chs_synchronized(ch_i)  <= '1';
            report "Channel " & natural'image(ch_i) & ": synchronized";
            
            counter := sig(-255, counter'length);
            
            loop
                read_data;
                while temp_data=CTL_00 loop
                    read_data;
                end loop;
                
                encoders_deser_data(ch_i)  <= temp_data;
                
                if temp_data(9) = '1' then
                    temp_data(7 downto 0)   := not temp_data(7 downto 0);
                end if;
                
                temp_dec_data(0)    := temp_data(0);
                if temp_data(8) = '1' then
                    temp_dec_data(1)    := temp_data(1) xor temp_data(0);
                    temp_dec_data(2)    := temp_data(2) xor temp_data(1);
                    temp_dec_data(3)    := temp_data(3) xor temp_data(2);
                    temp_dec_data(4)    := temp_data(4) xor temp_data(3);
                    temp_dec_data(5)    := temp_data(5) xor temp_data(4);
                    temp_dec_data(6)    := temp_data(6) xor temp_data(5);
                    temp_dec_data(7)    := temp_data(7) xor temp_data(6);
                else
                    temp_dec_data(1)    := temp_data(1) xnor temp_data(0);
                    temp_dec_data(2)    := temp_data(2) xnor temp_data(1);
                    temp_dec_data(3)    := temp_data(3) xnor temp_data(2);
                    temp_dec_data(4)    := temp_data(4) xnor temp_data(3);
                    temp_dec_data(5)    := temp_data(5) xnor temp_data(4);
                    temp_dec_data(6)    := temp_data(6) xnor temp_data(5);
                    temp_dec_data(7)    := temp_data(7) xnor temp_data(6);
                end if;
                
                encoders_dec_vid_data(ch_i) <= temp_dec_data;
                assert temp_dec_data=stdulv(abs int(counter), 8)
                    report "Counter value doesn't match!"
                    severity FAILURE;
                
                if counter=255 then
                    report "Channel " & natural'image(ch_i) & ": counter test finished successfully.";
                    wait;
                end if;
                
                counter := counter+1;
            end loop;
        end process;
        
    end generate;

END;
