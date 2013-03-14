# This file oritinally came from excamera's build example.
#
# The top level module should define the variables below then include
# this file.  The files listed should be in the same directory as the
# Makefile.  
#
# TODO: update these listings
#
#   variable	description
#   ----------  -------------
#   project	project name (top level module should match this name)
#   top_module  top level module of the project
#   libdir	path to library directory
#   libs	library modules used
#   vfiles	all local .v files
#   xilinx_cores  all local .xco files
#   vendor      vendor of FPGA (xilinx, altera, etc.)
#   family      FPGA device family (spartan3e) 
#   part        FPGA part name (xc4vfx12-10-sf363)
#   flashsize   size of flash for mcs file (16384)
#   optfile     (optional) xst extra opttions file to put in .scr
#   map_opts    (optional) options to give to map
#   par_opts    (optional) options to give to par
#   intstyle    (optional) intstyle option to all tools
#
#   files 		description
#   ----------  	------------
#   $(project).ucf	ucf file
#
# Library modules should have a modules.mk in their root directory,
# namely $(libdir)/<libname>/module.mk, that simply adds to the vfiles
# and xilinx_cores variable.
#
# all the .xco files listed in xilinx_cores will be generated with core, with
# the resulting .v and .ngc files placed back in the same directory as
# the .xco file.
#
# TODO: .xco files are device dependant, should use a template based system
#
# NOTE: DO NOT edit this file to change settings; instead edit Makefile

coregen_work_dir ?= ./coregen-tmp
map_opts ?= -timing -ol high -detail -pr b -register_duplication -w
par_opts ?= -ol high
hostbits = 64
iseenv= /opt/Xilinx/14.3/ISE_DS
iseenvfile?= $(iseenv)/settings$(hostbits).sh
xil_env ?= mkdir -p build/; cd ./build; source $(iseenvfile) > /dev/null
sim_env ?= cd ./tb; source $(iseenvfile) > /dev/null
flashsize ?= 8192

libmks = $(patsubst %,$(libdir)/%/module.mk,$(libs)) 
mkfiles = Makefile $(libmks) contrib/xilinx.mk
include $(libmks)

corengcs = $(foreach core,$(xilinx_cores),$(core:.xco=.ngc))
local_corengcs = $(foreach ngc,$(corengcs),$(notdir $(ngc)))
vfiles += $(foreach core,$(xilinx_cores),$(core:.xco=.v))
junk += $(local_corengcs)

.PHONY: default xilinx_cores clean twr etwr ise
default: build/$(project).bit build/$(project).mcs
xilinx_cores: $(corengcs)
twr: $(project).twr
etwr: $(project)_err.twr

define cp_template
$(2): $(1)
	cp $(1) $(2)
endef
$(foreach ngc,$(corengcs),$(eval $(call cp_template,$(ngc),$(notdir $(ngc)))))

