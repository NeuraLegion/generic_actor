.PHONY: all
all: specs

.PHONY: clean
clean:
	rm -rf bin docs lib .shards

.PHONY: specs
specs:
	crystal spec -p --debug --release --error-trace -Dpreview_mt

.PHONY: specs_no_mt
specs_no_mt:
	crystal spec -p --debug --release --error-trace

.PHONY: check-format
check-format:
	crystal tool format --check
