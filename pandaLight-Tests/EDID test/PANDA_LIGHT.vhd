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
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity PANDA_LIGHT is
    generic (
        RX_SEL      : natural range 0 to 1 := 1;
        G_CLK_MULT  : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV   : positive range 1 to 256 := 2
    );
    port (
        CLK20   : in std_ulogic;
        
        -- HDMI
        RX_CHANNELS_IN_P    : in std_ulogic_vector(7 downto 0);
        RX_CHANNELS_IN_N    : in std_ulogic_vector(7 downto 0);
        RX_SDA              : inout std_logic_vector(1 downto 0) := "ZZ";
        RX_SCL              : inout std_logic_vector(1 downto 0) := "ZZ";
        RX_CEC              : inout std_ulogic_vector(1 downto 0) := "ZZ";
        RX_DET              : in std_ulogic_vector(1 downto 0);
        RX_EN               : out std_ulogic_vector(1 downto 0) := "00";
        
        TX_CHANNELS_OUT_P   : out std_ulogic_vector(3 downto 0) := "1111";
        TX_CHANNELS_OUT_N   : out std_ulogic_vector(3 downto 0) := "1111";
        TX_SDA              : inout std_logic := 'Z';
        TX_SCL              : inout std_logic := 'Z';
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
        
        -- BT UART
        BT_CTSN : in std_ulogic;
        BT_RTSN : out std_ulogic := '0';
        BT_RXD  : in std_ulogic;
        BT_TXD  : out std_ulogic := '1';
        BT_WAKE : out std_ulogic := '0';
        BT_RSTN : out std_ulogic := '0';
        
        -- SPI Flash
        FLASH_MISO  : in std_ulogic;
        FLASH_MOSI  : out std_ulogic := '0';
        FLASH_CS    : out std_ulogic := '1';
        FLASH_SCK   : out std_ulogic := '0';
        
        -- LEDs
        LEDS_CLK    : out std_ulogic_vector(1 downto 0) := "00";
        LEDS_DATA   : out std_ulogic_vector(1 downto 0) := "00";
        
        -- PMOD
        PMOD0   : inout std_logic_vector(3 downto 0) := "ZZZZ";
        PMOD1   : inout std_logic_vector(3 downto 0) := "ZZZZ";
        PMOD2   : inout std_logic_vector(3 downto 0) := "ZZZZ";
        PMOD3   : inout std_logic_vector(3 downto 0) := "ZZZZ"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    constant G_CLK_PERIOD   : real := 50.0 * real(G_CLK_DIV) / real(G_CLK_MULT);
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    signal pmod2_deb        : std_ulogic_vector(3 downto 0) := x"0";
    
    
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
    
    
    -------------------
    --- E-DDC slave ---
    -------------------
    
    -- Inputs
    signal eddcs_clk    : std_ulogic := '0';
    signal eddcs_rst    : std_ulogic := '0';
    
    signal eddcs_data_in_addr   : std_ulogic_vector(6 downto 0) := "0000000";
    signal eddcs_data_in_wr_en  : std_ulogic := '0';
    signal eddcs_data_in        : std_ulogic_vector(7 downto 0) := x"00";
    signal eddcs_block_valid    : std_ulogic := '0';
    signal eddcs_block_invalid  : std_ulogic := '0';
    
    signal eddcs_sda_in : std_ulogic := '1';
    signal eddcs_scl_in : std_ulogic := '1';
    
    -- outputs
    signal eddcs_sda_out    : std_ulogic := '1';
    signal eddcs_scl_out    : std_ulogic := '1';
    
    signal eddcs_block_check    : std_ulogic := '0';
    signal eddcs_block_request  : std_ulogic := '0';
    signal eddcs_block_number   : std_ulogic_vector(7 downto 0) := x"00";
    signal eddcs_busy           : std_ulogic := '0';
    
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
    
    g_rst   <= not g_clk_locked or pmod2_deb(0);
    
    USB_TXD     <= uart_txd;
    
    pmod0_DEBOUNCE_gen : for i in 0 to 3 generate
        
        pmod2_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 100
            )
            port map (
                CLK => g_clk,
                I   => PMOD2(i),
                O   => pmod2_deb(i)
            );
        
    end generate;
    
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- only enabled chips make 'DET' signals possible!
    RX_EN(RX_SEL)   <= not g_rst;
    RX_EN(1-RX_SEL) <= '0';
    TX_EN           <= not g_rst;
    
    RX_SDA(RX_SEL)  <= eddcs_sda_out;
    RX_SCL(RX_SEL)  <= eddcs_scl_out;
    
    TX_SDA  <= eddcm_sda_out;
    TX_SCL  <= eddcm_scl_out;
    
    tx_channels_out <= rxpt_tx_channels_out;
    
    rx_SIGNAL_SYNC_and_DEBOUNCE_gen : for i in 0 to 1 generate
        
        rx_det_SIGNAL_SYNC_inst : entity work.SIGNAL_SYNC
            port map (
                CLK => g_clk,
                
                DIN     => RX_DET(i),
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
            
            DIN     => TX_DET,
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
    eddcm_rst   <= g_rst or not tx_det_stable;
    
    eddcm_sda_in    <= '0' when TX_SDA='0' else '1';
    eddcm_scl_in    <= '0' when TX_SCL='0' else '1';
    
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
        type state_type is (
            WAITING_FOR_CONNECT,
            STARTING,
            WAITING_FOR_START,
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
                        eddcm_block_number  <= x"00";
                        if tx_det_stable='1' then
                            state   <= STARTING;
                        end if;
                    
                    when STARTING =>
                        eddcm_start <= '1';
                        state       <= WAITING_FOR_START;
                    
                    when WAITING_FOR_START =>
                        if eddcm_busy='1' then
                            state   <= READING_BLOCK;
                        end if;
                    
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
                        if tx_det_stable='0' then
                            state   <= WAITING_FOR_CONNECT;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
    
    -------------------
    --- E-DDC slave ---
    -------------------
    
    eddcs_clk   <= g_clk;
    eddcs_rst   <= rx_rst;
    
    eddcs_sda_in    <= '0' when RX_SDA(RX_SEL)='0' else '1';
    eddcs_scl_in    <= '0' when RX_SCL(RX_SEL)='0' else '1';
    
    E_DDC_SLAVE_inst : entity work.E_DDC_SLAVE
        port map (
            CLK => eddcs_clk,
            RST => eddcs_rst,
            
            DATA_IN_ADDR    => eddcs_data_in_addr,
            DATA_IN_WR_EN   => eddcs_data_in_wr_en,
            DATA_IN         => eddcs_data_in,
            BLOCK_VALID     => eddcs_block_valid,
            BLOCK_INVALID   => eddcs_block_invalid,
            
            SDA_IN  => eddcs_sda_in,
            SDA_OUT => eddcs_sda_out,
            SCL_IN  => eddcs_scl_in,
            SCL_OUT => eddcs_scl_out,
            
            BLOCK_CHECK     => eddcs_block_check,
            BLOCK_REQUEST   => eddcs_block_request,
            BLOCK_NUMBER    => eddcs_block_number,
            BUSY            => eddcs_busy
        );
    
    eddcs_stim_gen : if true generate
        type state_type is (
            WAITING,
            CHECKING_BLOCK_NUMBER,
            WRITING_BLOCK
        );
        
        type edid_block_type is array(0 to 127) of std_ulogic_vector(7 downto 0);
        constant edid_block0    : edid_block_type := (
            x"00", x"FF", x"FF", x"FF", x"FF", x"FF", x"FF", x"00", x"5A", x"63", x"1D", x"E5", x"01", x"01", x"01", x"01",
            x"20", x"10", x"01", x"03", x"80", x"2B", x"1B", x"78", x"2E", x"CF", x"E5", x"A3", x"5A", x"49", x"A0", x"24",
            x"13", x"50", x"54", x"BF", x"EF", x"80", x"B3", x"0F", x"81", x"80", x"81", x"40", x"71", x"4F", x"31", x"0A",
            x"01", x"01", x"01", x"01", x"01", x"01", x"21", x"39", x"90", x"30", x"62", x"1A", x"27", x"40", x"68", x"B0",
            x"36", x"00", x"B1", x"0F", x"11", x"00", x"00", x"1C", x"00", x"00", x"00", x"FF", x"00", x"51", x"36", x"59",
            x"30", x"36", x"30", x"30", x"30", x"30", x"30", x"30", x"30", x"0A", x"00", x"00", x"00", x"FD", x"00", x"32",
            x"4B", x"1E", x"52", x"11", x"00", x"0A", x"20", x"20", x"20", x"20", x"20", x"20", x"00", x"00", x"00", x"FC",
            x"00", x"56", x"58", x"32", x"30", x"32", x"35", x"77", x"6D", x"0A", x"20", x"20", x"20", x"20", x"00", x"FE"
        );
        
        signal state        : state_type := WAITING;
        signal rd_p         : natural range 0 to 127 := 0;
        signal byte_counter : unsigned(7 downto 0) := x"7E";
    begin
        
        eddcs_stim_proc : process(eddcs_rst, eddcs_clk)
        begin
            if eddcs_rst='1' then
                state               <= WAITING;
                eddcs_block_valid   <= '0';
                eddcs_block_invalid <= '0';
                eddcs_data_in_addr  <= "1111111";
                eddcs_data_in_wr_en <= '0';
                rd_p                <= 0;
                byte_counter        <= x"7E";
            elsif rising_edge(eddcs_clk) then
                eddcs_block_valid   <= '0';
                eddcs_block_invalid <= '0';
                eddcs_data_in_addr  <= "1111111";
                eddcs_data_in_wr_en <= '0';
                rd_p                <= 0;
                byte_counter        <= x"7E";
                case state is
                    
                    when WAITING =>
                        if eddcs_block_check='1' then
                            state   <= CHECKING_BLOCK_NUMBER;
                        end if;
                        if eddcs_block_request='1' then
                            state   <= WRITING_BLOCK;
                        end if;
                    
                    when CHECKING_BLOCK_NUMBER =>
                        state   <= WAITING;
                        if eddcs_block_number=x"00" then
                            eddcs_block_valid   <= '1';
                        else
                            eddcs_block_invalid <= '1';
                        end if;
                    
                    when WRITING_BLOCK =>
                        eddcs_data_in_addr  <= eddcs_data_in_addr+1;
                        eddcs_data_in_wr_en <= '1';
                        eddcs_data_in       <= edid_block0(rd_p);
                        rd_p                <= rd_p+1;
                        byte_counter        <= byte_counter-1;
                        if byte_counter(7)='1' then
                            state   <= WAITING;
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
    
    uart_din    <= eddcm_data_out;
    uart_wr_en  <= eddcm_data_out_valid;
    
    UART_SENDER_inst : entity work.UART_SENDER
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            BUFFER_SIZE     => 512
        )
        port map (
            CLK => uart_clk,
            RST => uart_rst,
            
            DIN     => uart_din,
            WR_EN   => uart_wr_en,
            CTS     => uart_cts,
            
            TXD     => uart_txd,
            FULL    => uart_full,
            BUSY    => uart_busy
        );
    
end;
