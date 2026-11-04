NVIM ?= nvim
STYLUA ?= stylua

.PHONY: test fmt fmt-check

test:
	$(NVIM) --headless -u NONE -l tests/run.lua

fmt:
	$(STYLUA) lua/ plugin/ tests/

fmt-check:
	$(STYLUA) --check lua/ plugin/ tests/
