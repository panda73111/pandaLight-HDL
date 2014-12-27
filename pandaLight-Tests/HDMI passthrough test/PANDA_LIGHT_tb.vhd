library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.help_funcs.all;
use work.video_profiles.all;

entity testbench is
    generic (
        HARDWARE_ENCODER    : boolean := false -- slow
    );
end testbench;

architecture behavior of testbench is

    signal g_clk20  : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    -- HDMI
    signal RX_CHANNELS_IN_P : std_ulogic_vector(7 downto 0) := x"FF";
    signal RX_CHANNELS_IN_N : std_ulogic_vector(7 downto 0) := x"FF";
    signal RX_SDA           : std_ulogic_vector(1 downto 0) := "11";
    signal RX_SCL           : std_ulogic_vector(1 downto 0) := "11";
    signal RX_CEC           : std_ulogic_vector(1 downto 0) := "11";
    signal RX_DET           : std_ulogic_vector(1 downto 0) := "00";
    signal RX_EN            : std_ulogic_vector(1 downto 0);
    
    signal TX_CHANNELS_OUT_P    : std_ulogic_vector(3 downto 0);
    signal TX_CHANNELS_OUT_N    : std_ulogic_vector(3 downto 0);
    signal TX_SDA               : std_ulogic := '1';
    signal TX_SCL               : std_ulogic := '1';
    signal TX_CEC               : std_ulogic := '1';
    signal TX_DET               : std_ulogic := '0';
    signal TX_EN                : std_ulogic;
    
    -- USB UART
    signal USB_RXD     : std_ulogic := '0';
    signal USB_TXD     : std_ulogic;
    signal USB_CTSN    : std_ulogic := '0';
    signal USB_RTSN    : std_ulogic;
    signal USB_DSRN    : std_ulogic := '0';
    signal USB_DTRN    : std_ulogic;
    signal USB_DCDN    : std_ulogic;
    signal USB_RIN     : std_ulogic;
    
    constant G_CLK20_PERIOD : time := 50 ns;
    constant PROFILE_BITS   : natural := log2(VIDEO_PROFILE_COUNT);
    
    signal vp   : video_profile_type;
    
