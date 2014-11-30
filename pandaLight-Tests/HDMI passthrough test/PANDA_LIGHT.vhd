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
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;
use work.txt_util.all;

entity PANDA_LIGHT is
    generic (
        G_CLK_MULT          : natural := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV           : natural := 2;
        G_CLK_PERIOD        : real := 20.0; -- 50 MHz in nano seconds
        RX_SEL              : natural := 1;
        RX0_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"000000";
        RX1_BITFILE_ADDR    : std_ulogic_vector(23 downto 0) := x"060000";
        UART_DEBUG          : boolean := true
    );
    port (
        CLK20   : in std_ulogic;
        
        -- HDMI
        RX_CHANNELS_IN_P    : in std_ulogic_vector(7 downto 0);
        RX_CHANNELS_IN_N    : in std_ulogic_vector(7 downto 0);
        RX_SDA              : inout std_ulogic_vector(1 downto 0) := "ZZ";
        RX_SCL              : inout std_ulogic_vector(1 downto 0) := "ZZ";
        RX_CEC              : inout std_ulogic_vector(1 downto 0) := "ZZ";
        RX_DET              : in std_ulogic_vector(1 downto 0);
        RX_EN               : out std_ulogic_vector(1 downto 0) := "00";
        
        TX_CHANNELS_OUT_P   : out std_ulogic_vector(3 downto 0) := "1111";
        TX_CHANNELS_OUT_N   : out std_ulogic_vector(3 downto 0) := "1111";
        TX_SDA              : inout std_ulogic := 'Z';
        TX_SCL              : inout std_ulogic := 'Z';
        TX_CEC              : inout std_ulogic := 'Z';
        TX_DET              : in std_ulogic := '0';
        TX_EN               : out std_ulogic := '0';
        
        -- USB UART
        USB_RXD     : in std_ulogic;
        USB_TXD     : out std_ulogic := '0';
        USB_CTSN    : in std_ulogic;
        USB_RTSN    : out std_ulogic := '0';
        USB_DSRN    : in std_ulogic;
        USB_DTRN    : out std_ulogic := '0';
        USB_DCDN    : out std_ulogic := '0';
        USB_RIN     : out std_ulogic := '0'
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    type rx_bitfile_addrs_type is array(0 to 1)
        of std_ulogic_vector(23 downto 0);
    
    constant rx_bitfile_addrs   : rx_bitfile_addrs_type := (
        RX0_BITFILE_ADDR,
        RX1_BITFILE_ADDR
    );
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_stopped    : std_ulogic := '0';
    
    
    ----------------------------
    --- HDMI related signals ---
    ----------------------------
    
    signal rx_det_stable    : std_ulogic_vector(1 downto 0) := "00";
    signal rx_det_stable_q  : std_ulogic_vector(1 downto 0) := "00";
    signal tx_det_stable    : std_ulogic := '0';
    
    signal rx_channels_in   : std_ulogic_vector(7 downto 0) := x"00";
    signal tx_channels_out  : std_ulogic_vector(3 downto 0) := "0000";
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    -- Inputs
    signal rxclk_clk_in : std_ulogic := '0';
    attribute keep of rxclk_clk_in : signal is true;
    
    -- Outputs
    signal rxclk_clk_out1       : std_ulogic := '0';
    signal rxclk_clk_out2       : std_ulogic := '0';
    signal rxclk_ioclk_out      : std_ulogic := '0';
    signal rxclk_ioclk_locked   : std_ulogic := '0';
    signal rxclk_serdesstrobe   : std_ulogic := '0';
    
    
    -----------------------
    --- RX HDMI Decoder ---
    -----------------------
    
    -- Inputs
    signal rx_pix_clk       : std_ulogic := '0';
    signal rx_pix_clk_x2    : std_ulogic := '0';
    signal rx_pix_clk_x10   : std_ulogic := '0';
    signal rx_rst           : std_ulogic := '0';
    
    signal rx_clk_locked    : std_ulogic := '0';
    signal rx_serdesstrobe  : std_ulogic := '0';
    
    -- Outputs
    signal rx_enc_data          : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rx_enc_data_valid    : std_ulogic := '0';
    
    signal rx_vsync             : std_ulogic := '0';
    signal rx_hsync             : std_ulogic := '0';
    signal rx_rgb               : std_ulogic_vector(23 downto 0) := x"000000";
    signal rx_aux_data          : std_ulogic_vector(8 downto 0) := (others => '0');
    signal rx_aux_data_valid    : std_ulogic := '0';
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    -- Inputs
    signal rxpt_pix_clk : std_ulogic := '0';
    signal rxpt_rst     : std_ulogic := '0';
    
    -- Outputs
    signal rxpt_rx_enc_data         : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rxpt_rx_enc_data_valid   : std_ulogic := '0';
    
    signal rxpt_tx_channels_out : std_ulogic_vector(3 downto 0) := "0000";
    
    
    -----------------------------
    --- IPROG reconfiguration ---
    -----------------------------
    
    -- Inputs
    signal iprog_clk    : std_ulogic := '0';
    signal iprog_en     : std_ulogic := '0';
    
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
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- only enabled chips make 'DET' signals possible!
    RX_EN(RX_SEL)   <= tx_det_stable;
    RX_EN(1-RX_SEL) <= tx_det_stable;
    TX_EN           <= '1';
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    rx_DEBOUNCE_gen : for i in 0 to 1 generate
        
        rx_det_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 1000
            )
            port map (
                CLK => g_clk,
                
                I   => RX_DET(i),
                O   => rx_det_stable(i)
            );
    
    end generate;
        
    tx_det_DEBOUNCE_inst : entity work.DEBOUNCE
        generic map (
            CYCLE_COUNT => 1000
        )
        port map (
            CLK => g_clk,
            
            I   => TX_DET,
            O   => tx_det_stable
        );
    
    diff_IBUFDS_gen : for i in 0 to 7 generate
        
        rx_channel_IBUFDS_inst : IBUFDS
            generic map (DIFF_TERM  => false)
            port map (
                I   => RX_CHANNELS_IN_P(i),
                IB  => RX_CHANNELS_IN_N(i),
                O   => rx_channels_in(i)
            );
        
    end generate;
    
    diff_OBUFDS_gen : for i in 0 to 3 generate
        
        tx_channel_OBUFDS_inst : OBUFDS
            port map (
                I   => tx_channels_out(i),
                O   => TX_CHANNELS_OUT_P(i),
                OB  => TX_CHANNELS_OUT_N(i)
            );
        
    end generate;
    
    
    ----------------------------
    --- HDMI DDC passthrough ---
    ----------------------------
    
    scl_BIDIR_REPEAT_BUFFER_inst : entity work.BIDIR_REPEAT_BUFFER
        generic map (
            PULL    => "UP",
            FLOAT   => true
        )
        port map (
            CLK => g_clk,
            
            P0_IN   => RX_SCL(RX_SEL),
            P0_OUT  => RX_SCL(RX_SEL),
            P1_IN   => TX_SCL,
            P1_OUT  => TX_SCL
        );
    
    sda_BIDIR_REPEAT_BUFFER_inst : entity work.BIDIR_REPEAT_BUFFER
        generic map (
            PULL => "UP",
            FLOAT   => true
        )
        port map (
            CLK => g_clk,
            
            P0_IN   => RX_SDA(RX_SEL),
            P0_OUT  => RX_SDA(RX_SEL),
            P1_IN   => TX_SDA,
            P1_OUT  => TX_SDA
        );
    
    
    ----------------------------------
    --- HDMI ISerDes clock manager ---
    ----------------------------------
    
    rxclk_clk_in    <= rx_channels_in(RX_SEL*4 + 3);

    ISERDES2_CLK_MAN_inst : entity work.ISERDES2_CLK_MAN
        generic map (
            MULTIPLIER      => 10,
            CLK_IN_PERIOD   => 13.0, -- only for testing
            DIVISOR0        => 1,    -- bit clock
            DIVISOR1        => 5,    -- serdes clock = pixel clock * 2
            DIVISOR2        => 10,   -- pixel clock
            DATA_CLK_SELECT => 1,    -- clock out 1
            IO_CLK_SELECT   => 0     -- clock out 0
        )
        port map (
            CLK_IN          => rxclk_clk_in,
            CLK_OUT1        => rxclk_clk_out1,
            CLK_OUT2        => rxclk_clk_out2,
            IOCLK_OUT       => rxclk_ioclk_out,
            IOCLK_LOCKED    => rxclk_ioclk_locked,
            SERDESSTROBE    => rxclk_serdesstrobe
        );
    
    
    --------------------
    --- HDMI Decoder ---
    --------------------
    
    rx_pix_clk          <= rxclk_clk_out2;
    rx_pix_clk_x2       <= rxclk_clk_out1;
    rx_pix_clk_x10      <= rxclk_ioclk_out;
    rx_rst              <= not tx_det_stable;
    rx_clk_locked       <= rxclk_ioclk_locked;
    rx_serdesstrobe     <= rxclk_serdesstrobe;
    
    TMDS_DECODER_inst : entity work.TMDS_DECODER
        port map (
            PIX_CLK         => rx_pix_clk,
            PIX_CLK_X2      => rx_pix_clk_x2,
            PIX_CLK_X10     => rx_pix_clk_x10,
            RST             => rx_rst,
            
            CLK_LOCKED      => rx_clk_locked,
            SERDESSTROBE    => rx_serdesstrobe,
            
            CHANNELS_IN => rx_channels_in(RX_SEL*4 + 2 downto RX_SEL*4),
            
            ENC_DATA        => rx_enc_data,
            ENC_DATA_VALID  => rx_enc_data_valid,
            
            VSYNC           => rx_vsync,
            HSYNC           => rx_hsync,
            RGB             => rx_rgb,
            AUX_DATA        => rx_aux_data,
            AUX_DATA_VALID  => rx_aux_data_valid
        );
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    rxpt_pix_clk    <= rx_pix_clk;
    rxpt_rst        <= rx_rst;
    
    rxpt_rx_enc_data        <= rx_enc_data;
    rxpt_rx_enc_data_valid  <= rx_enc_data_valid;
    
    TMDS_PASSTHROUGH_inst : entity work.TMDS_PASSTHROUGH
        port map (
            PIX_CLK => rxpt_pix_clk,
            RST     => rxpt_rst,
            
            RX_ENC_DATA         => rxpt_rx_enc_data,
            RX_ENC_DATA_VALID   => rxpt_rx_enc_data_valid,
            
            TX_CHANNELS_OUT => rxpt_tx_channels_out
        );
    
    
    -----------------------------
    --- IPROG reconfiguration ---
    -----------------------------
    
    iprog_clk   <= g_clk;
    
    iprog_enable_proc : process(g_clk)
    begin
        if rising_edge(g_clk) then
            -- switch the bitfile if the inactive RX port gets connected
            iprog_en        <= rx_det_stable(1-RX_SEL) and not rx_det_stable_q(1-RX_SEL);
            rx_det_stable_q <= rx_det_stable;
        end if;
    end process;
    
    
    IPROG_RECONF_inst : entity work.iprog_reconf
        generic map (
            START_ADDR      => rx_bitfile_addrs(1-RX_SEL),
            FALLBACK_ADDR   => rx_bitfile_addrs(RX_SEL)
        )
        port map (
            CLK => iprog_clk,
            
            EN  => iprog_en
        );
    
    
    UART_DEBUG_gen : if UART_DEBUG generate
        constant BOOT_DELAY_CYCLES  : natural := 1000;
        constant STATUS_MSG_CYCLES  : natural := 50_000_000; -- 1 sec
        
        type state_type is (
            WAIT_FOR_BOOT,
            PRINT_BOOT_MSG,
            IDLE,
            PRINT_STATUS
        );
        signal state            : state_type := WAIT_FOR_BOOT;
        signal boot_msg_delay   : natural range 0 to BOOT_DELAY_CYCLES-1 := 0;
        signal cycle_cnt        : natural range 0 to STATUS_MSG_CYCLES-1 := 0;
        
        -- Inputs
        signal dbg_clk  : std_ulogic := '0';
        signal dbg_rst  : std_ulogic := '0';
        
        signal dbg_msg      : string(1 to 128) := (others => nul);
        signal dbg_wr_en    : std_ulogic := '0';
        signal dbg_cts      : std_ulogic := '0';
        
        -- Outputs
        signal dbg_busy : std_ulogic := '0';
        signal dbg_full : std_ulogic := '0';
        signal dbg_txd  : std_ulogic := '0';
    begin
        
        USB_TXD     <= dbg_txd;
        USB_RTSN    <= dbg_full;
        
        
        ------------------
        --- UART debug ---
        ------------------
        
        dbg_clk <= g_clk;
        dbg_rst <= g_rst;
        
        dbg_cts <= not USB_CTSN;
        
        process(g_rst, g_clk)
        begin
            if g_rst='1' then
                dbg_wr_en       <= '0';
                state           <= WAIT_FOR_BOOT;
                boot_msg_delay  <= 0;
                cycle_cnt       <= 0;
            elsif rising_edge(g_clk) then
                dbg_wr_en   <= '0';
                case state is
                    
                    when WAIT_FOR_BOOT =>
                        boot_msg_delay  <= boot_msg_delay+1;
                        if boot_msg_delay=BOOT_DELAY_CYCLES-2 then
                            state   <= PRINT_BOOT_MSG;
                        end if;
                    
                    when PRINT_BOOT_MSG =>
                        dbg_msg(1 to 11)    <= "RX" & natural'image(RX_SEL) & ": ready" & nul;
                        dbg_wr_en           <= '1';
                        state               <= IDLE;
                    
                    when IDLE =>
                        cycle_cnt   <= cycle_cnt+1;
                        if cycle_cnt=STATUS_MSG_CYCLES-2 then
                            state   <= PRINT_STATUS;
                        end if;
                    
                    when PRINT_STATUS =>
                        cycle_cnt           <= 0;
                        dbg_msg(1 to 7)     <= "RX" & natural'image(1-RX_SEL) & ":  " & nul;
                        dbg_msg(6)          <= chr(rx_det_stable(1-RX_SEL));
                        dbg_wr_en           <= '1';
                        state               <= IDLE;
                    
                end case;
            end if;
        end process;
        
        UART_DEBUG_inst : entity work.UART_DEBUG
            generic map (
                CLK_IN_PERIOD   => G_CLK_PERIOD
            )
            port map (
                CLK => dbg_clk,
                RST => dbg_rst,
                
                MSG     => dbg_msg,
                WR_EN   => dbg_wr_en,
                CTS     => dbg_cts,
                
                BUSY    => dbg_busy,
                FULL    => dbg_full,
                TXD     => dbg_txd
            );
        
    end generate;
    
end rtl;

