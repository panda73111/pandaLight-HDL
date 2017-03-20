----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    12:27:29 07/30/2014 
-- Module Name:    LED_CONTROL - rtl 
-- Project Name:   LED_CONTROL
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--
-- Additional Comments: 
--   Modes (to be extended):
--    [0] = WS2801
--    [1] = WS2811, fast mode (800 kHz)
--    [2] = WS2811, slow mode (400 kHz)
--    [3] = WS2812/WS2812B
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.help_funcs.all;

entity LED_CONTROL is
    generic (
        CLK_IN_PERIOD           : real;
        WS2801_LEDS_CLK_PERIOD  : real := 1000.0; -- 1 MHz;
        MAX_LED_COUNT           : natural := 128
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        MODE    : in std_ulogic_vector(1 downto 0);
        
        LED_VSYNC       : in std_ulogic;
        LED_RGB         : in std_ulogic_vector(23 downto 0);
        LED_RGB_WR_EN   : in std_ulogic;
        
        BUSY    : out std_ulogic := '0';
        
        LEDS_CLK    : out std_ulogic := '0';
        LEDS_DATA   : out std_ulogic := '0'
    );
end LED_CONTROL;

architecture rtl of LED_CONTROL is
    
    type state_type is (
        GETTING_FRAME,
        WAITING_FOR_LED_START_IDLE,
        STARTING,
        WAITING_FOR_LED_END_IDLE,
        WAITING_FOR_FRAME_START
    );
    
    type reg_type is record
        state       : state_type;
        fifo_wr_en  : std_ulogic;
        fifo_din    : std_ulogic_vector(23 downto 0);
        start       : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => GETTING_FRAME,
        fifo_wr_en  => '0',
        fifo_din    => x"000000",
        start       => '0'
    );
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal led_vsync_q  : std_ulogic := '0';
    
    signal ws2801_rst       : std_ulogic := '0';
    signal ws2801_start     : std_ulogic := '0';
    signal ws2801_stop      : std_ulogic := '0';
    signal ws2801_busy      : std_ulogic := '0';
    signal ws2801_vsync     : std_ulogic := '0';
    signal ws2801_leds_clk  : std_ulogic := '0';
    signal ws2801_leds_data : std_ulogic := '0';
    signal ws2801_rgb_rd_en : std_ulogic := '0';
    
    signal ws2811_rst       : std_ulogic := '0';
    signal ws2811_start     : std_ulogic := '0';
    signal ws2811_stop      : std_ulogic := '0';
    signal ws2811_busy      : std_ulogic := '0';
    signal ws2811_vsync     : std_ulogic := '0';
    signal ws2811_slow_mode : std_ulogic := '0';
    signal ws2811_leds_data : std_ulogic := '0';
    signal ws2811_rgb_rd_en : std_ulogic := '0';
    
    signal ws2812_rst       : std_ulogic := '0';
    signal ws2812_start     : std_ulogic := '0';
    signal ws2812_stop      : std_ulogic := '0';
    signal ws2812_busy      : std_ulogic := '0';
    signal ws2812_vsync     : std_ulogic := '0';
    signal ws2812_leds_data : std_ulogic := '0';
    signal ws2812_rgb_rd_en : std_ulogic := '0';
    
    signal fifo_rd_en   : std_ulogic := '0';
    signal fifo_dout    : std_ulogic_vector(23 downto 0) := x"000000";
    signal fifo_empty   : std_ulogic := '0';
    
