----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    10:43:54 07/28/2014 
-- Module Name:    TMDS_DECODER - rtl 
-- Project Name:   TMDS_DECODER
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
use work.help_funcs.all;

entity TMDS_DECODER is
    port (
        PIX_CLK         : in std_ulogic;
        PIX_CLK_X2      : in std_ulogic;
        PIX_CLK_X10     : in std_ulogic;
        RST             : in std_ulogic;
        
        SERDESSTROBE    : in std_ulogic;
        
        CHANNELS_IN     : in std_ulogic_vector(2 downto 0);
        
        RAW_DATA        : out std_ulogic_vector(14 downto 0) := (others => '0');
        RAW_DATA_VALID  : out std_ulogic := '0';
        
        VSYNC           : out std_ulogic := '0';
        HSYNC           : out std_ulogic := '0';
        RGB             : out std_ulogic_vector(23 downto 0) := x"000000";
        RGB_VALID       : out std_ulogic := '0';
        AUX_DATA        : out std_ulogic_vector(8 downto 0) := (others => '0');
        AUX_DATA_VALID  : out std_ulogic := '0'
    );
end TMDS_DECODER;

architecture rtl of TMDS_DECODER is
    
    type chs_raw_data_type is
        array(0 to 2) of
        std_ulogic_vector(9 downto 0);
    
    type chs_raw_data_x2_type is
        array(0 to 2) of
        std_ulogic_vector(4 downto 0);
    
    type chs_rgb_type is
        array(0 to 2) of
        std_ulogic_vector(7 downto 0);
    
    type chs_ctl_type is
        array(0 to 2) of
        std_ulogic_vector(1 downto 0);
    
    type chs_aux_type is
        array(0 to 2) of
        std_ulogic_vector(3 downto 0);
    
    type state_type is (
        RESET_CHANNEL_DECODERS,
        WAIT_FOR_SYNC,
        WAIT_FOR_VBLANK,
        PASSTHROUGH
        );
    
    type reg_type is record
        state       : state_type;
        dec_rst     : std_ulogic;
        hsync       : std_ulogic;
        vsync       : std_ulogic;
        rgb         : std_ulogic_vector(23 downto 0);
        rgb_valid   : std_ulogic;
        aux         : std_ulogic_vector(7 downto 0);
        aux_valid   : std_ulogic;
        watchdog    : unsigned(13 downto 0);
    end record;
    
    constant reg_type_def   : reg_type := (
        state       => WAIT_FOR_SYNC,
        dec_rst     => '1',
        hsync       => '0',
        vsync       => '0',
        rgb         => (others => '0'),
        rgb_valid   => '0',
        aux         => x"00",
        aux_valid   => '0',
        watchdog    => (others => '0')
        );
    
    signal chs_synced       : std_ulogic_vector(0 to 2) := "000";
    signal chs_raw_data     : chs_raw_data_type := (others => (others => '0'));
    signal chs_raw_data_x2  : chs_raw_data_x2_type := (others => "00000");
    signal chs_rgb          : chs_rgb_type := (others => x"00");
    signal chs_rgb_valid    : std_ulogic_vector(0 to 2) := "000";
    signal chs_ctl          : chs_ctl_type := (others => "00");
    signal chs_ctl_valid    : std_ulogic_vector(0 to 2) := "000";
    signal chs_aux          : chs_aux_type := (others => "0000");
    signal chs_aux_valid    : std_ulogic_vector(0 to 2) := "000";
    signal chs_gb_valid     : std_ulogic_vector(0 to 2) := "000";
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
    attribute keep  : boolean;
    attribute keep of chs_synced    : signal is true;
    
