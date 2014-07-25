----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    11:25:23 07/22/2014 
-- Module Name:    TMDS_CHANNEL_BITSYNC - rtl 
-- Project Name:   TMDS_CHANNEL_DECODER
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
library UNISIM;
use UNISIM.VComponents.all;

entity TMDS_CHANNEL_BITSYNC is
    generic (
        SEARCH_TIMER_BITS   : natural := 13
    );
    port (
        PIX_CLK_X2  : in std_ulogic;
        PIX_CLK     : in std_ulogic;
        RST         : in std_ulogic;
        
        DIN : in std_ulogic_vector(9 downto 0);
        
        BITSLIP     : out std_ulogic := '0';
        FLIP_GEAR   : out std_ulogic := '0';
        SYNCED      : out std_ulogic := '0'
    );
end TMDS_CHANNEL_BITSYNC;

architecture rtl of TMDS_CHANNEL_BITSYNC is
    
    type tokens_type is
        array(0 to 3) of
        std_ulogic_vector(9 downto 0);
    
    type state_type is (
        SEARCH,
        SHIFT,
        FOUND_TOKEN,
        FINISHED
        );
    
    type reg_type is record
        state           : state_type;
        search_timer    : unsigned(SEARCH_TIMER_BITS-1 downto 0);
        tok_cnt         : unsigned(3 downto 0);
        bitslip_cnt     : unsigned(3 downto 0);
    end record;
    
    constant ctrl_tokens    : tokens_type := (
        "1101010100", "0010101011", "0101010100", "1010101011"
        );
        
    constant reg_type_def   : reg_type := (
        state           => SEARCH,
        search_timer    => (others => '0'),
        tok_cnt         => "0000",
        bitslip_cnt     => "0000"
        );
    
    signal tok_detected     : boolean := false;
    signal tok_detected_q   : boolean := false;
    signal new_tok_detected : boolean := false;
    
    signal bitslip_x2, bitslip_x2_q    : std_ulogic := '0';
    
    signal cur_reg, next_reg    : reg_type := reg_type_def;
    
begin
    
    ---------------------
    --- static routes ---
    ---------------------
    
    -- FLIP_GEAR: issued bitslip between four and eight times
    FLIP_GEAR   <= cur_reg.bitslip_cnt(3);
    BITSLIP     <= bitslip_x2 and not bitslip_x2_q;
    SYNCED      <= '1' when cur_reg.state=FINISHED else '0';
    
    new_tok_detected    <= tok_detected and not tok_detected_q;
    
    
    -----------------
    --- processes ---
    -----------------
    
    process(PIX_CLK)
    begin
        if rising_edge(PIX_CLK) then
            tok_detected    <=
                DIN = ctrl_tokens(0) or
                DIN = ctrl_tokens(1) or
                DIN = ctrl_tokens(2) or
                DIN = ctrl_tokens(3);
            tok_detected_q  <= tok_detected;
        end if;
    end process;
    
    bitslip_sync_proc : process(PIX_CLK_X2)
    begin
        if rising_edge(PIX_CLK_X2) then
            bitslip_x2  <= '0';
            if cur_reg.state=SHIFT then
                bitslip_x2  <= '1';
            end if;
            bitslip_x2_q    <= bitslip_x2;
        end if;
    end process;
    
    -------------------------------------
    --- synchronisation state machine ---
    -------------------------------------
    
    stm_proc : process(RST, cur_reg, tok_detected, new_tok_detected)
        alias cr    : reg_type is cur_reg;
        variable r  : reg_type;
    begin
        r           := cr;
        
        case cr.state is
            
            when SEARCH =>
                r.search_timer  := cr.search_timer+1;
                if cr.search_timer(SEARCH_TIMER_BITS-1)='1' then
                    -- search timeout, shift one bit
                    r.state := SHIFT;
                end if;
                if new_tok_detected then
                    r.tok_cnt   := "0001";
                    r.state     := FOUND_TOKEN;
                end if;
            
            when SHIFT =>
                r.search_timer  := (others => '0');
                r.bitslip_cnt   := cr.bitslip_cnt+1;
                r.state         := SEARCH;
            
            when FOUND_TOKEN =>
                if tok_detected then
                    r.tok_cnt   := cr.tok_cnt+1;
                    if cr.tok_cnt(3)='1' then
                        -- got eight consecutive control tokens
                        r.state := FINISHED;
                    end if;
                else
                    -- false positive, not a blank period
                    r.state := SEARCH;
                end if;
            
            when FINISHED =>
                -- idle state
                null;
            
        end case;
        if RST='1' then
            r   := reg_type_def;
        end if;
        next_reg    <= r;
    end process;
    
    sync_stm_proc : process(PIX_CLK)
    begin
        if rising_edge(PIX_CLK) then
            cur_reg <= next_reg;
        end if;
    end process;
    
end rtl;

