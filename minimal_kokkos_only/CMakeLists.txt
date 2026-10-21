cmake_minimum_required(VERSION 3.16)
project(kokkos_cuda_static_kernel_reproducer CXX)
find_package(Kokkos REQUIRED)
# destroy.cpp is linked first, so its copies of the shared (COMDAT) code are kept.
add_executable(repro destroy.cpp make.cpp main.cpp)
target_link_libraries(repro Kokkos::kokkos)
