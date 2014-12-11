--------------------------------------------------------------------------------
-- Engineer: Sebastian Huether
--
-- Create Date:   09:57:23 12/08/2014
-- Module Name:   C:/Users/hudini/GitHub/VHDL/pandaLight-HDL/VIDEO_ANALYZER/VIDEO_ANALYZER_tb.vhd
-- Project Name:  VIDEO_ANALYZER
-- Tool versions: Xilinx ISE 14.7
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: VIDEO_ANALYZER
-- 
-- Additional Comments:
--  
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.help_funcs.all;
use work.video_profiles.all;

ENTITY VIDEO_ANALYZER_tb IS
END VIDEO_ANALYZER_tb;

ARCHITECTURE behavior OF VIDEO_ANALYZER_tb IS

    -- Inputs
    signal CLK          : std_ulogic := '0';
    signal RST          : std_ulogic := '0';
    signal START        : std_ulogic := '0';
    signal VSYNC        : std_ulogic := '0';
    signal HSYNC        : std_ulogic := '0';
    signal RGB_VALID    : std_ulogic := '0';

    -- Outputs
    signal POSITIVE_VSYNC   : std_ulogic;
    signal POSITIVE_HSYNC   : std_ulogic;
    signal WIDTH            : std_ulogic_vector(10 downto 0);
    signal HEIGHT           : std_ulogic_vector(10 downto 0);
    signal INTERLACED       : std_ulogic;
    signal VALID            : std_ulogic;
    
    constant TEST_COUNT     : natural := VIDEO_PROFILE_COUNT;
    constant FRAME_COUNT    : natural := 10;
    
    signal pix_clk      : std_ulogic := '0';
    signal pix_period   : time := 10 ns;
    
BEGIN
    
    CLK <= pix_clk;
    
    VIDEO_ANALYZER_inst : entity work.VIDEO_ANALYZER
        port map (
            CLK => CLK,
            RST => RST,
            
            START           => START,
            VSYNC           => VSYNC,
            HSYNC           => HSYNC,
            RGB_VALID       => RGB_VALID,
            
            POSITIVE_VSYNC  => POSITIVE_VSYNC,
            POSITIVE_HSYNC  => POSITIVE_HSYNC,
            WIDTH           => WIDTH,
            HEIGHT          => HEIGHT,
            INTERLACED      => INTERLACED,
            VALID           => VALID
        );
    
    pix_clk <= not pix_clk after pix_period/2;
    
    -- Stimulus process
    stim_proc: process
        variable vp : video_profile_type;
        variable total_ver_lines, total_hor_pixels : natural;
        variable pos_vsync, pos_hsync   : std_ulogic;
    begin
        -- hold reset state for 100 ns.
        RST <= '1';
        wait for 100 ns;
        RST <= '0';
        wait for 100 ns;
        wait until rising_edge(pix_clk);
        
        -- insert stimulus here 
        
        for test_index in 0 to TEST_COUNT-1 loop
            
            report "Starting test " & natural'image(test_index);
            vp                  := video_profiles(test_index);
            
            total_ver_lines     := vp.v_sync_lines + vp.v_front_porch + vp.top_border + vp.height +
                                    vp.bottom_border + vp.v_back_porch + sel(vp.interlaced, 1, 0);
            
            total_hor_pixels    := vp.h_sync_cycles + vp.h_front_porch + vp.left_border + vp.width +
                                    vp.right_border + vp.h_back_porch;
            
            pix_period  <= video_profiles(test_index).pixel_period;
            START       <= '1';
            wait until rising_edge(pix_clk);
            START       <= '0';
            wait until rising_edge(pix_clk);
            
            for frame_index in 0 to FRAME_COUNT-1 loop
                
                for y in 0 to total_ver_lines-1 loop
                    
                    -- interlaced video has 1 more vblank line every other frame
                    next when vp.interlaced and (frame_index mod 2)=0 and y=vp.v_sync_lines;
                    
                    for x in 0 to total_hor_pixels-1 loop
                        
                        if not vp.interlaced or (frame_index mod 2)=0 or x >= total_hor_pixels/2 then
                            if y < vp.v_sync_lines then
                                -- vsync period
                                pos_vsync   := '1';
                            else
                                pos_vsync   := '0';
                            end if;
                        end if;
                        
                        if x < vp.h_sync_cycles then
                            -- hsync period
                            pos_hsync   := '1';
                        elsif x < vp.h_sync_cycles + vp.h_front_porch then
                            -- horizontal front porch period
                            pos_hsync   := '0';
                        elsif x < vp.h_sync_cycles + vp.h_front_porch + vp.left_border then
                            -- left border period
                        elsif x < vp.h_sync_cycles + vp.h_front_porch + vp.left_border + vp.width then
                            if
                                y >= vp.v_sync_lines + vp.v_front_porch + vp.top_border and
                                y < vp.v_sync_lines + vp.v_front_porch + vp.top_border + vp.height
                            then
                                -- active pixels
                                RGB_VALID   <= '1';
                            end if;
                        else
                            RGB_VALID   <= '0';
                        end if;
                        
                        -- translate sync signals
                        if vp.negative_vsync then
                            VSYNC   <= not pos_vsync;
                        else
                            VSYNC   <= pos_vsync;
                        end if;
                        if vp.negative_hsync then
                            HSYNC   <= not pos_hsync;
                        else
                            HSYNC   <= pos_hsync;
                        end if;
                        
                        wait until rising_edge(pix_clk);
                        
                    end loop;
                end loop;
                
            end loop;
            
            assert VALID='1'
                report "Not yet valid analysis!"
                severity FAILURE;
            assert POSITIVE_VSYNC='0'
                report "Wrong VSync polarity!"
                severity FAILURE;
            assert POSITIVE_HSYNC='0'
                report "Wrong HSync polarity!"
                severity FAILURE;
            assert WIDTH=stdulv(vp.width, WIDTH'length)
                report "WIDTH doesn't match!"
                severity FAILURE;
            assert HEIGHT=stdulv(vp.height, HEIGHT'length)
                report "HEIGHT doesn't match!"
                severity FAILURE;
            assert INTERLACED=sel(vp.interlaced, '1', '0')
                report "Interlacing not detected!"
                severity FAILURE;
        
        end loop;
        
        wait for 100 ns;
        report "NONE. All tests completed successfully"
            severity FAILURE;
    end process;

END;
