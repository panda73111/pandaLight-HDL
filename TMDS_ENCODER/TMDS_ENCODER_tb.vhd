--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   23:50:05 12/20/2014
-- Module Name:   TMDS_ENCODER_tb
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: TMDS_ENCODER
-- 
-- Additional Comments:
--
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;
use work.video_profiles.all;

ENTITY TMDS_ENCODER_tb IS
    generic (
        FIRST_PROFILE   : natural := 0;
        LAST_PROFILE    : natural := VIDEO_PROFILE_COUNT-1;
        FRAME_COUNT     : natural := 5; -- frames of each video resolution
        FRAME_STEP      : natural := 0; -- swtitch pattern every frame
        PROFILE_BITS    : natural := log2(VIDEO_PROFILE_COUNT);
        X_BITS          : natural := 12;
        Y_BITS          : natural := 12
    );
END TMDS_ENCODER_tb;

ARCHITECTURE rtl OF TMDS_ENCODER_tb IS 
    
    --------------------------
    ------ TMDS encoder ------
    --------------------------
    
    -- Inputs
    signal PIX_CLK      : std_ulogic := '0';
    signal PIX_CLK_X2   : std_ulogic := '0';
    signal PIX_CLK_X10  : std_ulogic := '0';
    signal RST          : std_ulogic := '0';
    
    signal SERDESSTROBE : std_ulogic := '0';
    signal CLK_LOCKED   : std_ulogic := '0';
    
    signal HSYNC        : std_ulogic := '0';
    signal VSYNC        : std_ulogic := '0';
    signal RGB          : std_ulogic_vector(23 downto 0) := x"000000";
    signal RGB_ENABLE   : std_ulogic := '0';
    signal AUX          : std_ulogic_vector(8 downto 0) := (others => '0');
    signal AUX_ENABLE   : std_ulogic := '0';
    
    -- Outputs
    signal CHANNELS_OUT_P   : std_ulogic_vector(2 downto 0);
    signal CHANNELS_OUT_N   : std_ulogic_vector(2 downto 0);
    
    
    ----------------------------
    --- test frame generator ---
    ----------------------------
    
    signal profile  : std_ulogic_vector(PROFILE_BITS-1 downto 0) := (others => '0');
    
    signal tfg_clk_out          : std_ulogic := '0';
    signal tfg_clk_out_locked   : std_ulogic := '0';
    
    
    -- Clock period definitions
    constant g_clk_period       : time := 50 ns; -- 20 MHz
    constant g_clk_period_real  : real := real(g_clk_period / 1 ps) / real(1 ns / 1 ps);
    
    signal g_clk    : std_ulogic := '0';
    
    signal vp   : video_profile_type;
    
    signal pixclk_hsync     : std_ulogic := '0';
    signal pixclk_vsync     : std_ulogic := '0';
    signal pixclk_rgb_en    : std_ulogic := '0';
    signal pixclk_rgb       : std_ulogic_vector(23 downto 0) := x"000000";

BEGIN
    
    vp  <= VIDEO_PROFILES(int(profile));
    
    TMDS_ENCODER_inst : entity work.TMDS_ENCODER
        port map (
            PIX_CLK     => PIX_CLK,
            PIX_CLK_X2  => PIX_CLK_X2,
            PIX_CLK_X10 => PIX_CLK_X10,
            RST         => RST or not CLK_LOCKED,
            
            SERDESSTROBE    => SERDESSTROBE,
            CLK_LOCKED      => CLK_LOCKED,
            
            HSYNC       => pixclk_hsync,
            VSYNC       => pixclk_vsync,
            RGB         => pixclk_rgb,
            RGB_ENABLE  => pixclk_rgb_en,
            AUX         => (others => '0'),
            AUX_ENABLE  => '0',
            
            CHANNELS_OUT_P  => CHANNELS_OUT_P,
            CHANNELS_OUT_N  => CHANNELS_OUT_N
        );
    
    OSERDES_CLK_MAN_inst : entity work.OSERDES2_CLK_MAN
        generic map (
            CLK_IN_PERIOD   => 13.5, -- 720p60
            MULTIPLIER      => 10,
            DIVISOR0        => 1,    -- bit clock
            DIVISOR1        => 10,   -- pixel clock
            DIVISOR2        => 5,    -- serdes clock = pixel clock * 2
            DATA_CLK_SELECT => 2,    -- clock out 1
            IO_CLK_SELECT   => 0     -- clock out 2
        )
        port map (
            CLK_IN          => tfg_clk_out,
            
            CLK_OUT1        => PIX_CLK,
            CLK_OUT2        => PIX_CLK_X2,
            IOCLK_OUT       => PIX_CLK_X10,
            IOCLK_LOCKED    => CLK_LOCKED,
            SERDESSTROBE    => SERDESSTROBE
        );
    
    TEST_FRAME_GEN_inst : entity work.TEST_FRAME_GEN
        generic map (
            CLK_IN_PERIOD   => g_clk_period_real,
            FRAME_STEP      => FRAME_STEP,
            PROFILE_BITS    => PROFILE_BITS,
            X_BITS          => X_BITS,
            Y_BITS          => Y_BITS
        )
        port map (
            CLK_IN  => g_clk,
            RST     => RST,
            
            PROFILE => profile,
            
            CLK_OUT         => tfg_clk_out,
            CLK_OUT_LOCKED  => tfg_clk_out_locked,
            
            HSYNC       => HSYNC,
            VSYNC       => VSYNC,
            RGB_ENABLE  => RGB_ENABLE,
            RGB         => RGB
        );
    
    
    g_clk   <= not g_clk after g_clk_period/2;
    
    sync_proc : process(PIX_CLK)
    begin
        if rising_edge(PIX_CLK) then
            pixclk_hsync    <= HSYNC;
            pixclk_vsync    <= VSYNC;
            pixclk_rgb_en   <= RGB_ENABLE;
            pixclk_rgb      <= RGB;
        end if;
    end process;
    
    -- Stimulus process
    stim_proc: process
    begin		
        -- hold reset state for 100 ns.
        RST <= '1';
        wait for 1 us;
        RST <= '0';
        wait for 100 ns;
        wait until rising_edge(g_clk);

        -- insert stimulus here
        
        wait until rising_edge(CLK_LOCKED);
        
        for profile_i in FIRST_PROFILE to LAST_PROFILE loop
            report "Setting profile " & natural'image(profile_i);
            profile <= stdulv(profile_i, PROFILE_BITS);
            
            wait until rising_edge(CLK_LOCKED);
            for frame_i in 0 to FRAME_COUNT loop
                wait until VSYNC'event;
                wait until VSYNC'event;
            end loop;
        end loop;
        
        wait for 10 us;
        report "NONE. All tests finished successfully."
            severity FAILURE;
    end process;

END;
