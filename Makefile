.PHONY: test smoke check

# Unit tests — no ft binary required.
test:
	nvim --headless -l tests/run.lua

# Integration smoke test — requires a real ft binary:
#   make smoke FT_BIN=/path/to/ft/target/release/ft
smoke:
	nvim --headless -l tests/smoke.lua

# Default check: unit tests (safe everywhere). Run `make smoke` too
# when you have a built ft binary.
check: test
