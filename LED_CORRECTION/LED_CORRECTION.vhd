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
--  
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
        MAX_BUFFER_SIZE : natural
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
    
    constant MAX_FRAME_COUNT    : natural := MAX_BUFFER_SIZE/MAX_LED_COUNT;
    constant BUF_ADDR_BITS      : natural := log2(MAX_BUFFER_SIZE);
    
    type led_buf_type is
        array (0 to MAX_BUFFER_SIZE-1) of
        std_ulogic_vector(23 downto 0);
    
    signal led_buf              : led_buf_type;
    
    type state_type is (
        WAIT_FOR_BLANK,
        WAIT_FOR_LED,
        WRITE_LED,
        CHECK_DELAY_START,
        BEGIN_READ_LEDS,
        WAIT_FOR_DATA,
        READ_LED,
        CHANGE_FRAME
        );
    
    type reg_type is record
        state           : state_type;
        wr_en           : std_ulogic;
        din             : std_ulogic_vector(23 downto 0);
        rd_p            : natural range 0 to MAX_BUFFER_SIZE-1;
        wr_p            : natural range 0 to MAX_BUFFER_SIZE-1;
        rd_led_i        : natural range 0 to MAX_LED_COUNT-1;
        rd_led_cnt      : natural range 0 to MAX_LED_COUNT-1;
        rd_frame_p      : natural range 0 to MAX_BUFFER_SIZE-1;
        wr_frame_p      : natural range 0 to MAX_BUFFER_SIZE-1;
        rd_frame_i      : natural range 0 to MAX_FRAME_COUNT-1;
        wr_frame_i      : natural range 0 to MAX_FRAME_COUNT-1;
        start_read      : boolean;
        finished_read   : boolean;
        out_valid       : std_ulogic;
    end record;
    
    constant reg_type_def   : reg_type := (
        state           => WAIT_FOR_BLANK,
        wr_en           => '0',
        din             => x"000000",
        rd_p            => 0,
        wr_p            => 0,
        rd_led_i        => 0,
        rd_led_cnt      => 0,
        rd_frame_p      => 0,
        wr_frame_p      => 0,
        rd_frame_i      => 0,
        wr_frame_i      => 0,
        start_read      => false,
        finished_read   => true,
        out_valid       => '0'
        );
    
    signal stm_rst              : std_ulogic := '0';
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
    
    LED_OUT_VSYNC   <= cur_reg.out_valid;
    LED_OUT_RGB     <= led_buf_dout;
    LED_OUT_VALID   <= cur_reg.out_valid;
    
    stm_rst <= CFG_WR_EN;
    
    led_buf_rd_addr <= stdulv(cur_reg.rd_p, BUF_ADDR_BITS);
    led_buf_wr_addr <= stdulv(cur_reg.wr_p, BUF_ADDR_BITS);
    
    DUAL_PORT_RAM_inst : entity work.DUAL_PORT_RAM
        generic map (
            WIDTH   => 24,
            DEPTH   => MAX_BUFFER_SIZE
        )
        port map (
            CLK => CLK,
            
            RD_ADDR => led_buf_rd_addr,
            WR_ADDR => led_buf_wr_addr,
            WR_EN   => cur_reg.wr_en,
            DIN     => cur_reg.din,
            
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
            if CFG_WR_EN='1' and LED_IN_VSYNC='0' then
                case CFG_ADDR is
                    when "00" => led_count      <= CFG_DATA;
                    when "01" => start_led_num  <= CFG_DATA;
                    when "10" => frame_delay    <= CFG_DATA;
                    when "11" => rgb_mode       <= CFG_DATA(2 downto 0);
                    when others => null;
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
    
    stm_proc : process(RST, stm_rst, cur_reg, LED_IN_VSYNC, LED_IN_NUM, LED_IN_RGB, LED_IN_WR_EN,
        led_count, start_led_num, frame_delay, in_rgb_corrected)
        alias cr is cur_reg;
        variable r  : reg_type;
    begin
        r           := cr;
        r.wr_en     := '0';
        r.out_valid := '0';
        
        case cr.state is
            
            when WAIT_FOR_BLANK =>
                r.rd_p          := 0;
                r.wr_p          := 0;
                r.rd_led_i      := 0;
                r.rd_led_cnt    := 0;
                r.rd_frame_p    := 0;
                r.wr_frame_p    := 0;
                r.rd_frame_i    := 0;
                r.wr_frame_i    := 0;
                r.start_read    := false;
                r.finished_read := true;
                if frame_delay=0 then
                    r.start_read    := true;
                end if;
                if LED_IN_VSYNC='0' then
                    r.state := WAIT_FOR_LED;
                end if;
            
            when WAIT_FOR_LED =>
                if LED_IN_WR_EN='1' then
                    r.state := WRITE_LED;
                end if;
                if
                    LED_IN_VSYNC='0' and
                    not cr.finished_read
                then
                    r.state := CHECK_DELAY_START;
                end if;
            
            when CHECK_DELAY_START =>
                r.state := CHANGE_FRAME;
                if
                    cr.wr_frame_i=frame_delay or
                    cr.start_read
                then
                    r.state := BEGIN_READ_LEDS;
                end if;
            
            when WRITE_LED =>
                r.finished_read := false;
                r.din           := in_rgb_corrected;
                r.wr_en         := '1';
                r.wr_p          := cr.wr_frame_p+int(LED_IN_NUM);
                r.state         := WAIT_FOR_LED;
            
            when BEGIN_READ_LEDS =>
                r.start_read    := true;
                r.rd_led_cnt    := 0;
                r.rd_led_i      := int(start_led_num);
                r.rd_p          := cr.rd_frame_p+int(start_led_num);
                r.state         := WAIT_FOR_DATA;
            
            when WAIT_FOR_DATA =>
                r.out_valid     := '1';
                r.rd_led_cnt    := 1;
                r.rd_p          := cr.rd_p+1;
                r.state         := READ_LED;
            
            when READ_LED =>
                r.out_valid     := '1';
                r.rd_p          := cr.rd_p+1;
                r.rd_led_i      := cr.rd_led_i+1;
                r.rd_led_cnt    := cr.rd_led_cnt+1;
                if cr.rd_p=led_count-1 then
                    r.rd_p  := 0;
                end if;
                if cr.rd_led_i=led_count-1 then
                    r.rd_led_i  := 0;
                    r.rd_p      := cr.rd_frame_p+int(start_led_num);
                end if;
                if cr.rd_led_cnt=led_count-1 then
                    r.state := CHANGE_FRAME;
                end if;
            
            when CHANGE_FRAME =>
                r.finished_read := true;
                r.wr_frame_i    := cr.wr_frame_i+1;
                r.wr_frame_p    := cr.wr_frame_p+int(led_count);
                if cr.start_read then
                    r.rd_frame_i    := cr.rd_frame_i+1;
                    r.rd_frame_p    := cr.rd_frame_p+int(led_count);
                    r.rd_p          := cr.rd_p+int(led_count);
                end if;
                if cr.wr_frame_i=frame_delay then
                    r.wr_frame_i    := 0;
                    r.wr_frame_p    := 0;
                    r.wr_p          := 0;
                end if;
                if cr.rd_frame_i=frame_delay then
                    r.rd_p          := 0;
                    r.rd_frame_i    := 0;
                    r.rd_frame_p    := 0;
                end if;
                r.state     := WAIT_FOR_LED;
            
        end case;
        
        if (RST or stm_rst)='1' then
            r   := reg_type_def;
        end if;
        next_reg    <= r;
    end process;
    
    stm_sync_proc : process(RST, CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;

