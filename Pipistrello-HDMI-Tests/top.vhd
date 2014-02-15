----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    17:10:08 01/25/2014
-- Module Name:    TOP - Behavioral
-- Project Name:   HDMI Tests
-- Target Devices: Pipistrello
-- Tool versions:  Xilinx ISE 14.7
-- Description:    Just some messing around with the HDMI connector & HDMI wings
--
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity top is
    generic (
        CLK_IN_PERIOD   : real := 20.0 -- 50 MHz, in nano seconds
    );
    port (
        CLK_IN  : in std_ulogic;
        
        -- USB UART
        USB_TXD     : out std_ulogic;
        USB_RXD     : in std_ulogic;
        USB_RTS     : out std_ulogic;
        USB_CTS     : in std_ulogic;
        USB_RXLED   : in std_ulogic;
        USB_TXLED   : in std_ulogic;
        
        -- HDMI
        HDMI_B_P    : out std_ulogic := '0';
        HDMI_B_N    : out std_ulogic := '0';
        HDMI_R_P    : out std_ulogic := '0';
        HDMI_R_N    : out std_ulogic := '0';
        HDMI_G_P    : out std_ulogic := '0';
        HDMI_G_N    : out std_ulogic := '0';
        HDMI_CLK_P  : out std_ulogic := '0';
        HDMI_CLK_N  : out std_ulogic := '0';
        HDMI_SDA    : inout std_ulogic := '1';
        HDMI_SCL    : inout std_ulogic := '1';
        HDMI_DET    : in std_ulogic;
        
        -- IO
        LEDS    : out std_ulogic_vector(4 downto 0) := (others => '0');
        PUSHBTN : in std_ulogic
    );
end TOP;

architecture rtl of top is
    
    constant g_clk_period   : real := 10.0; -- in nano seconds
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    signal g_scl    : std_ulogic := '1';
    signal g_sda    : std_ulogic := '1';
    
    signal hdmi_r       : std_ulogic := '0';
    signal hdmi_g       : std_ulogic := '0';
    signal hdmi_b       : std_ulogic := '0';
    signal hdmi_clk     : std_ulogic := '0';
    signal hdmi_detect  : std_ulogic := '0';
    
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    -- Inputs
    signal e_ddc_edid_clk   : std_ulogic := '0';
    signal e_ddc_edid_rst   : std_ulogic := '0';
    signal e_ddc_edid_start : std_ulogic := '0';

    -- BiDirs
    signal e_ddc_edid_sda_in    : std_ulogic := '1';
    signal e_ddc_edid_sda_out   : std_ulogic := '1';
    signal e_ddc_edid_scl_in    : std_ulogic := '1';
    signal e_ddc_edid_scl_out   : std_ulogic := '1';

    -- Outputs
    signal e_ddc_edid_block_number      : std_ulogic_vector(7 downto 0) := (others => '0');
    signal e_ddc_edid_busy              : std_ulogic := '0';
    signal e_ddc_edid_transm_error      : std_ulogic := '0';
    signal e_ddc_edid_data_out          : std_ulogic_vector(7 downto 0) := (others => '0');
    signal e_ddc_edid_data_out_valid    : std_ulogic := '0';
    signal e_ddc_edid_byte_index        : std_ulogic_vector(6 downto 0) := (others => '0');
    signal e_ddc_edid_block_finished    : std_ulogic := '0';
    
    
    ----------------------------------------
    ------ MicroBlaze microcontroller ------
    ----------------------------------------
    
    component microblaze_mcs_v1_4
        port (
            Clk             : in std_logic;
            Reset           : in std_logic;
            UART_Rx         : in std_logic;
            UART_Tx         : out std_logic;
            FIT1_Interrupt  : out std_logic;
            FIT1_Toggle     : out std_logic;
            PIT1_Interrupt  : out std_logic;
            PIT1_Toggle     : out std_logic;
            GPO1            : out std_logic_vector(31 downto 0);
            GPO2            : out std_logic_vector(31 downto 0);
            GPI1            : in std_logic_vector(31 downto 0);
            GPI1_Interrupt  : out std_logic;
            GPI2            : in std_logic_vector(31 downto 0);
            GPI2_Interrupt  : out std_logic
        );
    end component;
    
    -- Inputs
    signal microblaze_clk   : std_logic := '0';
    signal microblaze_rst   : std_logic := '0';
    signal microblaze_rxd   : std_logic := '0';
    signal microblaze_gpi1  : std_logic_vector(31 downto 0) := (others => '0');
    signal microblaze_gpi2  : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Outputs
    signal microblaze_txd           : std_logic := '0';
    signal microblaze_gpo1          : std_logic_vector(31 downto 0) := (others => '0');
    signal microblaze_gpo2          : std_logic_vector(31 downto 0) := (others => '0');
    signal microblaze_gpi1_int      : std_logic := '0';
    signal microblaze_gpi2_int      : std_logic := '0';
    signal microblaze_fit1_int      : std_logic := '0';
    signal microblaze_fit1_toggle   : std_logic := '0';
    signal microblaze_pit1_int      : std_logic := '0';
    signal microblaze_pit1_toggle   : std_logic := '0';
    
