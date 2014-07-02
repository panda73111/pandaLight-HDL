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
        FRAME_SIZE_BITS     : natural := 11;
        LED_CNT_BITS        : natural := 7;
        LED_SIZE_BITS       : natural := 7;
        LED_PAD_BITS        : natural := 7;
        LED_STEP_BITS       : natural := 7;
        R_BITS              : natural range 1 to 16 := 8;
        G_BITS              : natural range 1 to 16 := 8;
        B_BITS              : natural range 1 to 16 := 8
    );
    port (
        CLK : in std_ulogic;
        
        HOR_LED_CNT     : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        VER_LED_CNT     : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        
        HOR_LED_WIDTH   : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        HOR_LED_HEIGHT  : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        VER_LED_WIDTH   : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        VER_LED_HEIGHT  : in std_ulogic_vector(LED_SIZE_BITS-1 downto 0);
        
        LED_PAD_TOP_LEFT        : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_TOP_TOP         : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_RIGHT_TOP       : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_RIGHT_RIGHT     : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_BOTTOM_LEFT     : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_BOTTOM_BOTTOM   : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_LEFT_TOP        : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_PAD_LEFT_LEFT       : in std_ulogic_vector(LED_PAD_BITS-1 downto 0);
        LED_STEP_TOP            : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        LED_STEP_RIGHT          : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        LED_STEP_BOTTOM         : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        LED_STEP_LEFT           : in std_ulogic_vector(LED_STEP_BITS-1 downto 0);
        
        FRAME_WIDTH     : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        FRAME_HEIGHT    : in std_ulogic_vector(FRAME_SIZE_BITS-1 downto 0);
        
        LED_VSYNC   : in std_ulogic;
        LED_VALID   : in std_ulogic;
        LED_NUM     : in std_ulogic_vector(LED_CNT_BITS-1 downto 0);
        LED_R       : in std_ulogic_vector(R_BITS-1 downto 0);
        LED_G       : in std_ulogic_vector(G_BITS-1 downto 0);
        LED_B       : in std_ulogic_vector(B_BITS-1 downto 0)
    );
end led_ppm_visualizer;

