.PHONY: all
all: specs

.PHONY: clean
clean:
	rm -rf bin docs lib .shards

.PHONY: specs
specs:
	crystal spec -p --debug --release --error-trace -Dpreview_mt

.PHONY: check-format
check-format:
	crystal tool format --check