begin
    
    RAW_DATA        <= chs_raw_data_x2(2) & chs_raw_data_x2(1) & chs_raw_data_x2(0);
    RAW_DATA_VALID  <= '1' when chs_synced="111" else '0';
    
    HSYNC           <= cur_reg.hsync;
    VSYNC           <= cur_reg.vsync;
    RGB_VALID       <= cur_reg.rgb_valid;
    AUX_DATA_VALID  <= cur_reg.aux_valid;
    
    TMDS_CHANNEL_DECODERs_gen : for i in 0 to 2 generate
        
        TMDS_CHANNEL_DECODER_inst : entity work.TMDS_CHANNEL_DECODER
            generic map (
                CHANNEL => i
            )
            port map (
                PIX_CLK     => PIX_CLK,
                PIX_CLK_X2  => PIX_CLK_X2,
                PIX_CLK_X10 => PIX_CLK_X10,
                RST         => cur_reg.dec_rst,
                
                SERDESSTROBE    => SERDESSTROBE,
                
                CHANNEL_IN  => CHANNELS_IN(i),
                
                SYNCED          => chs_synced(i),
                RAW_DATA        => chs_raw_data(i),
                RAW_DATA_X2     => chs_raw_data_x2(i),
                RGB             => chs_rgb(i),
                RGB_VALID       => chs_rgb_valid(i),
                CTL             => chs_ctl(i),
                CTL_VALID       => chs_ctl_valid(i),
                AUX_DATA        => chs_aux(i),
                AUX_DATA_VALID  => chs_aux_valid(i),
                GUARDBAND_VALID => chs_gb_valid(i)
            );
        
    end generate;
    
    passthrough_proc : process(PIX_CLK)
    begin
        if rising_edge(PIX_CLK) then
            RGB         <= chs_rgb(2) & chs_rgb(1) & chs_rgb(0);
            AUX_DATA    <= chs_aux(0)(2) & chs_aux(1) & chs_aux(2);
        end if;
    end process;
    
    stm_proc : process(RST, cur_reg, chs_synced, chs_aux,
        chs_ctl_valid, chs_ctl, chs_rgb_valid, chs_aux_valid)
        alias cr is cur_reg;
        variable r  : reg_type := reg_type_def;
    begin
        r           := cr;
        r.dec_rst   := '0';
        r.rgb_valid := '0';
        r.aux_valid := '0';
        
        case cr.state is
            
            when RESET_CHANNEL_DECODERS =>
                r.dec_rst   := '1';
                r.vsync     := '0';
                r.hsync     := '0';
                r.watchdog  := (others => '0');
                r.state     := WAIT_FOR_SYNC;
            
            when WAIT_FOR_SYNC =>
                if chs_synced="111" then
                    -- all channels have valid signals
                    r.state := WAIT_FOR_VBLANK;
                end if;
            
            when WAIT_FOR_VBLANK =>
                if chs_ctl_valid(0)='1' and chs_ctl(0)="00" then
                    -- control period, vsync=hsync=0
                    r.state := PASSTHROUGH;
                end if;
            
            when PASSTHROUGH =>
                r.watchdog  := cr.watchdog+1;
                r.rgb_valid := chs_rgb_valid(2) and chs_rgb_valid(1) and chs_rgb_valid(0);
                r.aux_valid := chs_aux_valid(2) and chs_aux_valid(1) and chs_aux_valid(0);
                if chs_ctl_valid(0)='1' then
                    r.vsync := chs_ctl(0)(1);
                    r.hsync := chs_ctl(0)(0);
                end if;
                if chs_aux_valid(0)='1' then
                    r.vsync := chs_aux(0)(1);
                    r.hsync := chs_aux(0)(0);
                end if;
                if chs_synced/="111" then
                    r.state := RESET_CHANNEL_DECODERS;
                end if;
                if chs_ctl_valid="111" then
                    r.watchdog  := (others => '0');
                end if;
                if cr.watchdog(reg_type.watchdog'high)='1' then
                    r.state := RESET_CHANNEL_DECODERS;
                end if;
            
        end case;
        
        if RST='1' then
            r   := reg_type_def;
        end if;
        
        next_reg    <= r;
    end process;
    
    sync_stm_proc : process(RST, PIX_CLK)
    begin
        if RST='1' then
            cur_reg <= reg_type_def;
        elsif rising_edge(PIX_CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end;
