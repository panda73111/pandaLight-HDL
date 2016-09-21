----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    10:45:21 09/20/2016
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    LED_OUT_QUEUE - rtl
-- Tool versions:  Xilinx ISE 14.7
-- Description:
--  
-- Additional Comments:
--  
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity LED_OUT_QUEUE is
    generic (
        MAX_LED_COUNT   : positive;
        R_BITS          : positive range 5 to 12 := 8;
        G_BITS          : positive range 6 to 12 := 8;
        B_BITS          : positive range 5 to 12 := 8;
        ACCU_BITS       : positive range 8 to 40
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        WR_EN       : in std_ulogic;
        ACCU        : in std_ulogic_vector(3*ACCU_BITS-1 downto 0);
        PIXEL_COUNT : in std_ulogic_vector(31 downto 0);
        
        LED_RGB_VALID   : out std_ulogic := '0';
        LED_RGB         : out std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0')
    );
end LED_OUT_QUEUE;

architecture rtl of LED_OUT_QUEUE is
    
    type divs_din_type is array(0 to 2) of std_ulogic_vector(ACCU_BITS-1 downto 0);
    
    signal divs_dividend    : divs_din_type := (others => (others => '0'));
    signal divs_quotient    : divs_din_type := (others => (others => '0'));
    signal divs_valid       : std_ulogic_vector(2 downto 0) := "000";
    signal divs_busy        : std_ulogic_vector(2 downto 0) := "000";
    
    signal divisor  : std_ulogic_vector(ACCU_BITS-1 downto 0);
    
    signal fifo_rd_en   : std_ulogic := '0';
    signal fifo_empty   : std_ulogic := '0';
    signal fifo_valid   : std_ulogic := '0';
    signal fifo_dout    : std_ulogic_vector(3*ACCU_BITS-1 downto 0) := (others => '0');
    
begin
    
    LED_RGB_VALID   <= divs_valid(0);
    LED_RGB         <=
        divs_quotient(0)(R_BITS-1 downto 0) &
        divs_quotient(1)(G_BITS-1 downto 0) &
        divs_quotient(2)(B_BITS-1 downto 0);
    
    divisor(PIXEL_COUNT'range)  <= PIXEL_COUNT;
    
    ASYNC_FIFO_inst : entity work.ASYNC_FIFO
        generic map (
            WIDTH   => 3*ACCU_BITS,
            DEPTH   => MAX_LED_COUNT
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            DIN     => ACCU,
            WR_EN   => WR_EN,
            RD_EN   => fifo_rd_en,
            
            DOUT    => fifo_dout,
            EMPTY   => fifo_empty,
            VALID   => fifo_valid
        );
    
    ITERATIVE_DIVIDERs_gen : for i in 0 to 2 generate
        
        -- divider 0 -> red
        -- divider 1 -> green
        -- divider 2 -> blue
        divs_dividend(i)    <= ACCU((3-i)*ACCU_BITS-1 downto (2-i)*ACCU_BITS);
        
        ITERATIVE_DIVIDER_inst : entity work.ITERATIVE_DIVIDER
            generic map (
                WIDTH   => ACCU_BITS
            )
            port map (
                CLK => CLK,
                RST => RST,
                
                START   => fifo_valid,
                
                DIVIDEND    => divs_dividend(i),
                DIVISOR     => divisor,
                
                BUSY    => divs_busy(i),
                VALID   => divs_valid(i),
                
                QUOTIENT    => divs_quotient(i)
            );
        
    end generate;
    
    process(RST, CLK)
    begin
        if RST='1' then
            fifo_rd_en  <= '0';
        elsif rising_edge(CLK) then
            fifo_rd_en  <= not fifo_empty and not divs_busy(0);
        end if;
    end process;
    
end rtl;
