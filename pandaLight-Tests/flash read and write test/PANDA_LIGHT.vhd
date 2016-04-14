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
        G_CLK_MULT      : positive range 2 to 256 := 5; -- 20 MHz * 5 / 2 = 50 MHz
        G_CLK_DIV       : positive range 1 to 256 := 2;
        FCTRL_CLK_MULT  : positive := 2; -- Flash clock: 20 MHz
        FCTRL_CLK_DIV   : positive := 5;
        BYTE_COUNT      : positive := 2048;
        FLASH_ADDR      : std_ulogic_vector(23 downto 0) := x"000000" -- x"060000"
    );
    port (
        CLK20   : in std_ulogic;
        
        -- SPI Flash
        FLASH_MISO  : in std_ulogic;
        FLASH_MOSI  : out std_ulogic := '0';
        FLASH_CS    : out std_ulogic := '1';
        FLASH_SCK   : out std_ulogic := '0';
        
        -- PMOD
        PMOD0   : inout std_ulogic_vector(3 downto 0) := "0000"
    );
end PANDA_LIGHT;

architecture rtl of PANDA_LIGHT is
    
    attribute keep  : boolean;
    
    constant G_CLK_PERIOD   : real := 50.0 * real(G_CLK_DIV) / real(G_CLK_MULT);
    
    signal g_clk    : std_ulogic := '0';
    signal g_rst    : std_ulogic := '0';
    
    signal g_clk_locked : std_ulogic := '0';
    
    signal pmod0_deb    : std_ulogic_vector(3 downto 0) := x"0";
    signal pmod0_deb_q  : std_ulogic_vector(3 downto 0) := x"0";
    
    signal start_flash_read     : boolean := false;
    signal start_flash_write    : boolean := false;
    
    
    -------------------------
    --- SPI Flash control ---
    -------------------------
    
    -- Inputs
    signal fctrl_clk    : std_ulogic := '0';
    signal fctrl_rst    : std_ulogic := '0';
    
    signal fctrl_addr   : std_ulogic_vector(23 downto 0) := x"000000";
    signal fctrl_din    : std_ulogic_vector(7 downto 0) := x"00";
    signal fctrl_rd_en  : std_ulogic := '0';
    signal fctrl_wr_en  : std_ulogic := '0';
    signal fctrl_miso   : std_ulogic := '0';
    
    -- Outputs
    signal fctrl_dout   : std_ulogic_vector(7 downto 0) := x"00";
    signal fctrl_valid  : std_ulogic := '0';
    signal fctrl_wr_ack : std_ulogic := '0';
    signal fctrl_busy   : std_ulogic := '0';
    signal fctrl_full   : std_ulogic := '0';
    signal fctrl_mosi   : std_ulogic := '0';
    signal fctrl_c      : std_ulogic := '0';
    signal fctrl_sn     : std_ulogic := '1';
    
    attribute keep of fctrl_dout : signal is true;
    
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
    
    g_rst               <= not g_clk_locked or pmod0_deb(0);
    start_flash_read    <= pmod0_deb(1)='1' and pmod0_deb_q(1)='0';
    start_flash_write   <= pmod0_deb(2)='1' and pmod0_deb_q(2)='0';
    
    FLASH_MOSI  <= fctrl_mosi;
    FLASH_CS    <= fctrl_sn;
    FLASH_SCK   <= fctrl_c;
    
    PMOD0(0)    <= 'Z';
    PMOD0(1)    <= 'Z';
    PMOD0(2)    <= 'Z';
    PMOD0(3)    <= 'Z';
    
    pmod0_DEBOUNCE_gen : for i in 0 to 3 generate
        
        pmod0_DEBOUNCE_inst : entity work.DEBOUNCE
            generic map (
                CYCLE_COUNT => 100
            )
            port map (
                CLK => g_clk,
                I   => PMOD0(i),
                O   => pmod0_deb(i)
            );
        
    end generate;
    
    pmod0_deb_q_proc : process(g_clk)
    begin
        if rising_edge(g_clk) then
            pmod0_deb_q <= pmod0_deb;
        end if;
    end process;
    
    
    -------------------------
    --- SPI Flash control ---
    -------------------------
    
    fctrl_clk   <= g_clk;
    fctrl_rst   <= g_rst;
    
    fctrl_miso  <= FLASH_MISO;
    
    SPI_FLASH_CONTROL_inst : entity work.SPI_FLASH_CONTROL
        generic map (
            CLK_IN_PERIOD   => G_CLK_PERIOD,
            CLK_OUT_MULT    => FCTRL_CLK_MULT,
            CLK_OUT_DIV     => FCTRL_CLK_DIV,
            BUF_SIZE        => 2**log2(BYTE_COUNT)
        )
        port map (
            CLK => fctrl_clk,
            RST => fctrl_rst,
            
            ADDR    => fctrl_addr,
            DIN     => fctrl_din,
            RD_EN   => fctrl_rd_en,
            WR_EN   => fctrl_wr_en,
            MISO    => fctrl_miso,
            
            DOUT    => fctrl_dout,
            VALID   => fctrl_valid,
            WR_ACK  => fctrl_wr_ack,
            BUSY    => fctrl_busy,
            FULL    => fctrl_full,
            MOSI    => fctrl_mosi,
            C       => fctrl_c,
            SN      => fctrl_sn
        );
    
    spi_flash_control_stim_gen : if true generate
        constant COUNTER_DEF    : unsigned(log2(BYTE_COUNT-1) downto 0)
                                := uns(BYTE_COUNT-1, log2(BYTE_COUNT-1)+1);
        
        type state_type is (
            INIT,
            READING_DATA,
            WRITING_DATA
        );
        
        signal state    : state_type := INIT;
        signal counter  : unsigned(log2(BYTE_COUNT) downto 0) := COUNTER_DEF;
        signal done     : boolean := false;
    begin
        
        fctrl_addr  <= FLASH_ADDR;
        fctrl_din   <= stdulv(resize(counter, 8));
        
        done    <= counter(counter'high)='1';
        
        spi_flash_control_stim_proc : process(g_clk, g_rst)
        begin
            if g_rst='1' then
                state       <= INIT;
                counter     <= COUNTER_DEF;
                fctrl_rd_en <= '0';
                fctrl_wr_en <= '0';
            elsif rising_edge(g_clk) then
                fctrl_rd_en <= '0';
                fctrl_wr_en <= '0';
                
                case state is
                    
                    when INIT =>
                        counter <= COUNTER_DEF;
                        if start_flash_read then
                            state   <= READING_DATA;
                        end if;
                        if start_flash_write then
                            state   <= WRITING_DATA;
                        end if;
                    
                    when READING_DATA =>
                        fctrl_rd_en <= '1';
                        if done then
                            state   <= INIT;
                        end if;
                        if fctrl_valid='1' then
                            counter <= counter-1;
                        end if;
                    
                    when WRITING_DATA =>
                        fctrl_wr_en <= '1';
                        counter     <= counter-1;
                        if done then
                            state   <= INIT;
                        end if;
                    
                end case;
            end if;
        end process;
        
    end generate;
    
end rtl;

