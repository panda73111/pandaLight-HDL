----------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
-- 
-- Create Date:    14:58:34 07/02/2014 
-- Design Name:    LED_COLOR_EXTRACTOR
-- Module Name:    led_ppm_visualizer - rtl 
-- Tool versions:  Xilinx ISE 14.7
-- Description:
--   This components gets LED colors from the LED_COLOR_EXTRACTOR instance
--   and places them at the respective LED position within the video source
--   frame which is saved as a PPM image
-- Revision: 0
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;
library std;
use std.textio.all;
use work.help_funcs.all;
use work.txt_util.all;

entity led_ppm_visualizer is
    generic (
        FILENAME_BASE       : string;
        FILENAME_START_NUM  : natural := 0;
        FRAMES_TO_SAVE      : natural;
        STOP_SIM            : boolean;
        WHITESPACE_CHAR     : character := character'val(13);
        MAX_WIDTH           : natural := 1920;
        MAX_HEIGHT          : natural := 1080;
        R_BITS              : natural range 1 to 12 := 8;
        G_BITS              : natural range 1 to 12 := 8;
        B_BITS              : natural range 1 to 12 := 8
    );
    port (
        CLK : in std_ulogic;
        RST : in std_ulogic;
        
        CFG_ADDR    : in std_ulogic_vector(3 downto 0);
        CFG_WR_EN   : in std_ulogic;
        CFG_DATA    : in std_ulogic_vector(7 downto 0);
        
        FRAME_VSYNC     : in std_ulogic;
        FRAME_RGB_WR_EN : in std_ulogic;
        FRAME_RGB       : in std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        
        LED_VSYNC       : in std_ulogic;
        LED_RGB_VALID   : in std_ulogic;
        LED_RGB         : in std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        LED_NUM         : in std_ulogic_vector(7 downto 0)
    );
end led_ppm_visualizer;

