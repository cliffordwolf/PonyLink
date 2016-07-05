
N = 100
tests = $(shell gawk 'BEGIN { for (i=0; i < $(N); i++) printf("test_%02d\n", i); exit; }')

test: $(addsuffix .ok,$(tests))
	@echo
	@echo "    All tests passed."
	@echo

define test_tpl
$(1).v: maketest.py ../plinksrc/timings.py
	python maketest.py > $(1).v
$(1).exe: $(1).v ../plinksrc/ponylink_*.v
	iverilog -o $(1).exe $(1).v ../plinksrc/ponylink_test.v ../plinksrc/ponylink_master.v ../plinksrc/ponylink_slave.v ../plinksrc/ponylink_pack.v ../plinksrc/ponylink_txrx.v ../plinksrc/ponylink_8b10b.v ../plinksrc/ponylink_crc32.v
$(1).vcd: $(1).exe
	timeout 20 vvp -N $(1).exe +vcd
$(1).ok: $(1).exe
	timeout 20 vvp -N $(1).exe
	touch $(1).ok

endef

$(foreach t,$(tests),$(eval $(call test_tpl,$t)))

view:
	gtkwave testbench.vcd testbench.gtkw

clean:
	rm -f test_[0-9][0-9].v
	rm -f test_[0-9][0-9].exe
	rm -f test_[0-9][0-9].ok

