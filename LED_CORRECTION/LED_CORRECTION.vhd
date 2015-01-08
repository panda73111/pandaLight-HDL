----------------------------------------------------------------------------------
-- Engineer: Sebastian Hther
-- 
-- Create Date:    11:12:37 08/03/2014 
-- Module Name:    LED_CORRECTION - rtl 
-- Project Name:   LED_CORRECTION
-- Tool versions:  Xilinx ISE 14.7
-- Description: 
--  
-- Additional Comments: 
--   These configuration registers can only be set while LED_IN_VSYNC is high and are reset
--   to zero when RST is high, using the CFG_* inputs:
--   
--    [0] = LED_COUNT      : The number of LEDs around the TV
--    [1] = START_LED_NUM  : The index (from top left clockwise) of the first LED in the chain
--    [2] = FRAME_DELAY    : The number of frames to be buffered before being transmitted
--    [3] = RGB_MODE       : The LED RGB channel order:
--                             0 = R G B
--                             1 = R B G
--                             2 = G R B
--                             3 = G B R
--                             4 = B R G
--                             5 = B G R
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
use work.help_funcs.all;

entity LED_CORRECTION is
    generic (
        MAX_LED_COUNT   : natural;
        MAX_FRAME_COUNT : natural
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CFG_ADDR    : in std_ulogic_vector(1 downto 0);
        CFG_WR_EN   : in std_ulogic := '0';
        CFG_DATA    : in std_ulogic_vector(7 downto 0) := x"00";
        
        LED_IN_VSYNC    : in std_ulogic;
        LED_IN_NUM      : in std_ulogic_vector(7 downto 0);
        LED_IN_RGB      : in std_ulogic_vector(23 downto 0);
        LED_IN_WR_EN    : in std_ulogic;
        
        LED_OUT_VSYNC   : out std_ulogic := '0';
        LED_OUT_RGB     : out std_ulogic_vector(23 downto 0) := x"000000";
        LED_OUT_VALID   : out std_ulogic := '0'
    );
end LED_CORRECTION;

architecture rtl of LED_CORRECTION is
    
    constant BUFFER_SIZE        : natural := MAX_FRAME_COUNT*MAX_LED_COUNT;
    constant FRAME_COUNT_BITS   : natural := log2(MAX_FRAME_COUNT);
    constant LED_COUNT_BITS     : natural := log2(MAX_LED_COUNT);
    constant BUF_ADDR_BITS      : natural := log2(BUFFER_SIZE);
    
    type state_type is (
        WAITING_FOR_BLANK,
        WAITING_FOR_LEDS,
        WRITING_LEDS,
        CHECKING_DELAY_START,
        BEGINNING_READING_LEDS,
        WAITING_FOR_BUFFER,
        READING_LEDS,
        CHANGING_FRAME
        );
    
    type reg_type is record
        state           : state_type;
        rd_p            : unsigned(BUF_ADDR_BITS-1 downto 0);
        rd_led_i        : unsigned(LED_COUNT_BITS-1 downto 0);
        rd_led_cnt      : unsigned(LED_COUNT_BITS-1 downto 0);
        rd_frame_p      : unsigned(BUF_ADDR_BITS-1 downto 0);
        wr_frame_p      : unsigned(BUF_ADDR_BITS-1 downto 0);
        rd_frame_i      : unsigned(FRAME_COUNT_BITS-1 downto 0);
        wr_frame_i      : unsigned(FRAME_COUNT_BITS-1 downto 0);
        reading_leds    : boolean;
        frame_read      : boolean;
        out_valid       : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => WAITING_FOR_BLANK,
        rd_p            => (others => '0'),
        rd_led_i        => (others => '0'),
        rd_led_cnt      => (others => '0'),
        rd_frame_p      => (others => '0'),
        wr_frame_p      => (others => '0'),
        rd_frame_i      => (others => '0'),
        wr_frame_i      => (others => '0'),
        reading_leds    => false,
        frame_read      => true,
        out_valid       => '0'
        );
    
    signal rst_stm              : std_ulogic := '0';
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    signal led_buf_rd_addr  : std_ulogic_vector(BUF_ADDR_BITS-1 downto 0) := (others => '0');
    signal led_buf_wr_addr  : std_ulogic_vector(BUF_ADDR_BITS-1 downto 0) := (others => '0');
    signal led_buf_dout     : std_ulogic_vector(23 downto 0) := x"000000";
    signal in_rgb_corrected : std_ulogic_vector(23 downto 0) := x"000000";
    
    -- configuration registers
    signal led_count        : std_ulogic_vector(7 downto 0) := x"00";
    signal start_led_num    : std_ulogic_vector(7 downto 0) := x"00";
    signal frame_delay      : std_ulogic_vector(7 downto 0) := x"00";
    signal rgb_mode         : std_ulogic_vector(2 downto 0) := "000";
    