architecture rtl of led_ppm_visualizer is
    constant maxval : natural := (2**(max(R_BITS, max(G_BITS, B_BITS))))-1;
    
    type char_file is file of character;
    type data_type is (BYTE, HWORD, WORD);
    
    type frame_col_type is
        array(0 to (2**FRAME_SIZE_BITS)-1) of
        std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
    
    type frame_buf_type is
        array(0 to (2**FRAME_SIZE_BITS)-1) of
        frame_col_type;
    
    function to_char (v : std_ulogic_vector) return character is
    begin
        return character'val(int(uns(v)));
    end to_char;

    procedure file_write (file f : char_file; v : std_ulogic_vector) is
        variable t : std_ulogic_vector(v'length-1 downto 0) := v;
        variable i : natural := 0;
    begin
        while i/=t'length loop
            write(f, to_char(t(i+7 downto i)));
            i := i+8;
        end loop;
    end file_write;
    
    procedure file_write (file f : char_file; c : character) is
    begin
        write(f, c);
    end procedure;
    
    procedure file_write (file f : char_file; s : string) is
        variable v : std_ulogic_vector(s'length*8-1 downto 0);
    begin
        for i in 1 to s'length loop
            write(f, s(i));
        end loop;
    end file_write;

    procedure file_write (file f : char_file; i : integer; t : data_type) is
    begin
        case t is
            when BYTE   => file_write(f, stdulv(uns(i, 8)));
            when HWORD  => file_write(f, stdulv(uns(i, 16)));
            when WORD   => file_write(f, stdulv(uns(i, 32)));
        end case;
    end file_write;
begin
    
    write_file_proc : process
        file img_file       : char_file;
        variable filename   : string(1 to FILENAME_BASE'length+6);
        variable file_index : integer := 0;
        variable frame_buf  : frame_buf_type := (others => (others => (others => '0')));
        variable pixel      : std_ulogic_vector(R_BITS+G_BITS+B_BITS-1 downto 0);
        variable r          : std_ulogic_vector(R_BITS-1 downto 0);
        variable g          : std_ulogic_vector(G_BITS-1 downto 0);
        variable b          : std_ulogic_vector(B_BITS-1 downto 0);
        variable led_start_x, led_start_y   : natural range 0 to (2**FRAME_SIZE_BITS)-1;
        variable led_end_x, led_end_y       : natural range 0 to (2**FRAME_SIZE_BITS)-1;
        variable side_led_index             : natural range 0 to (2**LED_CNT_BITS)-1;
    begin
        while file_index/=frames_to_save loop
            filename    := FILENAME_BASE & integer'image(file_index) & ".ppm";
            
            wait until LED_VSYNC='1';
            
            while LED_VSYNC='1' loop
                wait until rising_edge(CLK);
                if LED_VALID='1' then
                    if LED_NUM<HOR_LED_CNT then
                        
                        -- top side
                        side_led_index  := int(LED_NUM);
                        led_start_x     := int(LED_PAD_TOP_LEFT+(LED_STEP_TOP*side_led_index));
                        led_end_x       := led_start_x+int(HOR_LED_WIDTH);
                        led_start_y     := int(LED_PAD_TOP_TOP);
                        led_end_y       := led_start_y+int(HOR_LED_HEIGHT);
                        
                    elsif LED_NUM<HOR_LED_CNT+VER_LED_CNT then
                        
                        -- right side
                        side_led_index  := int(LED_NUM-HOR_LED_CNT);
                        led_start_x     := int(FRAME_WIDTH-LED_PAD_RIGHT_RIGHT-VER_LED_WIDTH);
                        led_end_x       := led_start_x+int(VER_LED_WIDTH);
                        led_start_y     := int(LED_PAD_RIGHT_TOP+(LED_STEP_RIGHT*side_led_index));
                        led_end_y       := led_start_y+int(VER_LED_HEIGHT);
                        
                    elsif LED_NUM<(HOR_LED_CNT*2)+VER_LED_CNT then
                        
                        -- bottom side
                        side_led_index  := int(HOR_LED_CNT-1-(LED_NUM-HOR_LED_CNT-VER_LED_CNT));
                        led_start_x     := int(LED_PAD_BOTTOM_LEFT+(LED_STEP_BOTTOM*side_led_index));
                        led_end_x       := led_start_x+int(HOR_LED_WIDTH);
                        led_start_y     := int(FRAME_HEIGHT-LED_PAD_BOTTOM_BOTTOM-HOR_LED_HEIGHT);
                        led_end_y       := led_start_y+int(HOR_LED_HEIGHT);
                        
                    else
                        
                        -- left side
                        side_led_index  := int(VER_LED_CNT-1-(LED_NUM-(HOR_LED_CNT*2)-VER_LED_CNT));
                        led_start_x     := int(LED_PAD_LEFT_LEFT);
                        led_end_x       := led_start_x+int(VER_LED_WIDTH);
                        led_start_y     := int(LED_PAD_LEFT_TOP+(LED_STEP_LEFT*side_led_index));
                        led_end_y       := led_start_y+int(VER_LED_HEIGHT);
                        
                    end if;
                    
                    -- draw the LED
                    for y in led_start_y to led_end_y loop
                        for x in led_start_x to led_end_x loop
                            frame_buf(x)(y) := LED_R & LED_G & LED_B;
                        end loop;
                    end loop;
                    
                end if;
            end loop;
            
            report("opening file " & filename);
            file_open(img_file, filename, write_mode);
            
            -- write the file header
            file_write(img_file, "P6");                   -- magic number
            file_write(img_file, WHITESPACE_CHAR);
            file_write(img_file, str(int(FRAME_WIDTH)));  -- width
            file_write(img_file, WHITESPACE_CHAR);
            file_write(img_file, str(int(FRAME_HEIGHT))); -- height
            file_write(img_file, WHITESPACE_CHAR);
            file_write(img_file, str(maxval));            -- Maxval
            file_write(img_file, WHITESPACE_CHAR);
            
            for y in 0 to int(FRAME_HEIGHT-1) loop
                for x in 0 to int(FRAME_WIDTH-1) loop
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
            
            file_index  := file_index+1;
        end loop;
        
        assert not stop_sim
            report "NONE. Saved " & integer'image(frames_to_save) & " frame(s)."
            severity FAILURE;
        
        wait;
    end process;
    
end rtl;

