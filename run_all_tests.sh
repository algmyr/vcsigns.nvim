#!/bin/bash
bash run_functional_tests.sh "$@"
bash run_tests.sh "$@"
bash run_vcrepo_functional_tests.sh "$@"
