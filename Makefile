.PHONY: test smoke check

# Unit + stub tests — no ft binary required. Tier 1 (pure functions,
# source-scan guard) and Tier 2 (editor behavior against a stub ft).
test:
	nvim --headless -l tests/run.lua
	nvim --headless -l tests/tasks_stub.lua
	nvim --headless -l tests/quote_stub.lua

# Integration smoke test — requires a real ft binary:
#   make smoke FT_BIN=/path/to/ft/target/release/ft
smoke:
	nvim --headless -l tests/smoke.lua

# Default check: unit tests (safe everywhere). Run `make smoke` too
# when you have a built ft binary.
check: test
