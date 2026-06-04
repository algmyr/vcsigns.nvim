#!/bin/bash
cd "$(dirname "$0")"

TEST_LUA="$1"
shift

rest=()

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
    rest+=("$1")
		shift
		;;
	esac
done

export NVIM_APPNAME=nvim.test
nvim "${rest[@]}" --headless -c "lua ${TEST_LUA}" -c "q" 2>&1