begin
    
    LED_OUT_VSYNC   <= not cur_reg.out_valid;
    LED_OUT_RGB     <= led_buf_dout;
    LED_OUT_VALID   <= cur_reg.out_valid;
    
    rst_stm <= RST or CFG_WR_EN;
    
    led_buf_rd_addr <= stdulv(cur_reg.rd_p);
    led_buf_wr_addr <= LED_IN_NUM+cur_reg.wr_frame_p;
    
    DUAL_PORT_RAM_inst : entity work.DUAL_PORT_RAM
        generic map (
            WIDTH   => 24,
            DEPTH   => BUFFER_SIZE
        )
        port map (
            CLK => CLK,
            
            RD_ADDR => led_buf_rd_addr,
            WR_ADDR => led_buf_wr_addr,
            WR_EN   => LED_IN_WR_EN,
            DIN     => LED_IN_RGB,
            
            DOUT    => led_buf_dout
        );
    
    cfg_proc : process(RST, CLK)
    begin
        if RST='1' then
            led_count       <= x"00";
            start_led_num   <= x"00";
            frame_delay     <= x"00";
            rgb_mode        <= "000";
        elsif rising_edge(CLK) then
            if CFG_WR_EN='1' and LED_IN_VSYNC='1' then
                case CFG_ADDR is
                    when "00"   => led_count        <= CFG_DATA;
                    when "01"   => start_led_num    <= CFG_DATA;
                    when "10"   => frame_delay      <= CFG_DATA;
                    when others => rgb_mode         <= CFG_DATA(2 downto 0);
                end case;
            end if;
        end if;
    end process;
    
    correct_in_rgb_proc : process(LED_IN_RGB, rgb_mode)
        alias rgb is in_rgb_corrected;
        alias r is LED_IN_RGB(23 downto 16);
        alias g is LED_IN_RGB(15 downto 8);
        alias b is LED_IN_RGB(7 downto 0);
    begin
        case rgb_mode is
            when "001" =>  rgb  <= r & b & g;
            when "010" =>  rgb  <= g & r & b;
            when "011" =>  rgb  <= g & b & r;
            when "100" =>  rgb  <= b & r & g;
            when "101" =>  rgb  <= b & g & r;
            when others => rgb  <= r & g & b;
        end case;
    end process;
    
    stm_proc : process(RST, rst_stm, cur_reg, LED_IN_VSYNC, LED_IN_NUM, LED_IN_RGB, LED_IN_WR_EN,
        led_count, start_led_num, frame_delay, in_rgb_corrected)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.out_valid := '0';
        
        case cr.state is
            
            when WAITING_FOR_BLANK =>
                r.rd_p          := (others => '0');
                r.rd_led_i      := (others => '0');
                r.rd_led_cnt    := (others => '0');
                r.rd_frame_p    := (others => '0');
                r.wr_frame_p    := (others => '0');
                r.rd_frame_i    := (others => '0');
                r.wr_frame_i    := (others => '0');
                r.reading_leds  := false;
                if frame_delay=0 then
                    r.reading_leds  := true;
                end if;
                if LED_IN_VSYNC='1' then
                    r.state := WAITING_FOR_LEDS;
                end if;
            
            when WAITING_FOR_LEDS =>
                if LED_IN_WR_EN='1' then
                    r.state := WRITING_LEDS;
                end if;
                if
                    LED_IN_VSYNC='1' and
                    not cr.frame_read
                then
                    r.state := CHECKING_DELAY_START;
                end if;
            
            when CHECKING_DELAY_START =>
                r.state := CHANGING_FRAME;
                if
                    cr.wr_frame_i=frame_delay or
                    cr.reading_leds
                then
                    r.state := BEGINNING_READING_LEDS;
                end if;
            
            when WRITING_LEDS =>
                r.frame_read    := false;
                if LED_IN_VSYNC='1' then
                    r.state := WAITING_FOR_LEDS;
                end if;
            
            when BEGINNING_READING_LEDS =>
                r.reading_leds  := true;
                r.rd_led_cnt    := (others => '0');
                r.rd_led_i      := uns(start_led_num);
                r.rd_p          := uns(start_led_num+cr.rd_frame_p);
                r.state         := WAITING_FOR_BUFFER;
            
            when WAITING_FOR_BUFFER =>
                r.out_valid     := '1';
                r.rd_led_cnt    := uns(1, LED_COUNT_BITS);
                r.rd_p          := cr.rd_p+1;
                r.state         := READING_LEDS;
            
            when READING_LEDS =>
                r.out_valid     := '1';
                r.rd_p          := cr.rd_p+1;
                r.rd_led_i      := cr.rd_led_i+1;
                r.rd_led_cnt    := cr.rd_led_cnt+1;
                if cr.rd_p=led_count-1 then
                    r.rd_p  := (others => '0');
                end if;
                if cr.rd_led_i=led_count-1 then
                    r.rd_led_i  := (others => '0');
                    r.rd_p      := uns(start_led_num+cr.rd_frame_p);
                end if;
                if cr.rd_led_cnt=led_count-1 then
                    r.state := CHANGING_FRAME;
                end if;
            
            when CHANGING_FRAME =>
                r.frame_read    := true;
                r.wr_frame_i    := cr.wr_frame_i+1;
                r.wr_frame_p    := uns(led_count+cr.wr_frame_p);
                if cr.reading_leds then
                    r.rd_frame_i    := cr.rd_frame_i+1;
                    r.rd_frame_p    := uns(led_count+cr.rd_frame_p);
                    r.rd_p          := uns(led_count+cr.rd_p);
                end if;
                if cr.wr_frame_i=frame_delay then
                    r.wr_frame_i    := (others => '0');
                    r.wr_frame_p    := (others => '0');
                end if;
                if cr.rd_frame_i=frame_delay then
                    r.rd_p          := (others => '0');
                    r.rd_frame_i    := (others => '0');
                    r.rd_frame_p    := (others => '0');
                end if;
                r.state     := WAITING_FOR_LEDS;
            
        end case;
        
        if rst_stm='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;
    
    sync_stm_proc : process(rst_stm, CLK)
    begin
        if rst_stm='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;