begin
    
    g_clk20 <= not g_clk20 after G_CLK20_PERIOD/2;
    
    PANDA_LIGHT_inst : entity work.panda_light
    port map (
        CLK20   => g_clk20,
        
        RX_CHANNELS_IN_P    => RX_CHANNELS_IN_P,
        RX_CHANNELS_IN_N    => RX_CHANNELS_IN_N,
        RX_SDA              => RX_SDA,
        RX_SCL              => RX_SCL,
        RX_CEC              => RX_CEC,
        RX_DET              => RX_DET,
        RX_EN               => RX_EN,
        
        TX_CHANNELS_OUT_P   => TX_CHANNELS_OUT_P,
        TX_CHANNELS_OUT_N   => TX_CHANNELS_OUT_N,
        TX_SDA              => TX_SDA,
        TX_SCL              => TX_SCL,
        TX_CEC              => TX_CEC,
        TX_DET              => TX_DET,
        TX_EN               => TX_EN,
        
        USB_RXD     => USB_RXD,
        USB_TXD     => USB_TXD,
        USB_CTSN    => USB_CTSN,
        USB_RTSN    => USB_RTSN,
        USB_DSRN    => USB_DSRN,
        USB_DTRN    => USB_DTRN,
        USB_DCDN    => USB_DCDN,
        USB_RIN     => USB_RIN
    );
    
    HARDWARE_ENCODER_gen : if HARDWARE_ENCODER generate
        signal tfg_profile          : std_ulogic_vector(PROFILE_BITS-1 downto 0) := (others => '0');
        signal tfg_clk_out          : std_ulogic;
        signal tfg_clk_out_locked   : std_ulogic;
        signal tfg_hsync            : std_ulogic;
        signal tfg_vsync            : std_ulogic;
        signal tfg_rgb_enable       : std_ulogic;
        signal tfg_rgb              : std_ulogic_vector(23 downto 0);
        
        signal enc_rst          : std_ulogic;
        signal enc_hsync        : std_ulogic := '0';
        signal enc_vsync        : std_ulogic := '0';
        signal enc_rgb_enable   : std_ulogic := '0';
        signal enc_rgb          : std_ulogic_vector(23 downto 0) := x"000000";
        signal enc_chs_p        : std_ulogic_vector(2 downto 0);
        signal enc_chs_n        : std_ulogic_vector(2 downto 0);
        
        signal os2_pix_clk          : std_ulogic;
        signal os2_pix_clk_x2       : std_ulogic;
        signal os2_pix_clk_x10      : std_ulogic;
        signal os2_pix_clk_locked   : std_ulogic;
        signal os2_serdesstrobe     : std_ulogic;
    begin
        
        RX_CHANNELS_IN_P(3)             <= os2_pix_clk;
        RX_CHANNELS_IN_N(3)             <= not os2_pix_clk;
        RX_CHANNELS_IN_P(2 downto 0)    <= enc_chs_p;
        RX_CHANNELS_IN_N(2 downto 0)    <= enc_chs_n;
        
        vp  <= video_profiles(nat(tfg_profile));
        
        TEST_FRAME_GEN_inst : entity work.TEST_FRAME_GEN
            generic map (
                CLK_IN_PERIOD   => 50.0
            )
            port map (
                CLK_IN  => g_clk20,
                RST     => g_rst,
                
                PROFILE => tfg_profile,
                
                CLK_OUT         => tfg_clk_out,
                CLK_OUT_LOCKED  => tfg_clk_out_locked,
                
                hsync       => tfg_hsync,
                vsync       => tfg_vsync,
                RGB_ENABLE  => tfg_rgb_enable,
                RGB         => tfg_rgb
            );
        
        TMDS_ENCODER_inst : entity work.TMDS_ENCODER
            port map (
                PIX_CLK     => os2_pix_clk,
                PIX_CLK_X2  => os2_pix_clk_x2,
                PIX_CLK_X10 => os2_pix_clk_x10,
                RST         => enc_rst,
                
                SERDESSTROBE    => os2_serdesstrobe,
                CLK_LOCKED      => os2_pix_clk_locked,
                
                HSYNC       => enc_hsync,
                VSYNC       => enc_vsync,
                RGB         => enc_rgb,
                RGB_ENABLE  => enc_rgb_enable,
                AUX         => (others => '0'),
                AUX_ENABLE  => '0',
                
                CHANNELS_OUT_P  => enc_chs_p,
                CHANNELS_OUT_N  => enc_chs_n
            );
        
        OSERDES2_CLK_MAN_inst : entity work.OSERDES2_CLK_MAN
            generic map (
                CLK_IN_PERIOD   => 13.5, -- 720p60
                MULTIPLIER      => 10,
                DIVISOR0        => 1,
                DIVISOR1        => 10,
                DIVISOR2        => 5,
                DATA_CLK_SELECT => 2,
                IO_CLK_SELECT   => 0
            )
            port map (
                CLK_IN  => tfg_clk_out,
                
                CLK_OUT1        => os2_pix_clk,
                CLK_OUT2        => os2_pix_clk_x2,
                IOCLK_OUT       => os2_pix_clk_x10,
                IOCLK_LOCKED    => os2_pix_clk_locked,
                SERDESSTROBE    => os2_serdesstrobe
            );
        
        enc_sync_proc : process(os2_pix_clk)
        begin
            if rising_edge(os2_pix_clk) then
                enc_hsync       <= tfg_hsync;
                enc_vsync       <= tfg_vsync;
                enc_rgb_enable  <= tfg_rgb_enable;
                enc_rgb         <= tfg_rgb;
            end if;
        end process;
        
        process
        begin
            g_rst   <= '1';
            enc_rst <= '1';
            wait for 200 ns;
            g_rst   <= '0';
            
            wait until os2_pix_clk_locked='1';
            enc_rst <= '0';
            wait for 200 ns;
            RX_DET  <= "01";
            
            wait;
        end process;
    
    end generate;
    
    not_HARDWARE_ENCODER_gen : if not HARDWARE_ENCODER generate
        
        test_tmds_encoder_inst : entity work.test_tmds_encoder
            port map (
                CHANNELS_OUT_P  => RX_CHANNELS_IN_P(3 downto 0),
                CHANNELS_OUT_N  => RX_CHANNELS_IN_N(3 downto 0)
            );
        
    end generate;
    
end;