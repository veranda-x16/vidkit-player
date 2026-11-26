# VIDKIT Player for Veranda
#   make          build/VIDKIT Player.cvt (VIDKIT inside it: three banked overlays; the disc a fourth)
#   make test     a test build (AUTOTEST) on an SD card image as AUTOSTART.cvt with
#                 MEDIA, run headless (default MEDIA: WAV files tests/mkwav.py makes)
#   make toolkit  Prog8 for Veranda at the version TOOLKIT pins, cloned into P8KIT
#
# From an exported tree (git archive, no .git: Veranda's tools/mkdist.sh) it
# builds the same, given P8KIT.
#
#   P8KIT       Prog8 for Veranda (veranda-prog8): its target, lib/ and tools/; default ../veranda-prog8
#   P8KIT_URL   where `make toolkit` clones it from (default: TOOLKIT's url)
#   VSDK        an installed Veranda SDK (a Veranda checkout's `make sdk`: build/sdk; bin/VERANDA.*)
#   VTOOLS      Veranda's tools (vpack.py, vcard.py); default $(VSDK)/tools
#   VIDKIT_BIN  VIDKIT-A000.BIN (default vendor/vidkit/'s; checked against the
#               toolkit's tools/vidkit.sha256)
#   PROG8C      prog8c 12.3.5 (or "java -jar .../prog8c-12.3.5-all.jar"); 64tass on the PATH
#   EMU, ROM    x16emu and the R49 rom.bin (make test)
P8KIT   ?= ../veranda-prog8
KIT     := $(P8KIT)
P8KIT_URL ?= $(shell sed -n 's/^url  *//p' TOOLKIT)
P8KIT_REF := $(shell sed -n 's/^ref  *//p' TOOLKIT)
VSDK    ?= ../veranda/build/sdk
VTOOLS  ?= $(VSDK)/tools
PROG8C  ?= prog8c
EMU     ?= x16emu
ROM     ?= rom.bin
VIDKIT_BIN ?= vendor/vidkit/VIDKIT-A000.BIN
VIDKIT_SUM ?= $(shell sed -n "s/  VIDKIT-A000.BIN$$//p" $(KIT)/tools/vidkit.sha256 2>/dev/null)
MEDIA   ?=
BUILD   := build
LIB     := $(abspath $(KIT)/lib)
NAME    := VIDKIT Player
TESTLOG ?= VIDPLAYER TEST DONE
TESTSECS ?= 180
TESTBAD := VP [A-Z0-9 ]*BAD
# (EMU: a file, made absolute for the run's folder, or a command on the PATH)
EMU_CMD = $(if $(wildcard $(EMU)),$(abspath $(EMU)),$(EMU))

all: $(BUILD)/app.cvt

toolkit:
	git clone -q "$(P8KIT_URL)" "$(P8KIT)"
	git -C "$(P8KIT)" checkout -q "$(P8KIT_REF)"
	@echo "Prog8 for Veranda $(P8KIT_REF) in $(P8KIT)"

$(KIT)/lib/vkx.p8:
	@echo "no Prog8 for Veranda in $(P8KIT): make toolkit, or P8KIT=/path/to/veranda-prog8"; exit 1

$(BUILD)/vidkit_layout.p8 $(BUILD)/vidkit.1 $(BUILD)/vidkit.2 $(BUILD)/vidkit.3: $(VIDKIT_BIN)
	mkdir -p $(BUILD)
	@# vkx.p8 calls into VIDKIT at fixed addresses: only the release it was written for will do
	@[ "$(VIDKIT_SUM)" = any ] || echo "$(VIDKIT_SUM)  $(VIDKIT_BIN)" | sha256sum -c --quiet - \
		|| { echo "$(VIDKIT_BIN): not the VIDKIT release vkx.p8 expects ($(KIT)/tools/vidkit.sha256, vendor/vidkit/README.md)"; exit 1; }
	python3 -I $(KIT)/tools/vidkit_split.py "$(VIDKIT_BIN)" $(BUILD)

$(BUILD)/disc.rec: $(KIT)/tools/mkdisc.py
	python3 -I $(KIT)/tools/mkdisc.py $@

$(BUILD)/veranda.properties: $(KIT)/lib/vkx.p8 $(KIT)/target/veranda.properties
	mkdir -p $(BUILD)
	sed 's|^library *=.*|library = $(LIB)|' $(KIT)/target/veranda.properties > $@

