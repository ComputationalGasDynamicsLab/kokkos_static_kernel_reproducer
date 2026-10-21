#!/bin/bash
# Usage: ./build.sh <tag> "<CMAKE_CXX_FLAGS_RELEASE>" [extra cmake args]
#   e.g. ./build.sh O1 "-O1"      ./build.sh O2 "-O2"
#        ./build.sh O2_unity "-O2" -DCMAKE_UNITY_BUILD=ON -DCMAKE_UNITY_BUILD_BATCH_SIZE=0
# Override the defaults with KOKKOS_ROOT, NVCC_WRAPPER and CUDA_ROOT.
set -e
tag=$1; flags=$2; shift 2
CUDA_ROOT=${CUDA_ROOT:-/usr/local/cuda-12.5}
KOKKOS_ROOT=${KOKKOS_ROOT:-/hdd1/dsmc/comet/comet_kokkos4.6.02/install/kokkos/install}
NVCC_WRAPPER=${NVCC_WRAPPER:-/hdd1/dsmc/comet/comet_kokkos4.6.02/kokkos/bin/nvcc_wrapper}
export PATH=$CUDA_ROOT/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_ROOT/lib64:$LD_LIBRARY_PATH
src=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$src/build_$tag" && cd "$src/build_$tag"
cmake "$src" -DCMAKE_PREFIX_PATH=$KOKKOS_ROOT -DCMAKE_CXX_COMPILER=$NVCC_WRAPPER \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE="$flags" "$@" > cmake.log 2>&1 || { tail -20 cmake.log; exit 1; }
make -j4 > make.log 2>&1 || { tail -20 make.log; exit 1; }
echo "built build_$tag/repro with flags: $flags $*"
