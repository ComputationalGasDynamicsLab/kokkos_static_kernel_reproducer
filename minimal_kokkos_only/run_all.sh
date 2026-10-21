#!/bin/bash
# Build and run the reproducer at each optimisation level, plus the unity-build workaround.
cd "$(dirname "$0")"
ulimit -c 0   # the -O2/-O3 builds abort by design; do not write core dumps
export LD_LIBRARY_PATH=${CUDA_ROOT:-/usr/local/cuda-12.5}/lib64:$LD_LIBRARY_PATH
run() { ./build.sh "$@" > /dev/null && out=$(./build_$1/repro 2>&1); rc=$?
        printf "%-10s exit=%-3s %s\n" "$1" "$rc" "$(echo "$out" | grep -E 'PASS|FAIL|what\(\)' | cut -c1-120)"; }
run O0 "-O0"
run O1 "-O1"
run O2 "-O2"
run O3 "-O3 -DNDEBUG"
run O2_unity "-O2" -DCMAKE_UNITY_BUILD=ON -DCMAKE_UNITY_BUILD_BATCH_SIZE=0
