#!/bin/bash
# Usage:
#   ./build.sh                                                        build every configuration below
#   ./build.sh <tag> "<CMAKE_CXX_FLAGS_RELEASE>" [extra cmake args]   build one configuration
#     e.g. ./build.sh O2 "-O2"
#          ./build.sh O2_unity "-O2" -DCMAKE_UNITY_BUILD=ON -DCMAKE_UNITY_BUILD_BATCH_SIZE=0
# Each build goes to build_<tag>/ and produces build_<tag>/repro.
# Override the defaults with KOKKOS_ROOT, NVCC_WRAPPER and CUDA_ROOT.
CUDA_ROOT=${CUDA_ROOT:-/usr/local/cuda-12.5}
KOKKOS_ROOT=${KOKKOS_ROOT:-/hdd1/dsmc/comet/comet_kokkos4.6.02/install/kokkos/install}
NVCC_WRAPPER=${NVCC_WRAPPER:-/hdd1/dsmc/comet/comet_kokkos4.6.02/kokkos/bin/nvcc_wrapper}
export PATH=$CUDA_ROOT/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_ROOT/lib64:$LD_LIBRARY_PATH
src=$(cd "$(dirname "$0")" && pwd)

# build_one <tag> "<flags>" [extra cmake args]
build_one() {
  local tag=$1 flags=$2; shift 2
  local dir="$src/build_$tag"
  mkdir -p "$dir" || return 1
  ( cd "$dir" &&
    cmake "$src" -DCMAKE_PREFIX_PATH="$KOKKOS_ROOT" -DCMAKE_CXX_COMPILER="$NVCC_WRAPPER" \
          -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE="$flags" "$@" > cmake.log 2>&1 ) \
    || { echo "FAILED build_$tag at cmake; last lines of build_$tag/cmake.log:"; tail -20 "$dir/cmake.log"; return 1; }
  ( cd "$dir" && make -j4 > make.log 2>&1 ) \
    || { echo "FAILED build_$tag at make; last lines of build_$tag/make.log:"; tail -20 "$dir/make.log"; return 1; }
  echo "built build_$tag/repro with flags: $flags $*"
}

if [ $# -gt 0 ]; then
  build_one "$@"
  exit $?
fi

# No arguments: build every configuration, carry on past a failure, report at the end.
failed=()
build_one O0       "-O0"          || failed+=(O0)
build_one O1       "-O1"          || failed+=(O1)
build_one O2       "-O2"          || failed+=(O2)
build_one O3       "-O3 -DNDEBUG" || failed+=(O3)
build_one O2_unity "-O2" -DCMAKE_UNITY_BUILD=ON -DCMAKE_UNITY_BUILD_BATCH_SIZE=0 || failed+=(O2_unity)
if [ ${#failed[@]} -gt 0 ]; then
  echo "builds that failed: ${failed[*]}"
  exit 1
fi
echo "all 5 builds done; run them with ./run_all.sh, or one with e.g. ./build_O2/repro"