architecture rtl of led_ppm_visualizer is
    constant MAXVAL     : natural := (2**(max(R_BITS, max(G_BITS, B_BITS))))-1;
    constant RGB_BITS   : natural := R_BITS+G_BITS+B_BITS;
    
    -- configuration registers
    signal hor_led_cnt      : std_ulogic_vector(7 downto 0) := x"00";
    signal hor_led_width    : std_ulogic_vector(7 downto 0) := x"00";
    signal hor_led_height   : std_ulogic_vector(7 downto 0) := x"00";
    signal hor_led_step     : std_ulogic_vector(7 downto 0) := x"00";
    signal hor_led_pad      : std_ulogic_vector(7 downto 0) := x"00";
    signal hor_led_offs     : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_cnt      : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_width    : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_height   : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_step     : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_pad      : std_ulogic_vector(7 downto 0) := x"00";
    signal ver_led_offs     : std_ulogic_vector(7 downto 0) := x"00";
    
    signal frame_width      : std_ulogic_vector(15 downto 0) := x"0000";
    signal frame_height     : std_ulogic_vector(15 downto 0) := x"0000";
    
    signal configured           : boolean := false;
    signal led_imgs_finished    : boolean := false;
    signal src_imgs_finished    : boolean := false;
    
    type char_file is file of character;
    type data_type is (BYTE, HWORD, WORD);
    
    type frame_col_type is
        array(0 to MAX_HEIGHT-1) of
        std_ulogic_vector(RGB_BITS-1 downto 0);
    
    type frame_buf_type is
        array(0 to MAX_WIDTH-1) of
        frame_col_type;
    
    function to_char(v : std_ulogic_vector) return character is
    begin
        return character'val(int(uns(v)));
    end to_char;

    procedure file_write(file f : char_file; v : std_ulogic_vector) is
        variable t : std_ulogic_vector(v'length-1 downto 0) := v;
        variable i : natural := 0;
    begin
        while i/=t'length loop
            write(f, to_char(t(i+7 downto i)));
            i := i+8;
        end loop;
    end file_write;
    
    procedure file_write(file f : char_file; constant c : character) is
    begin
        write(f, c);
    end procedure;
    
    procedure file_write(file f : char_file; constant s : string) is
        variable v : std_ulogic_vector(s'length*8-1 downto 0);
    begin
        for i in 1 to s'length loop
            write(f, s(i));
        end loop;
    end procedure;

    procedure file_write(file f : char_file; i : integer; constant t : data_type) is
    begin
        case t is
            when BYTE   => file_write(f, stdulv(uns(i, 8)));
            when HWORD  => file_write(f, stdulv(uns(i, 16)));
            when WORD   => file_write(f, stdulv(uns(i, 32)));
        end case;
    end procedure;
    
    procedure img_file_write(constant filename : string; frame_buf : in frame_buf_type) is
        file img_file   : char_file;
        variable pixel  : std_ulogic_vector(RGB_BITS-1 downto 0);
        variable r      : std_ulogic_vector(R_BITS-1 downto 0);
        variable g      : std_ulogic_vector(G_BITS-1 downto 0);
        variable b      : std_ulogic_vector(B_BITS-1 downto 0);
    begin
        report("opening file " & filename);
        file_open(img_file, filename, write_mode);
        
        -- write the file header
        file_write(img_file, "P6");                   -- magic number
        file_write(img_file, WHITESPACE_CHAR);
        file_write(img_file, str(int(frame_width)));  -- width
        file_write(img_file, WHITESPACE_CHAR);
        file_write(img_file, str(int(frame_height))); -- height
        file_write(img_file, WHITESPACE_CHAR);
        file_write(img_file, str(MAXVAL));            -- Maxval
        file_write(img_file, WHITESPACE_CHAR);
        
        for y in 0 to nat(frame_height)-1 loop
            for x in 0 to nat(frame_width)-1 loop
                pixel   := frame_buf(x)(y);
                r       := pixel(pixel'left downto pixel'left-R_BITS+1);
                g       := pixel(pixel'left-R_BITS downto B_BITS);
                b       := pixel(B_BITS-1 downto 0);
                file_write(img_file, r);
                file_write(img_file, g);
                file_write(img_file, b);
            end loop;
            --file_write(img_file, character'val(13)); -- newline
        end loop;
        
        report("closing file " & filename);
        file_close(img_file);
    end procedure;
begin
    
    cfg_proc : process(RST, CLK)
    begin
        if RST='1' then
            hor_led_cnt     <= x"00";
            hor_led_width   <= x"00";
            hor_led_height  <= x"00";
            hor_led_step    <= x"00";
            hor_led_pad     <= x"00";
            hor_led_offs    <= x"00";
            ver_led_cnt     <= x"00";
            ver_led_width   <= x"00";
            ver_led_height  <= x"00";
            ver_led_step    <= x"00";
            ver_led_pad     <= x"00";
            ver_led_offs    <= x"00";
            frame_width     <= x"0000";
            frame_height    <= x"0000";
            configured      <= false;
        elsif rising_edge(CLK) then
            if CFG_WR_EN='1' then
                case CFG_ADDR is
                    when "0000" =>  hor_led_cnt                  <= CFG_DATA;
                    when "0001" =>  hor_led_width                <= CFG_DATA;
                    when "0010" =>  hor_led_height               <= CFG_DATA;
                    when "0011" =>  hor_led_step                 <= CFG_DATA;
                    when "0100" =>  hor_led_pad                  <= CFG_DATA;
                    when "0101" =>  hor_led_offs                 <= CFG_DATA;
                    when "0110" =>  ver_led_cnt                  <= CFG_DATA;
                    when "0111" =>  ver_led_width                <= CFG_DATA;
                    when "1000" =>  ver_led_height               <= CFG_DATA;
                    when "1001" =>  ver_led_step                 <= CFG_DATA;
                    when "1010" =>  ver_led_pad                  <= CFG_DATA;
                    when "1011" =>  ver_led_offs                 <= CFG_DATA;
                    when "1100" =>  frame_width(15 downto 8)     <= CFG_DATA;
                    when "1101" =>  frame_width(7 downto 0)      <= CFG_DATA;
                    when "1110" =>  frame_height(15 downto 8)    <= CFG_DATA;
                    when others =>  frame_height(7 downto 0)     <= CFG_DATA;
                                    configured  <= true;
                end case;
            end if;
        end if;
    end process;
    
    write_src_file_proc : process
        variable filename   : string(1 to FILENAME_BASE'length+10);
        variable file_index : integer := 0;
        variable frame_buf  : frame_buf_type;
        variable x          : natural range 0 to MAX_WIDTH;
        variable y          : natural range 0 to MAX_HEIGHT;
        variable side_led_index : natural range 0 to 255;
    begin
        wait until configured;
        frame_loop: while file_index/=frames_to_save loop
            filename    := FILENAME_BASE & integer'image(file_index) & "_src.ppm";
            frame_buf   := (others => (others => (others => '0')));
            
            wait until falling_edge(FRAME_VSYNC);
            
            -- start of frame
            x   := 0;
            y   := 0;
            
            while FRAME_VSYNC='0' loop
                wait until rising_edge(CLK) or RST='1';
                
                if RST='1' then
                    next frame_loop;
                end if;
                
                if FRAME_RGB_WR_EN='0' then
                    next;
                end if;
                
                while FRAME_RGB_WR_EN='1' loop
                    frame_buf(x)(y) := FRAME_RGB;
                    x               := x+1;
                    wait until rising_edge(CLK) or RST='1';
                    
                    if RST='1' then
                        next frame_loop;
                    end if;
                end loop;
                
                -- end of line
                x   := 0;
                y   := y+1;
            end loop;
            
            img_file_write(filename, frame_buf);
            
            file_index  := file_index+1;
        end loop;
        
        src_imgs_finished   <= true;
        
        assert not stop_sim or not led_imgs_finished
            report "NONE. Saved " & integer'image(frames_to_save) & " frame(s)."
            severity FAILURE;
        
        wait;
    end process;
    
    write_led_file_proc : process
        file img_file       : char_file;
        variable filename   : string(1 to FILENAME_BASE'length+6);
        variable file_index : integer := 0;
        variable frame_buf  : frame_buf_type;
        variable led_start_x    : natural range 0 to MAX_WIDTH-1;
        variable led_end_x      : natural range 0 to MAX_WIDTH-1;
        variable led_start_y    : natural range 0 to MAX_HEIGHT-1;
        variable led_end_y      : natural range 0 to MAX_HEIGHT-1;
        variable side_led_index : natural range 0 to 255;
    begin
        wait until configured;
        frame_loop: while file_index/=frames_to_save loop
            filename    := FILENAME_BASE & integer'image(file_index) & ".ppm";
            frame_buf   := (others => (others => (others => '0')));
            
            wait until falling_edge(LED_VSYNC);
            
            while LED_VSYNC='0' loop
                wait until rising_edge(CLK) or RST='1';
                
                if RST='1' then
                    next frame_loop;
                end if;
                
                if LED_RGB_VALID='1' then
                    if LED_NUM<hor_led_cnt then
                        
                        -- top side
                        side_led_index  := int(LED_NUM);
                        led_start_x     := int(hor_led_offs+(hor_led_step*side_led_index));
                        led_end_x       := led_start_x+int(hor_led_width);
                        led_start_y     := int(hor_led_pad);
                        led_end_y       := led_start_y+int(hor_led_height);
                        
                    elsif LED_NUM<hor_led_cnt+ver_led_cnt then
                        
                        -- right side
                        side_led_index  := int(LED_NUM-hor_led_cnt);
                        led_start_x     := int(frame_width-ver_led_pad-ver_led_width);
                        led_end_x       := led_start_x+int(ver_led_width);
                        led_start_y     := int(ver_led_offs+(resize(uns(ver_led_step), 16)*side_led_index));
                        led_end_y       := led_start_y+int(ver_led_height);
                        
                    elsif LED_NUM<(hor_led_cnt*2)+ver_led_cnt then
                        
                        -- bottom side
                        side_led_index  := int(hor_led_cnt-1-(LED_NUM-hor_led_cnt-ver_led_cnt));
                        led_start_x     := int(hor_led_offs+(hor_led_step*side_led_index));
                        led_end_x       := led_start_x+int(hor_led_width);
                        led_start_y     := int(frame_height-hor_led_pad-hor_led_height);
                        led_end_y       := led_start_y+int(hor_led_height);
                        
                    else
                        
                        -- left side
                        side_led_index  := int(ver_led_cnt-1-(LED_NUM-(hor_led_cnt*2)-ver_led_cnt));
                        led_start_x     := int(ver_led_pad);
                        led_end_x       := led_start_x+int(ver_led_width);
                        led_start_y     := int(ver_led_offs+(resize(uns(ver_led_step), 16)*side_led_index));
                        led_end_y       := led_start_y+int(ver_led_height);
                        
                    end if;
                    
                    -- draw the LED
                    for y in led_start_y to led_end_y loop
                        for x in led_start_x to led_end_x loop
                            frame_buf(x)(y) := LED_RGB;
                        end loop;
                    end loop;
                    
                end if;
            end loop;
            
            img_file_write(filename, frame_buf);
            
            file_index  := file_index+1;
        end loop;
        
        led_imgs_finished   <= true;
        
        assert not stop_sim or not src_imgs_finished
            report "NONE. Saved " & integer'image(frames_to_save) & " frame(s)."
            severity FAILURE;
        
        wait;
    end process;
    
end rtl;

