----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    ‏‎14:13:07 09/21/2016
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    VER_SCANNER - rtl
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

entity VER_SCANNER is
    generic (
        MAX_LED_COUNT   : positive;
        R_BITS          : positive range 5 to 12;
        G_BITS          : positive range 6 to 12;
        B_BITS          : positive range 5 to 12;
        ACCU_BITS       : positive range 8 to 40
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CFG_ADDR    : in std_ulogic_vector(4 downto 0);
        CFG_WR_EN   : in std_ulogic;
        CFG_DATA    : in std_ulogic_vector(7 downto 0);
        
        FRAME_VSYNC     : in std_ulogic;
        FRAME_RGB_WR_EN : in std_ulogic;
        FRAME_RGB       : in std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        
        FRAME_X : in std_ulogic_vector(15 downto 0);
        FRAME_Y : in std_ulogic_vector(15 downto 0);
        
        LED_RGB_VALID   : out std_ulogic := '0';
        LED_RGB         : out std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0) := (others => '0');
        LED_NUM         : out std_ulogic_vector(7 downto 0) := (others => '0');
        LED_SIDE        : out std_ulogic := '0'
    );
end VER_SCANNER;

architecture rtl of VER_SCANNER is
    
    type scanners_pixel_count_type is array(0 to 1) of std_ulogic_vector(31 downto 0);
    type scanners_accu_type is array(0 to 1) of std_ulogic_vector(ACCU_BITS-1 downto 0);
    
    signal scanners_pixel_count : scanners_pixel_count_type := (others => x"0000_0000");
    signal scanners_accu_valid  : std_ulogic_vector(1 downto 0) := "00";
    signal scanners_accu_r      : scanners_accu_type := (others => (others => '0'));
    signal scanners_accu_g      : scanners_accu_type := (others => (others => '0'));
    signal scanners_accu_b      : scanners_accu_type := (others => (others => '0'));
    
    signal accu_valid   : std_ulogic := '0';
    signal accu_r       : std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
    signal accu_g       : std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
    signal accu_b       : std_ulogic_vector(ACCU_BITS-1 downto 0) := (others => '0');
    
    signal led_count    : std_ulogic_vector(7 downto 0) := x"00";
    signal led_counter  : unsigned(log2(MAX_LED_COUNT)-1 downto 0) := (others => '0');
    signal side         : std_ulogic := '0';
    
    signal queue_led_rgb_valid  : std_ulogic := '0';
    
begin
    
    LED_RGB_VALID   <= queue_led_rgb_valid;
    LED_NUM         <= stdulv(int(led_counter), 8);
    LED_SIDE        <= side;
    
    accu_valid  <= scanners_accu_valid(0) or scanners_accu_valid(1);
    accu_r      <= scanners_accu_r(0) when scanners_accu_valid(0)='1' else scanners_accu_r(1);
    accu_g      <= scanners_accu_g(0) when scanners_accu_valid(0)='1' else scanners_accu_g(1);
    accu_b      <= scanners_accu_b(0) when scanners_accu_valid(0)='1' else scanners_accu_b(1);
    
    cfg_proc : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' and CFG_WR_EN='1' and CFG_ADDR="00000" then
                led_count   <= CFG_DATA;
            end if;
        end if;
    end process;
    
    LED_OUT_QUEUE_inst : entity work.LED_OUT_QUEUE
        generic map (
            MAX_LED_COUNT   => MAX_LED_COUNT,
            R_BITS          => R_BITS,
            G_BITS          => G_BITS,
            B_BITS          => B_BITS,
            ACCU_BITS       => ACCU_BITS
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            WR_EN       => accu_valid,
            ACCU_R      => accu_r,
            ACCU_G      => accu_g,
            ACCU_B      => accu_b,
            PIXEL_COUNT => scanners_pixel_count(0),
            
            LED_RGB_VALID   => queue_led_rgb_valid,
            LED_RGB         => LED_RGB
        );
    
    HALF_VER_SCANNERs_gen : for odd in 0 to 1 generate
        
        HALF_VER_SCANNER_inst : entity work.HALF_VER_SCANNER
            generic map (
                ODD_LEDS        => odd=1,
                R_BITS          => R_BITS,
                G_BITS          => G_BITS,
                B_BITS          => B_BITS,
                ACCU_BITS       => ACCU_BITS
            )
            port map (
                CLK => CLK,
                RST => RST,
                
                CFG_ADDR    => CFG_ADDR,
                CFG_WR_EN   => CFG_WR_EN,
                CFG_DATA    => CFG_DATA,
                
                FRAME_VSYNC     => FRAME_VSYNC,
                FRAME_RGB_WR_EN => FRAME_RGB_WR_EN,
                FRAME_RGB       => FRAME_RGB,
                
                FRAME_X => FRAME_X,
                FRAME_Y => FRAME_Y,
                
                ACCU_VALID  => scanners_accu_valid(odd),
                ACCU_R      => scanners_accu_r(odd),
                ACCU_G      => scanners_accu_g(odd),
                ACCU_B      => scanners_accu_b(odd),
                
                PIXEL_COUNT => scanners_pixel_count(odd)
            );
        
    end generate;
    
    led_counter_proc : process(RST, CLK)
    begin
        if RST='1' then
            led_counter <= (others => '0');
            side        <= '0';
        elsif rising_edge(CLK) then
            if queue_led_rgb_valid='1' then
                side    <= not side;
                
                if side='1' then
                    led_counter <= led_counter+1;
                end if;
                
                if led_counter=led_count-1 then
                    led_counter <= (others => '0');
                    side        <= '0';
                end if;
            end if;
        end if;
    end process;
    
end rtl;
