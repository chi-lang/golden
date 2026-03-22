# Golden test runner for the Chi language
#
# Usage:
#   make test                        — run all tests using chi from PATH
#   make test CHI=/path/to/chi       — run all tests using specific chi binary
#   make test FILTER=strings/*       — run tests matching a glob pattern
#   make test FILTER=strings/basic   — run single test (with or without .chi)
#   make update                      — regenerate all .expected files
#   make update FILTER=strings/*     — regenerate .expected for matching tests
#
# Variables:
#   CHI     — path to chi executable (default: chi from PATH)
#   FILTER  — glob pattern relative to this directory, e.g. strings/* or types/records
#   UPDATE  — set to 1 to overwrite .expected instead of diffing (used by 'make update')

CHI    ?= chi
FILTER ?= **/*
UPDATE ?= 0

GOLDEN_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Resolve all .chi files matching FILTER
# We strip a trailing .chi from FILTER so both "strings/basic" and "strings/basic.chi" work
_FILTER_NORM := $(patsubst %.chi,%,$(FILTER))
_CHI_FILES   := $(sort $(wildcard $(_FILTER_NORM).chi) $(wildcard $(_FILTER_NORM)/*.chi) $(wildcard $(_FILTER_NORM)/**/*.chi))

# Fallback: if FILTER is the default wildcard, use find to get everything
ifeq ($(_CHI_FILES),)
  ifeq ($(FILTER),**/*) 
    _CHI_FILES := $(sort $(shell find "$(GOLDEN_DIR)" -name "*.chi" | sed 's|$(GOLDEN_DIR)||'))
  endif
endif

.PHONY: test update help

##@ Default target
test: _check_chi _run_tests  ## Run golden tests

update: UPDATE=1
update: _check_chi _run_tests  ## Regenerate .expected files

_check_chi:
	@if ! command -v "$(CHI)" > /dev/null 2>&1 && [ ! -x "$(CHI)" ]; then \
		echo "ERROR: chi executable not found: $(CHI)"; \
		echo "       Set CHI=/path/to/chi or ensure chi is on PATH"; \
		exit 1; \
	fi

_run_tests:
	@$(MAKE) -f "$(GOLDEN_DIR)Makefile" _run_tests_inner \
		CHI="$(CHI)" UPDATE="$(UPDATE)" FILTER="$(FILTER)" \
		_CHI_FILES="$(_CHI_FILES)" \
		GOLDEN_DIR="$(GOLDEN_DIR)" \
		2>&1

_run_tests_inner:
	@PASS=0; FAIL=0; SKIP=0; \
	CHI_BIN="$(CHI)"; \
	FILES="$(_CHI_FILES)"; \
	if [ -z "$$FILES" ]; then \
		FILES=$$(find "$(GOLDEN_DIR)" -name "*.chi" | sort | sed "s|$(GOLDEN_DIR)||"); \
	fi; \
	for rel in $$FILES; do \
		chi_file="$(GOLDEN_DIR)$$rel"; \
		[ -f "$$chi_file" ] || chi_file="$$rel"; \
		[ -f "$$chi_file" ] || { echo "  SKIP  $$rel (file not found)"; SKIP=$$((SKIP+1)); continue; }; \
		base="$${chi_file%.chi}"; \
		expected="$${base}.expected"; \
		actual=$$($$CHI_BIN "$$chi_file" 2>/dev/null); \
		exit_code=$$?; \
		if [ $$exit_code -ne 0 ]; then \
			actual_err=$$($$CHI_BIN "$$chi_file" 2>&1); \
			printf "  \033[31mERROR\033[0m  %s\n" "$$rel"; \
			printf "%s\n" "$$actual_err" | sed 's/^/         /'; \
			FAIL=$$((FAIL+1)); \
			continue; \
		fi; \
		if [ "$(UPDATE)" = "1" ]; then \
			printf "%s" "$$actual" > "$$expected"; \
			printf "  \033[33mUPDATED\033[0m %s\n" "$$rel"; \
			PASS=$$((PASS+1)); \
		elif [ ! -f "$$expected" ]; then \
			printf "%s" "$$actual" > "$$expected"; \
			printf "  \033[33mGENERATED\033[0m %s\n" "$$rel"; \
			PASS=$$((PASS+1)); \
		else \
			expected_content=$$(cat "$$expected"); \
			if [ "$$actual" = "$$expected_content" ]; then \
				printf "  \033[32mPASS\033[0m   %s\n" "$$rel"; \
				PASS=$$((PASS+1)); \
			else \
				printf "  \033[31mFAIL\033[0m   %s\n" "$$rel"; \
				printf "%s" "$$actual" | diff --color=always -u "$$expected" - | \
					sed '1s|--- .*|--- expected|; 2s|+++ .*|+++ actual|' | \
					sed 's/^/         /'; \
				FAIL=$$((FAIL+1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	if [ $$FAIL -eq 0 ]; then \
		printf "\033[32m%d passed\033[0m" $$PASS; \
	else \
		printf "\033[32m%d passed\033[0m, \033[31m%d failed\033[0m" $$PASS $$FAIL; \
	fi; \
	[ $$SKIP -gt 0 ] && printf ", %d skipped" $$SKIP; \
	echo "  (chi: $$CHI_BIN)"; \
	[ $$FAIL -eq 0 ]

help:  ## Show this help
	@echo "Usage: make [target] [CHI=/path/to/chi] [FILTER=pattern]"
	@echo ""
	@echo "Targets:"
	@echo "  test     Run golden tests (default)"
	@echo "  update   Regenerate .expected files"
	@echo "  help     Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  CHI      Path to chi executable (default: chi from PATH)"
	@echo "  FILTER   Glob pattern for tests, e.g. strings/* or types/records"
	@echo ""
	@echo "Examples:"
	@echo "  make test"
	@echo "  make test CHI=~/builds/chi-new"
	@echo "  make test FILTER=strings/*"
	@echo "  make test FILTER=strings/basic"
	@echo "  make update FILTER=types/records"
