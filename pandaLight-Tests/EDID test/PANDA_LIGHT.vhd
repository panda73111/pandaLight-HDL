----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:37:00 09/06/2016 
-- Module Name:    PANDA_LIGHT - rtl 
-- Project Name:   EDID test
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--  
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity PANDA_LIGHT is
    generic (
        RX_SEL      : natural range 0 to 1 := 0;
        G_CLK_MULT  : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV   : positive range 1 to 256 := 2
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
        USB_TXD     : out std_ulogic := '1';
        USB_CTSN    : in std_ulogic;
        USB_RTSN    : out std_ulogic := '0';
        USB_DSRN    : in std_ulogic;
        USB_DTRN    : out std_ulogic := '0';
        USB_DCDN    : out std_ulogic := '0';
        USB_RIN     : out std_ulogic := '0';
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    constant G_CLK_PERIOD   : real := 50.0 * real(G_CLK_DIV) / real(G_CLK_MULT);
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    
    ----------------------------
    --- HDMI related signals ---
    ----------------------------
    
    signal rx_det_sync          : std_ulogic_vector(1 downto 0) := "00";
    signal rx_det_stable        : std_ulogic_vector(1 downto 0) := "00";
    
    signal tx_det_sync      : std_ulogic := '0';
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
    
    signal rx_serdesstrobe  : std_ulogic := '0';
    
    -- Outputs
    signal rx_raw_data          : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rx_raw_data_valid    : std_ulogic := '0';
    
    signal rx_vsync     : std_ulogic := '0';
    signal rx_hsync     : std_ulogic := '0';
    signal rx_rgb       : std_ulogic_vector(23 downto 0) := x"000000";
    signal rx_rgb_valid : std_ulogic := '0';
    signal rx_aux       : std_ulogic_vector(8 downto 0) := (others => '0');
    signal rx_aux_valid : std_ulogic := '0';
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    -- Inputs
    signal rxpt_pix_clk : std_ulogic := '0';
    signal rxpt_rst     : std_ulogic := '0';
    
    -- Outputs
    signal rxpt_rx_raw_data         : std_ulogic_vector(14 downto 0) := (others => '0');
    signal rxpt_rx_raw_data_valid   : std_ulogic := '0';
    
    signal rxpt_tx_channels_out : std_ulogic_vector(3 downto 0) := "0000";
    
    
    ----------------
    --- USB UART ---
    ----------------
    
    -- Inputs
    signal uart_clk : std_ulogic := '0';
    signal uart_rst : std_ulogic := '0';
    
    signal uart_din     : std_ulogic_vector(7 downto 0) := x"00";
    signal uart_wr_en   : std_ulogic := '0';
    signal uart_cts     : std_ulogic := '0';
    
    signal uart_txd     : std_ulogic := '0';
    signal uart_full    : std_ulogic := '0';
    signal uart_busy    : std_ulogic := '0';
    
    
    --------------------
    --- E-DDC master ---
    --------------------
    
    -- Inputs
    signal eddcm_clk    : std_ulogic := '0';
    signal eddcm_rst    : std_ulogic := '0';
    
    signal eddcm_sda_in : std_ulogic := '0';
    signal eddcm_scl_in : std_ulogic := '0';
    
    signal eddcm_start          : std_ulogic := '0';
    signal eddcm_block_number   : std_ulogic_vector(7 downto 0) := x"00";
    
    -- Outputs
    signal eddcm_sda_out    : std_ulogic := '1';
    signal eddcm_scl_out    : std_ulogic := '1';
    
    signal eddcm_busy           : std_ulogic := '0';
    signal eddcm_transm_error   : std_ulogic := '0';
    signal eddcm_data_out       : std_ulogic_vector(7 downto 0) := x"00";
    signal eddcm_data_out_valid : std_ulogic := '0';
    signal eddcm_byte_index     : std_ulogic_vector(6 downto 0) := "0000000";
    
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
            
            CLK_IN  => CLK20,
            CLK_OUT => g_clk,
            LOCKED  => g_clk_locked
        );
        
    
    --------------------------------------
    ------ global signal management ------
    --------------------------------------
    
    g_rst   <= not g_clk_locked;
    
    USB_TXD     <= uart_txd;
    USB_RTSN    <= not uart_rts;
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- only enabled chips make 'DET' signals possible!
    RX_EN(RX_SEL)   <= tx_det_stable;
    RX_EN(1-RX_SEL) <= tx_det_stable;
    TX_EN           <= '1';
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    rx_SIGNAL_SYNC_and_DEBOUNCE_gen : for i in 0 to 1 generate
        
        rx_det_SIGNAL_SYNC_inst : entity work.SIGNAL_SYNC
            port map (
                CLK => g_clk,
                
                DIN     => rx_det(i),
                DOUT    => rx_det_sync(i)
            );
        
        rx_det_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 1500
            )
            port map (
                CLK => g_clk,
                
                I   => rx_det_sync(i),
                O   => rx_det_stable(i)
            );
    
    end generate;
    
    tx_det_SIGNAL_SYNC_inst : entity work.SIGNAL_SYNC
        port map (
            CLK => g_clk,
            
            DIN     => tx_det,
            DOUT    => tx_det_sync
        );
        
    tx_det_DEBOUNCE_inst : entity work.DEBOUNCE
        generic map (
            CYCLE_COUNT => 1000
        )
        port map (
            CLK => g_clk,
            
            I   => tx_det_sync,
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
    rx_rst              <= g_rst or not rx_det_stable(RX_SEL) or not rxclk_ioclk_locked;
    rx_serdesstrobe     <= rxclk_serdesstrobe;
    
    TMDS_DECODER_inst : entity work.TMDS_DECODER
        port map (
            PIX_CLK         => rx_pix_clk,
            PIX_CLK_X2      => rx_pix_clk_x2,
            PIX_CLK_X10     => rx_pix_clk_x10,
            RST             => rx_rst,
            
            SERDESSTROBE    => rx_serdesstrobe,
            
            CHANNELS_IN => rx_channels_in(RX_SEL*4 + 2 downto RX_SEL*4),
            
            RAW_DATA        => rx_raw_data,
            RAW_DATA_VALID  => rx_raw_data_valid,
            
            VSYNC       => rx_vsync,
            HSYNC       => rx_hsync,
            RGB         => rx_rgb,
            RGB_VALID   => rx_rgb_valid,
            AUX         => rx_aux,
            AUX_VALID   => rx_aux_valid
        );
    
    
    -----------------------------
    --- RX to TX0 passthrough ---
    -----------------------------
    
    rxpt_pix_clk    <= rx_pix_clk;
    rxpt_rst        <= rx_rst;
    
    rxpt_rx_raw_data        <= rx_raw_data;
    rxpt_rx_raw_data_valid  <= rx_raw_data_valid;
    
    TMDS_PASSTHROUGH_inst : entity work.TMDS_PASSTHROUGH
        port map (
            PIX_CLK => rxpt_pix_clk,
            RST     => rxpt_rst,
            
            RX_RAW_DATA         => rxpt_rx_raw_data,
            RX_RAW_DATA_VALID   => rxpt_rx_raw_data_valid,
            
            TX_CHANNELS_OUT => rxpt_tx_channels_out
        );
    
    
    --------------------
    --- E-DDC master ---
    --------------------
    
    eddcm_clk   <= g_clk;
    eddcm_rst   <= rx_rst;
    
    eddcm_sda_in    <= RX_SDA(RX_SEL);
    eddcm_sda_out   <= RX_SDA(RX_SEL);
    eddcm_scl_in    <= RX_SCL(RX_SEL);
    eddcm_scl_out   <= RX_SCL(RX_SEL);
    
    E_DDC_MASTER_inst : entity work.E_DDC_MASTER
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD
        )
        port map (
            CLK => eddcm_clk,
            RST => eddcm_rst,
            
            SDA_IN  => eddcm_sda_in,
            SDA_OUT => eddcm_sda_out,
            SCL_IN  => eddcm_scl_in,
            SCL_OUT => eddcm_scl_out,
            
            START           => eddcm_start,
            BLOCK_NUMBER    => eddcm_block_number,
            
            BUSY            => eddcm_busy,
            TRANSM_ERROR    => eddcm_transm_error,
            DATA_OUT        => eddcm_data_out,
            DATA_OUT_VALID  => eddcm_data_out_valid,
            BYTE_INDEX      => eddcm_byte_index
        );
    
    eddcm_stim_gen : if true generate
        type state_type (
            WAITING_FOR_CONNECT,
            STARTING,
            READING_BLOCK,
            INCREMENTING_BLOCK_NUMBER,
            WAITING_FOR_DISCONNECT
        );
        
        signal state    : state_type := WAITING_FOR_CONNECT;
    begin
        
        eddcm_stim_proc : process(eddcm_clk, eddcm_rst)
        begin
            if eddcm_rst='1' then
                state               <= WAITING_FOR_CONNECT;
                eddcm_start         <= '0';
                eddcm_block_number  <= x"00";
            elsif rising_edge(eddcm_clk) then
                eddcm_start <= '0';
                
                case state is
                    
                    when WAITING_FOR_CONNECT =>
                        if rx_det_stable(RX_SEL)='1' then
                            state   <= STARTING;
                        end if;
                    
                    when STARTING =>
                        eddcm_start <= '1';
                        state       <= READING_BLOCK;
                    
                    when READING_BLOCK =>
                        if eddcm_busy='0' then
                            state   <= INCREMENTING_BLOCK_NUMBER;
                        end if;
                        if eddcm_transm_error='1' then
                            state   <= WAITING_FOR_DISCONNECT;
                        end if;
                    
                    when INCREMENTING_BLOCK_NUMBER =>
                        eddcm_block_number  <= eddcm_block_number+1;
                        state               <= STARTING;
                    
                    when WAITING_FOR_DISCONNECT =>
                        if rx_det_stable(RX_SEL)='0' then
                            state   <= WAITING_FOR_CONNECT;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
    ----------------
    --- USB UART ---
    ----------------
    
    uart_clk    <= g_clk;
    uart_rst    <= g_rst;
    
    uart_cts    <= not USB_CTSN;
    
    uart_din        <= eddcm_data_out;
    uart_din_wr_en  <= eddcm_data_out_valid;
    
    UART_CONTROL_inst : entity work.UART_SENDER
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            BUFFER_SIZE     => 2048
        )
        port map (
            CLK => uart_clk,
            RST => uart_rst,
            
            DIN     => uart_din,
            WR_EN   => uart_din_wr_en,
            CTS     => uart_cts,
            
            TXD     => uart_txd,
            FULL    => uart_full,
            BUSY    => uart_busy
        );
    
end;