begin
    
    ------------------------------
    ------ clock management ------
    ------------------------------
    
    CLKMAN_inst : entity work.CLKMAN
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            MULTIPLIER      => 2,
            DIVISOR         => 1
        )
        port map (
            CLK_IN          => CLK_IN,
            CLK_OUT         => g_clk,
            CLK_IN_STOPPED  => open,
            CLK_OUT_STOPPED => open
        );
    
    g_rst   <= PUSHBTN;
    LEDS(4) <= PUSHBTN;
    LEDS(3) <= not USB_TXLED;
    LEDS(2) <= not USB_RXLED;
    LEDS(1) <= microblaze_gpo1(2);
    LEDS(0) <= microblaze_fit1_toggle;
    
    ------------------------------------
    ------ HDMI signal management ------
    ------------------------------------
    
    -- drive low dominant I2C signals
    HDMI_SDA    <= '0' when e_ddc_edid_sda_out = '0' else 'Z';
    HDMI_SCL    <= '0' when e_ddc_edid_scl_out = '0' else 'Z';
    
    hdmi_detect <= HDMI_DET;
    
    hdmi_r      <= '0';
    hdmi_g      <= '0';
    hdmi_b      <= '0';
    hdmi_clk    <= '0';
    
    -- connect differential outputs
    
    hdmi_r_obuf_inst : OBUFDS
        generic map (
            IOSTANDARD  => "TMDS_33"
        )
        port map (
            I   => hdmi_r,
            O   => HDMI_R_P,
            OB  => HDMI_R_N
        );
    
    hdmi_g_obuf_inst : OBUFDS
        generic map (
            IOSTANDARD  => "TMDS_33"
        )
        port map (
            I   => hdmi_g,
            O   => HDMI_G_P,
            OB  => HDMI_G_N
        );
    
    hdmi_b_obuf_inst : OBUFDS
        generic map (
            IOSTANDARD  => "TMDS_33"
        )
        port map (
            I   => hdmi_b,
            O   => HDMI_B_P,
            OB  => HDMI_B_N
        );
    
    hdmi_clk_obuf_inst : OBUFDS
        generic map (
            IOSTANDARD  => "TMDS_33"
        )
        port map (
            I   => hdmi_clk,
            O   => HDMI_CLK_P,
            OB  => HDMI_CLK_N
        );
    
    
    -----------------------------------
    ------ E-DDC (E-)EDID Master ------
    -----------------------------------
    
    e_ddc_edid_clk      <= g_clk;
    e_ddc_edid_rst      <= g_rst;
    e_ddc_edid_sda_in   <= HDMI_SDA;
    e_ddc_edid_scl_in   <= HDMI_SCL;
    
    DDC_EDID_MASTER_inst : entity work.DDC_EDID_MASTER
        generic map (
            CLK_IN_PERIOD   => g_clk_period
        )
        port map (
            CLK => e_ddc_edid_clk,
            RST => e_ddc_edid_rst,
            
            SDA_IN  => e_ddc_edid_sda_in,
            SDA_OUT => e_ddc_edid_sda_out,
            SCL_IN  => e_ddc_edid_scl_in,
            SCL_OUT => e_ddc_edid_scl_out,
            
            START           => e_ddc_edid_start,
            BLOCK_NUMBER    => e_ddc_edid_block_number,
            
            BUSY            => e_ddc_edid_busy,
            TRANSM_ERROR    => e_ddc_edid_transm_error,
            DATA_OUT        => e_ddc_edid_data_out,
            DATA_OUT_VALID  => e_ddc_edid_data_out_valid,
            BYTE_INDEX      => e_ddc_edid_byte_index,
            BLOCK_FINISHED  => e_ddc_edid_block_finished
        );
    
    
    ----------------------------------------
    ------ MicroBlaze microcontroller ------
    ----------------------------------------
    
    microblaze_clk  <= g_clk;
    microblaze_rst  <= g_rst;
    
    microblaze_rxd  <= USB_RXD;
    USB_TXD         <= microblaze_txd;
    
    microblaze_gpi1(31 downto 6)    <= (others => '0');
    microblaze_gpi1(5)              <= hdmi_detect;
    microblaze_gpi1(4)              <= e_ddc_edid_block_finished;
    microblaze_gpi1(3)              <= e_ddc_edid_data_out_valid;
    microblaze_gpi1(2)              <= e_ddc_edid_transm_error;
    microblaze_gpi1(1)              <= e_ddc_edid_busy;
    microblaze_gpi1(0)              <= USB_CTS;
    
    microblaze_gpi2(31 downto 16)   <= (others => '0');
    microblaze_gpi2(15 downto 8)    <= std_logic_vector(e_ddc_edid_data_out);
    microblaze_gpi2(7 downto 0)     <= "0" & std_logic_vector(e_ddc_edid_byte_index);
    
    e_ddc_edid_start    <= microblaze_gpo1(1);
    USB_RTS             <= microblaze_gpo1(0);
    
    e_ddc_edid_block_number <= std_ulogic_vector(microblaze_gpo2(7 downto 0));
    
    microblaze_inst : microblaze_mcs_v1_4
        port map (
            Clk             => microblaze_clk,
            Reset           => microblaze_rst,
            UART_Rx         => microblaze_rxd,
            UART_Tx         => microblaze_txd,
            FIT1_Interrupt  => microblaze_fit1_int,
            FIT1_Toggle     => microblaze_fit1_toggle,
            PIT1_Interrupt  => microblaze_pit1_int,
            PIT1_Toggle     => microblaze_pit1_toggle,
            GPO1            => microblaze_gpo1,
            GPO2            => microblaze_gpo2,
            GPI1            => microblaze_gpi1,
            GPI2            => microblaze_gpi2,
            GPI1_Interrupt  => microblaze_gpi1_int,
            GPI2_Interrupt  => microblaze_gpi2_int
        );

    
end rtl;

