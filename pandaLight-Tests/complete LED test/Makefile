
PROJECT_TITLE = PANDA_LIGHT
BITFILE_PREFIX = pandaLight
UCF_PATH = PANDA_LIGHT.ucf
PARTNAME = xc6slx9-tqg144-3

SYNTHESIZE_OPTS = -intstyle ise
TRANSLATE_OPTS = -intstyle ise -dd _ngo -nt timestamp -uc "$(UCF_PATH)" -p "$(PARTNAME)"
MAP_OPTS = -intstyle ise -p $(PARTNAME) -w -logic_opt off -ol high -t 2 -xt 0 -r 4 -global_opt speed -equivalent_register_removal on -mt off -ir off -pr b -lc off -power off
PAR_OPTS = -w -intstyle ise -ol high -xe n -mt off
BITGEN_OPTS = -w -g DebugBitstream:No -g Binary:no -g CRC:Enable -g Reset_on_err:No -g ConfigRate:26 -g ProgPin:PullUp -g TckPin:PullUp -g TdiPin:PullUp -g TdoPin:PullUp -g TmsPin:PullUp -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g ExtMasterCclk_en:No -g SPI_buswidth:1 -g TIMER_CFG:0xFFFF -g multipin_wakeup:No -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 -g LCK_cycle:NoWait -g Security:None -g DonePipe:Yes -g DriveDone:No -g en_sw_gsr:No -g drive_awake:No -g sw_clk:Startupclk -g sw_gwe_cycle:5 -g sw_gts_cycle:4 -intstyle ise

XILINX_BIN_DIR = D:\\Xilinx\\14.7\\ISE_DS\\ISE\\bin\\nt64
XST = $(XILINX_BIN_DIR)\\xst.exe
NGDBUILD = $(XILINX_BIN_DIR)\\ngdbuild.exe
MAP = $(XILINX_BIN_DIR)\\map.exe
PAR = $(XILINX_BIN_DIR)\\par.exe
BITGEN = $(XILINX_BIN_DIR)\\bitgen.exe

#$(error Execute Synthesize to create $@)
%.xst:
	$(echo tse\r\nttt > blub.txt)

%.ucf:
	$(error UCF file $@ not found)

# Synthesize
%.ngc: $(PROJECT_TITLE).xst
	$(XST) $(SYNTHESIZE_OPTS) -ifn "$<" -ofn "$@"

# Translate
%.ngd: %.ngc $(UCF_PATH)
	$(NGDBUILD) $(TRANSLATE_OPTS) "$<" "$@.ngd"

# Map
%_map.ncd: %.ngd
	$(MAP) $(MAP_OPTS) -o "$@" "$<" "$(basename $@).pcf"

# Place and Route
%.ncd: %_map.ncd
	$(PAR) $(PAR_OPTS) "$<" "$@" "$(basename $@).pcf"

# Generate Programming File
%.bit: %.ncd
	$(BITGEN) $(BITGEN_OPTS) "$<"

.PHONY: clean all

all: $(BITFILE_PREFIX)_rx0.bit $(BITFILE_PREFIX)_rx1.bit

clean:
	$(RM) -rf .Xil/ smartxplorer_results/ planAhead_run_*/ _xmsgs/ _ngo/ iseconfig/ xst/ templates/ isim/ tmp/ db/ incremental_db/ work/ smartxplorer_setup xlnx_auto_0_xdb transcript *.exe *.swp *~ *# *.txt *.xds *.tcl *.html *.gise *.log *.cmd_log *.debug *.xdl *.xreport *.ncd *.xwbt *.xml *.vhi *.cr.mti *.wlf *.ini *.wdb *.ace *.prj *.stx *.svf *.scr *.bak *.elf *.xrpt *.wcfg *.cmd *.sh *.xmsgs *.mem *.lso *.syr *.lst *.bgn *.bld *.drc *.ngc *.ngd *.ngr *.pad *.par *.pcf *.ptwx *.twr *.twx *.unroutes *.ut *.xpi *.map *.mrp *.ngm *.psr *.csv *.xbcd *.cfi *.prm *.blc *.xsl *.version compxlib.cfg *.fdo *.udo*.mti *.dat *.dbs *.psm *.bak *.cmp *.jpg *.html *.bsfwlf* *.wlf *.vstf *.ucdb cov*/ transcript* sc_dpiheader.h vsim.dbg