$(BUILD)/main.bin: main.p8 $(BUILD)/veranda.properties $(BUILD)/vidkit_layout.p8 $(wildcard $(LIB)/*.p8)
	$(PROG8C) -target $(BUILD)/veranda.properties -srcdirs $(LIB):$(BUILD) -out $(BUILD) -quiet main.p8

$(BUILD)/app.cvt: $(BUILD)/main.bin app.hdr icon.pbm $(BUILD)/vidkit.1 $(BUILD)/disc.rec
	python3 -I -B $(VTOOLS)/vpack.py --load 0x0801 -o "$(BUILD)/$(NAME).cvt" app.hdr $(BUILD)/main.bin $(BUILD)/vidkit.1 $(BUILD)/vidkit.2 $(BUILD)/vidkit.3 $(BUILD)/disc.rec
	cp "$(BUILD)/$(NAME).cvt" $@

# the test build: main.p8 with AUTOTEST on (it plays the folder's files by itself)
$(BUILD)/test/main.bin: main.p8 $(BUILD)/veranda.properties $(BUILD)/vidkit_layout.p8 $(wildcard $(LIB)/*.p8)
	mkdir -p $(BUILD)/test
	sed 's/const bool AUTOTEST = false/const bool AUTOTEST = true/' main.p8 > $(BUILD)/test/main.p8
	$(PROG8C) -target $(BUILD)/veranda.properties -srcdirs $(LIB):$(BUILD) -out $(BUILD)/test -quiet $(BUILD)/test/main.p8

$(BUILD)/test/app.cvt: $(BUILD)/test/main.bin app.hdr icon.pbm $(BUILD)/vidkit.1 $(BUILD)/disc.rec
	python3 -I -B $(VTOOLS)/vpack.py --load 0x0801 -o $@ app.hdr $(BUILD)/test/main.bin $(BUILD)/vidkit.1 $(BUILD)/vidkit.2 $(BUILD)/vidkit.3 $(BUILD)/disc.rec

test: $(BUILD)/test/app.cvt
	rm -rf $(BUILD)/run && mkdir -p $(BUILD)/run/card
	cp $(BUILD)/test/app.cvt $(BUILD)/run/card/AUTOSTART.cvt
	cp $(VSDK)/bin/VERANDA.SYS $(BUILD)/run/card/
	@# (no MEDIA: three WAV files made here; with MEDIA, 8BG.WAV first, as the test expects)
	$(if $(strip $(MEDIA)),for f in $(MEDIA); do cp "$$f" $(BUILD)/run/card/; done,python3 -I tests/mkwav.py $(BUILD)/run/card)
	cp $(VSDK)/bin/VERANDA.PRG $(BUILD)/run/
	python3 -I -B $(VTOOLS)/vcard.py make --mb 256 $(BUILD)/run/sd.img $(BUILD)/run/card
	@# a sound device is needed (SDL's dummy one): without it VERA's PCM FIFO never drains
	@# (stopped once the test's last line is on the console, else after TESTSECS; TERM: a
	@# background job of a non-interactive shell ignores INT)
	cd $(BUILD)/run && { SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy $(EMU_CMD) -rom $(abspath $(ROM)) \
		-sdcard sd.img -prg VERANDA.PRG -run -warp -echo $(GIF) > console.txt 2>&1 & pid=$$!; i=0; \
		while [ $$i -lt $(TESTSECS) ] && kill -0 $$pid 2>/dev/null && ! grep -a -q "$(TESTLOG)" console.txt; do sleep 1; i=$$((i+1)); done; \
		sleep 1; kill -TERM $$pid 2>/dev/null; wait $$pid 2>/dev/null; true; }
	@tr -cd '[:print:]\n' < $(BUILD)/run/console.txt | grep -a -o "VP [A-Z0-9 ]*\|VIDPLAYER[A-Z ]*" || true
	@grep -a -q "$(TESTLOG)" $(BUILD)/run/console.txt \
		|| { tr -cd '[:print:]\n' < $(BUILD)/run/console.txt | tail -5; echo "FAIL  no \"$(TESTLOG)\" on the console"; exit 1; }
	@! grep -a -q "$(TESTBAD)" $(BUILD)/run/console.txt || { echo "FAIL  a check failed (BAD on the console)"; exit 1; }
	@echo "ok    \"$(TESTLOG)\", no check BAD"

clean:
	rm -rf $(BUILD)

.PHONY: all test toolkit clean
