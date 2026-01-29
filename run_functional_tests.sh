#!/bin/bash
cd "$(dirname "$0")"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --filter | -f)
    export TEST_FILTER="$2"
    shift 2
    ;;
  --filter=*)
    export TEST_FILTER="${1#*=}"
    shift
    ;;
  *)
    shift
    ;;
  esac
done

export NVIM_APPNAME=nvim.test
nvim --headless -c "lua require('vcsigns_tests').run_functional()" -c "q" 2>&1
