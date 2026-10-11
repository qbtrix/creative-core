# Makefile: a make entry point for tools that may start `make` but not a
# script path directly (the Belt charter allowlist refuses relative paths).
# scripts/ci stays the one gate; this only calls it.
.PHONY: ci
ci:
	scripts/ci
