----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    21:49:35 07/28/2014 
-- Module Name:    PANDA_LIGHT - rtl 
-- Project Name:   PANDA_LIGHT
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity PANDA_LIGHT is
    generic (
        RX_SEL  : natural := 0
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
        
        TX_CHANNELS_OUT_P   : out std_ulogic_vector(3 downto 0) := "0000";
        TX_CHANNELS_OUT_N   : out std_ulogic_vector(3 downto 0) := "0000";
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
    
    -- 50 MHz in nano seconds
    constant G_CLK_PERIOD   : real := 20.0;
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_stopped    : std_ulogic := '0';
    
    signal boot_msg_delay   : natural := 1000;
    signal boot_msg_sent    : boolean := false;
    signal dbg_ready        : boolean := false;
    signal rx_con_msg_sent  : boolean := false;
    signal tx_con_msg_sent  : boolean := false;
    
    
    ----------------------------
    --- HDMI related signals ---
    ----------------------------
    
    signal rx_det_stable    : std_ulogic := '0';
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
    
    
    ------------------
    --- UART debug ---
    ------------------
    
    -- Inputs
    signal dbg_clk  : std_ulogic := '0';
    signal dbg_rst  : std_ulogic := '0';
    
    signal dbg_msg      : string(1 to 128) := (others => nul);
    signal dbg_wr_en    : std_ulogic := '0';
    signal dbg_cts      : std_ulogic := '0';
    
    -- Outputs
    signal dbg_done : std_ulogic := '0';
    signal dbg_full : std_ulogic := '0';
    signal dbg_txd  : std_ulogic := '0';
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLK_MAN_inst : entity work.CLK_MAN
        generic map (
            CLK_IN_PERIOD   => 50.0,
            MULTIPLIER      => 5,
            DIVISOR         => 2
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
    
    USB_TXD     <= dbg_txd;
    USB_RTSN    <= dbg_full;
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- only enabled chips make 'DET' signals possible!
    RX_EN(RX_SEL)   <= '1'; --tx_det_stable;
    TX_EN           <= '1';
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    rx_det_DEBOUNCE_inst : entity work.DEBOUNCE
        generic map (
            CYCLE_COUNT => 100
        )
        port map (
            CLK => g_clk,
            
            I   => RX_DET(RX_SEL),
            O   => rx_det_stable
        );
        
    tx_det_DEBOUNCE_inst : entity work.DEBOUNCE
        generic map (
            CYCLE_COUNT => 100
        )
        port map (
            CLK => g_clk,
            
            I   => TX_DET,
            O   => tx_det_stable
        );
    
    diff_ibuf_gen : for i in 0 to 7 generate
        
        rx_channel_IBUFDS_inst : IBUFDS
            generic map (DIFF_TERM  => false)
            port map (
                I   => RX_CHANNELS_IN_P(i),
                IB  => RX_CHANNELS_IN_N(i),
                O   => rx_channels_in(i)
            );
        
    end generate;
    
    diff_obuf_gen : for i in 0 to 3 generate
        
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
    
    
    ------------------
    --- UART debug ---
    ------------------
    
    dbg_clk <= g_clk;
    dbg_rst <= g_rst;
    
    dbg_cts <= not USB_CTSN;
    
    process(g_clk)
    begin
        if rising_edge(g_clk) then
            dbg_wr_en   <= '0';
            
            if not boot_msg_sent then
                if boot_msg_delay=0 then
                    dbg_msg(1 to 6) <= "ready" & nul;
                    dbg_wr_en       <= '1';
                    boot_msg_sent   <= true;
                    dbg_ready       <= true;
                else
                    boot_msg_delay  <= boot_msg_delay-1;
                end if;
            end if;
            
            if dbg_ready then
                if rx_det_stable='1' then
                    if not rx_con_msg_sent and dbg_full='0' then
                        dbg_msg(1 to 13)    <= "RX connected" & nul;
                        dbg_wr_en           <= '1';
                        rx_con_msg_sent     <= true;
                    end if;
                else
                    rx_con_msg_sent <= false;
                end if;
                
                if tx_det_stable='1' then
                    if not tx_con_msg_sent and dbg_full='0' then
                        dbg_msg(1 to 13)    <= "TX connected" & nul;
                        dbg_wr_en           <= '1';
                        tx_con_msg_sent     <= true;
                    end if;
                else
                    tx_con_msg_sent <= false;
                end if;
            end if;
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
            
            DONE    => dbg_done,
            FULL    => dbg_full,
            TXD     => dbg_txd
        );
    
end rtl;