$(coregen_work_dir)/$(project).cgp: contrib/template.cgp Makefile
	if [ -d $(coregen_work_dir) ]; then \
		rm -rf $(coregen_work_dir)/*; \
	else \
		mkdir -p $(coregen_work_dir); \
	fi
	cp contrib/template.cgp $@
	echo "SET designentry = Verilog " >> $@
	echo "SET device = $(device)" >> $@
	echo "SET devicefamily = $(family)" >> $@
	echo "SET package = $(device_package)" >> $@
	echo "SET speedgrade = $(speedgrade)" >> $@
	echo "SET workingdirectory = ./tmp/" >> $@

%.ngc %.v: %.xco $(coregen_work_dir)/$(project).cgp
	@echo "=== rebuilding $@"
	bash -c "$(xil_env); cd ../$(coregen_work_dir); coregen -b $$OLDPWD/../$< -p $(project).cgp;"
	xcodir=`dirname $<`; \
	basename=`basename $< .xco`; \
	echo $(coregen_work_dir)/$$basename.v; \
	if [ ! -r $(coregen_work_dir)/$$basename.ngc ]; then \
		echo "'$@' wasn't created."; \
		exit 1; \
	else \
		cp $(coregen_work_dir)/$$basename.v $(coregen_work_dir)/$$basename.ngc $$xcodir; \
	fi
junk += $(coregen_work_dir)

date = $(shell date +%F-%H-%M)

# some common junk
junk += *.xrpt
junk += _xmsgs

programming_files: build/$(project).bit build/$(project).mcs
	mkdir -p $@/$(date)
	mkdir -p $@/latest
	for x in .bit .mcs .cfi _bd.bmm; do cp $(project)$$x $@/$(date)/$(project)$$x; cp $(project)$$x $@/latest/$(project)$$x; done
	bash -c "$(xil_env); xst -help | head -1 | sed 's/^/#/' | cat - build/$(project).scr > $@/$(date)/$(project).scr"

build/$(project).mcs: build/$(project).bit
	bash -c "$(xil_env); promgen -w -s $(flashsize) -p mcs -o $(project).mcs -u 0 $(project).bit"
junk += $(project).mcs $(project).cfi $(project).prm

build/$(project).bit: build/$(project)_par.ncd
	bash -c "$(xil_env); \
	bitgen $(intstyle) -g DriveDone:yes -g StartupClk:Cclk -w $(project)_par.ncd $(project).bit"
junk += $(project).bgn $(project).bit $(project).drc $(project)_bd.bmm


build/$(project)_par.ncd: build/$(project).ncd
	bash -c "$(xil_env); \
	if par $(intstyle) $(par_opts) -w $(project).ncd $(project)_par.ncd; then \
		:; \
	else \
		$(MAKE) etwr; \
	fi "
junk += $(project)_par.ncd $(project)_par.par $(project)_par.pad 
junk += $(project)_par_pad.csv $(project)_par_pad.txt 
junk += $(project)_par.grf $(project)_par.ptwx
junk += $(project)_par.unroutes $(project)_par.xpi

build/$(project).ncd: build/$(project).ngd
	if [ -r $(project)_par.ncd ]; then \
		cp $(project)_par.ncd smartguide.ncd; \
		smartguide="-smartguide smartguide.ncd"; \
	else \
		smartguide=""; \
	fi; \
	bash -c "$(xil_env); \
	map $(intstyle) $(map_opts) $$smartguide $(project).ngd "
junk += $(project).ncd $(project).pcf $(project).ngm $(project).mrp $(project).map
junk += smartguide.ncd $(project).psr 
junk += $(project)_summary.xml $(project)_usage.xml

build/$(project).ngd: build/$(project).ngc $(project).ucf $(project).bmm
	bash -c "$(xil_env); \
	ngdbuild $(intstyle) $(project).ngc -bm ../$(project).bmm -sd ../cores"
junk += $(project).ngd $(project).bld

build/$(project).ngc: $(vfiles) $(local_corengcs) build/$(project).scr build/$(project).prj
	bash -c "$(xil_env); xst $(intstyle) -ifn $(project).scr"
junk += xlnx_auto* build/$(top_module).lso $(project).srp 
junk += netlist.lst xst $(project).ngc

build/$(project).prj: $(vfiles) $(mkfiles)
	for src in $(vfiles); do echo "verilog work ../$$src" >> $(project).tmpprj; done
	sort -u $(project).tmpprj > $@
	rm -f $(project).tmpprj
junk += $(project).prj

optfile += $(wildcard $(project).opt)
top_module ?= $(project)
build/$(project).scr: $(optfile) $(mkfiles) ./$(project).opt
	mkdir -p build
	echo "run" > $@
	echo "-p $(part)" >> $@
	echo "-top $(top_module)" >> $@
	echo "-ifn $(project).prj" >> $@
	echo "-ofn $(project).ngc" >> $@
	cat $(optfile) >> $@
	cp $@ build/$(project).xst
junk += $(project).scr

build/$(project).post_map.twr: build/$(project).ncd
	bash -c "$(xil_env); trce -e 10 $< $(project).pcf -o $@"
junk += $(project).post_map.twr $(project).post_map.twx smartpreview.twr

build/$(project).twr: build/$(project)_par.ncd
	bash -c "$(xil_env); trce $< $(project).pcf -o $(project).twr"
junk += $(project).twr $(project).twx smartpreview.twr

build/$(project)_err.twr: build/$(project)_par.ncd
	bash -c "$(xil_env); trce -e 10 $< $(project).pcf -o $(project)_err.twr"
junk += $(project)_err.twr $(project)_err.twx

.gitignore: $(mkfiles)
	echo programming_files $(junk) | sed 's, ,\n,g' > .gitignore

tb/simulate_isim.prj: $(tbfiles)
	rm $@
	for f in $(vfiles)
	do
		echo "verilog unenclib ../$(f)" >> $@
	done
	for f in $(tbfiles)
	do
		echo "verilog unenclib ../$(f)" >> $@
	done
	echo "verilog unenclib ../$(iseenv)/ISE/verilog/src/glbl.v" >> $@

tb/isim: tb/simulate_isim.prj
	bash -c "$(sim_env); cd ../tb/; vlogcomp -prj simulate_isim.prj"

tb/simulate_isim: tb/isim
	bash -c "$(sim_env); cd ../tb/; fuse -lib unisims_ver -lib secureip -lib xilinxcorelib_ver -lib unimacro_ver -lib iplib=./iplib -lib unenclib -o simulate_isim unenclib.tb unenclib.glbl"

simulate: tb/simulate_isim

isim_cli: simulate
	bash -c "$(sim_env); cd ../tb/; ./simulate_isim"

isim: simulate
	bash -c "$(sim_env); cd ../tb/; ./simulate_isim -gui -view signals.wcfg"

ise:
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "! WARNING: you might need to update ISE's project settings !"
	@echo "!          (see README)                                    !"
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@mkdir -p build
	bash -c "$(xil_env); ise .. &"

clean: clean_synth clean_sim

clean_sim::
	rm -f tb/simulate_isim tb/*.log tb/*.cmd tb/*.xmsgs
	rm -rf tb/isim

clean_synth::
	rm -rf build
	rm -rf coregen-tmp
#rm -rf $(junk)