begin

    BUSY        <= ws2801_busy or ws2811_busy or ws2812_busy;
    LEDS_CLK    <= ws2801_leds_clk;
    
    with MODE select LEDS_DATA <=
        ws2801_leds_data when "00",
        ws2811_leds_data when "01",
        ws2811_leds_data when "10",
        ws2812_leds_data when others;
    
    ws2801_rst  <= '1' when MODE/="00" else '0';
    ws2811_rst  <= '1' when MODE/="01" and MODE/="10" else '0';
    ws2812_rst  <= '1' when MODE/="11" else '0';
    
    ws2801_start    <= cur_reg.start;
    ws2811_start    <= cur_reg.start;
    ws2812_start    <= cur_reg.start;
    
    ws2801_stop     <= fifo_empty;
    ws2811_stop     <= fifo_empty;
    ws2812_stop     <= fifo_empty;
    
    ws2811_slow_mode    <= '1' when MODE="10" else '0';
    fifo_rd_en          <= ws2801_rgb_rd_en or ws2811_rgb_rd_en or ws2812_rgb_rd_en;
    
    FIFO_inst : entity work.ASYNC_FIFO
        generic map (
            WIDTH   => 24,
            DEPTH   => MAX_LED_COUNT
        )
        port map (
            CLK => CLK,
            RST => RST,
            
            DIN     => cur_reg.fifo_din,
            RD_EN   => fifo_rd_en,
            WR_EN   => cur_reg.fifo_wr_en,
            
            DOUT    => fifo_dout,
            EMPTY   => fifo_empty
        );
    
    LED_CONTROL_WS2801_inst : entity work.LED_CONTROL_WS2801
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD,
            LEDS_CLK_PERIOD => WS2801_LEDS_CLK_PERIOD
        )
        port map (
            CLK => CLK,
            RST => ws2801_rst,
            
            START       => ws2801_start,
            STOP        => ws2801_stop,
            RGB         => fifo_dout,
            
            BUSY    => ws2801_busy,
            VSYNC   => ws2801_vsync,
            
            RGB_RD_EN   => ws2801_rgb_rd_en,
            LEDS_CLK    => ws2801_leds_clk,
            LEDS_DATA   => ws2801_leds_data
        );
    
    LED_CONTROL_WS2811_inst : entity work.LED_CONTROL_WS2811
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD
        )
        port map (
            CLK => CLK,
            RST => ws2811_rst,
            
            START       => ws2811_start,
            STOP        => ws2811_stop,
            SLOW_MODE   => ws2811_slow_mode,
            RGB         => fifo_dout,
            
            BUSY    => ws2811_busy,
            VSYNC   => ws2811_vsync,
            
            RGB_RD_EN   => ws2811_rgb_rd_en,
            LEDS_DATA   => ws2811_leds_data
        );
    
    LED_CONTROL_WS2812_inst : entity work.LED_CONTROL_WS2812
        generic map (
            CLK_IN_PERIOD   => CLK_IN_PERIOD
        )
        port map (
            CLK => CLK,
            RST => ws2812_rst,
            
            START       => ws2812_start,
            STOP        => ws2812_stop,
            RGB         => fifo_dout,
            
            BUSY    => ws2812_busy,
            VSYNC   => ws2812_vsync,
            
            RGB_RD_EN   => ws2812_rgb_rd_en,
            LEDS_DATA   => ws2812_leds_data
        );
    
    stm_proc : process(cur_reg, LED_RGB_WR_EN, LED_RGB, LED_VSYNC,
        ws2801_busy, ws2811_busy, ws2812_busy, fifo_rd_en, led_vsync_q)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        
        r   := cr;
        
        r.fifo_wr_en    := '0';
        r.fifo_din      := LED_RGB;
        r.start         := '0';
        
        case cr.state is
            
            when GETTING_FRAME =>
                r.fifo_wr_en    := not LED_VSYNC and LED_RGB_WR_EN;
                if led_vsync_q='0' and LED_VSYNC='1' then
                    r.state := WAITING_FOR_LED_START_IDLE;
                end if;
            
            when WAITING_FOR_LED_START_IDLE =>
                if (ws2801_busy or ws2811_busy or ws2812_busy)='0' then
                    r.state := STARTING;
                end if;
            
            when STARTING =>
                r.start := '1';
                if (ws2801_busy or ws2811_busy or ws2812_busy)='1' then
                    r.state := WAITING_FOR_LED_END_IDLE;
                end if;
            
            when WAITING_FOR_LED_END_IDLE =>
                if
                    (
                        (not ws2801_busy or ws2801_vsync) and
                        (not ws2811_busy or ws2811_vsync) and
                        (not ws2812_busy or ws2812_vsync)
                    )='1'
                then
                    r.state := WAITING_FOR_FRAME_START;
                end if;
            
            when WAITING_FOR_FRAME_START =>
                if led_vsync_q='1' and LED_VSYNC='0' then
                    r.fifo_wr_en    := LED_RGB_WR_EN;
                    r.state         := GETTING_FRAME;
                end if;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        next_reg    <= r;
        
    end process;
    
    stm_sync_proc : process(CLK, RST)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg     <= next_reg;
            led_vsync_q <= LED_VSYNC;
        end if;
    end process;
    
end rtl;

