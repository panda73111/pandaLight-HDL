----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    21:49:35 07/28/2014 
-- Module Name:    PANDA_LIGHT - rtl 
-- Project Name:   PANDA_LIGHT
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity PANDA_LIGHT is
    generic (
        G_CLK_MULT      : natural range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV       : natural range 1 to 256 := 2;
        G_CLK_PERIOD    : real := 20.0; -- 50 MHz in nano seconds
        HOR_LED_COUNT   : natural :=  13;
        VER_LED_COUNT   : natural :=   7;
        PAUSE_CYCLES    : natural := 416_666-50; -- 120 Hz
        START_LED_NUM   : natural :=  10;
        FRAME_DELAY     : natural := 120
    );
    port (
        CLK20   : in std_ulogic;
        
        -- LEDs
        LEDS_CLK    : out std_ulogic_vector(1 downto 0) := "00";
        LEDS_DATA   : out std_ulogic_vector(1 downto 0) := "00";
        
        -- PMOD
        PMOD0   : out std_ulogic_vector(3 downto 0) := "0000"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_stopped    : std_ulogic := '0';
    
    
    ----------------------
    --- LED correction ---
    ----------------------
    
    signal lcor_clk : std_ulogic := '0';
    signal lcor_rst : std_ulogic := '0';
    
    signal lcor_cfg_addr    : std_ulogic_vector(9 downto 0) := (others => '0');
    signal lcor_cfg_wr_en   : std_ulogic := '0';
    signal lcor_cfg_data    : std_ulogic_vector(7 downto 0) := x"00";
    
    signal lcor_led_in_vsync        : std_ulogic := '0';
    signal lcor_led_in_num          : std_ulogic_vector(7 downto 0) := x"FF";
    signal lcor_led_in_rgb          : std_ulogic_vector(23 downto 0) := x"000000";
    signal lcor_led_in_rgb_wr_en    : std_ulogic := '0';
    
    signal lcor_led_out_vsync       : std_ulogic := '0';
    signal lcor_led_out_rgb         : std_ulogic_vector(23 downto 0) := x"000000";
    signal lcor_led_out_rgb_valid   : std_ulogic := '0';
    
    
    -------------------
    --- LED control ---
    -------------------
    
    signal lctrl_clk    : std_ulogic := '0';
    signal lctrl_rst    : std_ulogic := '0';
    
    signal lctrl_mode   : std_ulogic_vector(1 downto 0) := "00";
    
    signal lctrl_led_vsync      : std_ulogic := '0';
    signal lctrl_led_rgb        : std_ulogic_vector(23 downto 0) := x"000000";
    signal lctrl_led_rgb_wr_en  : std_ulogic := '0';
    
    signal lctrl_leds_clk   : std_ulogic := '0';
    signal lctrl_leds_data  : std_ulogic := '0';
    
    
    --------------------
    --- configurator ---
    --------------------
    
    -- Inputs
    signal conf_clk : std_ulogic := '0';
    signal conf_rst : std_ulogic := '0';
    
    signal conf_calculate           : std_ulogic := '0';
    signal conf_configure_ledcor    : std_ulogic := '0';
    signal conf_configure_ledex     : std_ulogic := '0';
    
    signal conf_frame_width     : std_ulogic_vector(10 downto 0) := (others => '0');
    signal conf_frame_height    : std_ulogic_vector(10 downto 0) := (others => '0');
    
    signal conf_settings_wr_en  : std_ulogic := '0';
    signal conf_settings_data   : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal conf_cfg_sel_ledcor  : std_ulogic := '0';
    signal conf_cfg_sel_ledex   : std_ulogic := '0';
    
    signal conf_cfg_addr        : std_ulogic_vector(9 downto 0) := (others => '0');
    signal conf_cfg_wr_en       : std_ulogic := '0';
    signal conf_cfg_data        : std_ulogic_vector(7 downto 0) := x"00";
    
    signal conf_idle    : std_ulogic := '0';
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLK_MAN_inst : entity work.CLK_MAN
        generic map (
            CLK_IN_PERIOD   => 50.0, -- 20 MHz in nano seconds
            MULTIPLIER      => G_CLK_MULT,
            DIVISOR         => G_CLK_DIV
        )
        port map (
            RST => '0',
            
            CLK_IN          => CLK20,
            CLK_OUT         => g_clk,
            CLK_OUT_STOPPED => g_clk_stopped
        );
    
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    g_rst   <= g_clk_stopped;
    
    LEDS_CLK    <= lctrl_leds_clk & lctrl_leds_clk;
    LEDS_DATA   <= lctrl_leds_data & lctrl_leds_data;
    
    PMOD0(0)    <= '0';
    PMOD0(1)    <= '0';
    PMOD0(2)    <= '0';
    PMOD0(3)    <= '0';
    
    
    ----------------------
    --- LED correction ---
    ----------------------
    
    lcor_clk    <= g_clk;
    lcor_rst    <= g_rst or conf_cfg_sel_ledcor;
    
    lcor_cfg_addr   <= conf_cfg_addr(lcor_cfg_addr'range);
    lcor_cfg_wr_en  <= conf_cfg_wr_en and conf_cfg_sel_ledcor;
    lcor_cfg_data   <= conf_cfg_data;
    
    LED_CORRECTION_inst : entity work.LED_CORRECTION
        generic map (
            MAX_LED_COUNT   => 128,
            MAX_FRAME_COUNT => 128
        )
        port map (
            CLK => lcor_clk,
            RST => lcor_rst,
            
            CFG_ADDR    => lcor_cfg_addr,
            CFG_WR_EN   => lcor_cfg_wr_en,
            CFG_DATA    => lcor_cfg_data,
            
            LED_IN_VSYNC        => lcor_led_in_vsync,
            LED_IN_NUM          => lcor_led_in_num,
            LED_IN_RGB          => lcor_led_in_rgb,
            LED_IN_RGB_WR_EN    => lcor_led_in_rgb_wr_en,
            
            LED_OUT_VSYNC       => lcor_led_out_vsync,
            LED_OUT_RGB         => lcor_led_out_rgb,
            LED_OUT_RGB_VALID   => lcor_led_out_rgb_valid
        );
    
    LED_CORRECTION_TEST_gen : if true generate
        constant LED_COUNT      : natural := 2*(HOR_LED_COUNT+VER_LED_COUNT);
        constant LED_BITS       : natural := log2(LED_COUNT)+1;
        constant PAUSE_BITS     : natural := log2(PAUSE_CYCLES)+1;
        
        type state_type is (
            WRITING_LEDS,
            PAUSING
        );
        signal state        : state_type := WRITING_LEDS;
        signal leds_left    : unsigned(LED_BITS-1 downto 0) := uns(LED_COUNT-2, LED_BITS);
        signal pause_left   : unsigned(PAUSE_BITS-1 downto 0) := uns(PAUSE_CYCLES-2, PAUSE_BITS);
        signal start_color  : std_ulogic_vector(23 downto 0) := x"000000";
    begin
        
        led_ctrl_test_proc : process(g_clk, g_rst)
        begin
            if g_rst='1' then
                state               <= WRITING_LEDS;
                
                lcor_led_in_vsync       <= '0';
                lcor_led_in_num         <= x"FF";
                lcor_led_in_rgb         <= x"000000";
                lcor_led_in_rgb_wr_en   <= '0';
                
                leds_left           <= uns(LED_COUNT-2, LED_BITS);
                pause_left          <= uns(PAUSE_CYCLES-2, PAUSE_BITS);
                start_color         <= x"000000";
            elsif rising_edge(g_clk) then
                lcor_led_in_vsync       <= '0';
                lcor_led_in_rgb_wr_en   <= '0';
                
                case state is
                    
                    when WRITING_LEDS =>
                        lcor_led_in_num         <= lcor_led_in_num+1;
                        lcor_led_in_rgb         <= lcor_led_in_rgb+5;
                        lcor_led_in_rgb_wr_en   <= '1';
                        leds_left               <= leds_left-1;
                        pause_left              <= uns(PAUSE_CYCLES-2, PAUSE_BITS);
                        if leds_left(leds_left'high)='1' then
                            -- mark the last LED red
                            lcor_led_in_rgb <= x"FF0000";
                            state           <= PAUSING;
                        end if;
                    
                    when PAUSING =>
                        lcor_led_in_vsync   <= '1';
                        lcor_led_in_num     <= x"FF";
                        lcor_led_in_rgb     <= start_color;
                        pause_left          <= pause_left-1;
                        leds_left           <= uns(LED_COUNT-2, LED_BITS);
                        if pause_left(pause_left'high)='1' then
                            start_color <= start_color+(LED_COUNT*5);
                            state       <= WRITING_LEDS;
                        end if;
                    
                end case;
            end if;
        end process;
    
    end generate;
    
    
    ------------------
    -- LED control ---
    ------------------
    
    lctrl_clk   <= g_clk;
    lctrl_rst   <= g_rst;
    
    lctrl_mode  <= "00";
    
    lctrl_led_vsync     <= lcor_led_out_vsync;
    lctrl_led_rgb       <= lcor_led_out_rgb;
    lctrl_led_rgb_wr_en <= lcor_led_out_rgb_valid;
    
    LED_CONTROL_inst : entity work.LED_CONTROL
        generic map (
            CLK_IN_PERIOD           => G_CLK_PERIOD,
            WS2801_LEDS_CLK_PERIOD  => 1000.0 -- 1 MHz
        )
        port map (
            CLK => lctrl_clk,
            RST => lctrl_rst,
            
            MODE    => lctrl_mode,
            
            LED_VSYNC       => lctrl_led_vsync,
            LED_RGB         => lctrl_led_rgb,
            LED_RGB_WR_EN   => lctrl_led_rgb_wr_en,
            
            LEDS_CLK    => lctrl_leds_clk,
            LEDS_DATA   => lctrl_leds_data
        );
    
    
    -------------------
    -- configurator ---
    -------------------
    
    conf_clk    <= g_clk;
    conf_rst    <= g_rst;
    
    CONFIGURATOR_inst : entity work.CONFIGURATOR
        port map (
            CLK => conf_clk,
            RST => conf_rst,
            
            CALCULATE           => conf_calculate,
            CONFIGURE_LEDCOR    => conf_configure_ledcor,
            CONFIGURE_LEDEX     => conf_configure_ledex,
            
            FRAME_WIDTH     => conf_frame_width,
            FRAME_HEIGHT    => conf_frame_height,
            
            SETTINGS_WR_EN  => conf_settings_wr_en,
            SETTINGS_DATA   => conf_settings_data,
            
            CFG_SEL_LEDCOR  => conf_cfg_sel_ledcor,
            CFG_SEL_LEDEX   => conf_cfg_sel_ledex,
            
            CFG_ADDR    => conf_cfg_addr,
            CFG_WR_EN   => conf_cfg_wr_en,
            CFG_DATA    => conf_cfg_data,
            
            IDLE    => conf_idle
        );
    
    configurator_stim_gen : if true generate
        type led_lookup_table_type is
            array(0 to 255) of
            std_ulogic_vector(7 downto 0);
        
        type state_type is (
            INIT,
            SENDING_SETTINGS,
            CALCULATING,
            CONF_LEDCOR_WAITING_FOR_BUSY,
            CONF_LEDCOR_WAITING_FOR_IDLE,
            CONF_LEDCOR_CONFIGURING_LED_CORRECTION,
            IDLE
        );
        
        signal state    : state_type := INIT;
        signal counter  : unsigned(9 downto 0) := (others => '1');
        
        function calc_gamma_cor_value(i : natural; y : real)
            return natural is
        begin
            return natural(255.0 * ((real(i) / 255.0) ** y));
        end function;
        
        function calc_gamma_cor_table(y : real)
            return led_lookup_table_type
        is
            variable t  : led_lookup_table_type;
        begin
            for i in 0 to 255 loop
                t(i)    := stdulv(calc_gamma_cor_value(i, y), 8);
            end loop;
            return t;
        end function;
        
        constant R_LOOKUP_TABLE : led_lookup_table_type := calc_gamma_cor_table(2.0);
        constant G_LOOKUP_TABLE : led_lookup_table_type := calc_gamma_cor_table(2.0);
        constant B_LOOKUP_TABLE : led_lookup_table_type := calc_gamma_cor_table(2.0);
    begin
        
        conf_frame_width    <= stdulv(640, 11);
        conf_frame_height   <= stdulv(480, 11);
        
        configurator_stim_proc : process(g_clk, g_rst)
        begin
            if g_rst='1' then
                conf_settings_wr_en     <= '0';
                conf_settings_data      <= x"00";
                conf_calculate          <= '0';
                conf_configure_ledcor   <= '0';
                counter                 <= (others => '1');
            elsif rising_edge(g_clk) then
                conf_settings_wr_en     <= '0';
                conf_calculate          <= '0';
                conf_configure_ledcor   <= '0';
                
                case state is
                    
                    when INIT =>
                        state   <= SENDING_SETTINGS;
                    
                    when SENDING_SETTINGS =>
                        counter             <= counter+1;
                        conf_settings_wr_en <= '1';
                        case counter+1 is
                            when "0000000000"   =>  conf_settings_data  <= stdulv(HOR_LED_COUNT, 8);
                            when "0000000001"   =>  conf_settings_data  <= x"00";
                            when "0000000010"   =>  conf_settings_data  <= x"00";
                            when "0000000011"   =>  conf_settings_data  <= x"00";
                            when "0000000100"   =>  conf_settings_data  <= x"00";
                            when "0000000101"   =>  conf_settings_data  <= x"00";
                            when "0000000110"   =>  conf_settings_data  <= stdulv(VER_LED_COUNT, 8);
                            when "0000000111"   =>  conf_settings_data  <= x"00";
                            when "0000001000"   =>  conf_settings_data  <= x"00";
                            when "0000001001"   =>  conf_settings_data  <= x"00";
                            when "0000001010"   =>  conf_settings_data  <= x"00";
                            when "0000001011"   =>  conf_settings_data  <= x"00";
                            when "0000001100"   =>  conf_settings_data  <= stdulv(START_LED_NUM, 8);
                            when "0000001101"   =>  conf_settings_data  <= stdulv(FRAME_DELAY, 8);
                            when "0000001110"   =>  conf_settings_data  <= x"00";
                            when others         =>
                                                    if counter < 256+14 then
                                                        conf_settings_data  <= R_LOOKUP_TABLE(nat(counter-14));
                                                    elsif counter < 2*256+14 then
                                                        conf_settings_data  <= G_LOOKUP_TABLE(nat(counter-256-14));
                                                    elsif counter < 3*256+14 then
                                                        conf_settings_data  <= B_LOOKUP_TABLE(nat(counter-2*256-14));
                                                    else
                                                        state   <= CALCULATING;
                                                    end if;
                        end case;
                    
                    when CALCULATING =>
                        conf_calculate  <= '1';
                        state           <= CONF_LEDCOR_WAITING_FOR_BUSY;
                    
                    when CONF_LEDCOR_WAITING_FOR_BUSY =>
                        if conf_idle='0' then
                            state   <= CONF_LEDCOR_WAITING_FOR_IDLE;
                        end if;
                    
                    when CONF_LEDCOR_WAITING_FOR_IDLE =>
                        if conf_idle='1' then
                            state   <= CONF_LEDCOR_CONFIGURING_LED_CORRECTION;
                        end if;
                    
                    when CONF_LEDCOR_CONFIGURING_LED_CORRECTION =>
                        conf_configure_ledcor   <= '1';
                        state                   <= IDLE;
                    
                    when IDLE =>
                        null;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
end rtl;

