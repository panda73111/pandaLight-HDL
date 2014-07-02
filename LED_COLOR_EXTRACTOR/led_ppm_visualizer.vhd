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
        FILENAME_START_NUM  : natural;
        FRAMES_TO_SAVE      : natural;
        STOP_SIM            : boolean;
        WHITESPACE_CHAR     : character := character'val(13);
        FRAME_SIZE_BITS     : natural := 11;
        LED_CNT_BITS        : natural := 5;
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
    constant maxval : natural := 2**(R_BITS+G_BITS+B_BITS);
    
    type char_file is file of character;
    type data_type is (BYTE, HWORD, WORD);
    
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
        variable filename   : string(1 to base_filename'length+6);
        variable file_index : integer := 0;
    begin
        while file_index/=frames_to_save loop
            filename    := base_filename & integer'image(file_index) & ".ppm";
            
            wait until LED_VSYNC='1';
            
            while LED_VSYNC='1' loop
                wait until rising_edge(CLK);
                if LED_VALID='1' then
                    -- TODO: store and/or draw the LEDS
                end if;
            end loop;
            
            report("opening file " & filename);
            file_open(img_file, filename, write_mode);
            
            -- write the file header
            file_write(img_file, "P6");              -- magic number
            file_write(img_file, WHITESPACE_CHAR);
            file_write(img_file, str(FRAME_WIDTH));  -- width
            file_write(img_file, WHITESPACE_CHAR);
            file_write(img_file, str(FRAME_HEIGHT)); -- height
            file_write(img_file, WHITESPACE_CHAR);
            file_write(img_file, str(maxval));       -- Maxval
            file_write(img_file, WHITESPACE_CHAR);
            
            -- TODO: write image buffer
            
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

