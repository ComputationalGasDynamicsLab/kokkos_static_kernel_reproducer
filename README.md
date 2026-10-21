# Minimal reproducer: `cudaErrorInvalidDeviceFunction` in Release (`-O2`) builds of Kokkos CUDA code

This reproduces, with Kokkos alone, the abort that Comet's Release build hits at its first particle
move:

```
terminate called after throwing an instance of 'std::runtime_error'
  what():  cudaFuncGetAttributes(&attr, func) error( cudaErrorInvalidDeviceFunction): invalid device function
  .../kokkos/install/include/Cuda/Kokkos_Cuda_KernelLaunch.hpp:140
```

The reproducer is in [`minimal_kokkos_only/`](minimal_kokkos_only/): three source files and a header,
about 60 lines, with no pumi-pic, Cabana or MPI. The same failure also reproduces with the real
pumi-pic `DPS` and Comet's particle types, using the same three-file pattern.

## Result

```
$ ./minimal_kokkos_only/run_all.sh
O0         exit=0     PASS: v(0) = 1, expected 1
O1         exit=0     PASS: v(0) = 1, expected 1
O2         exit=134   what():  cudaFuncGetAttributes(&attr, func) error( cudaErrorInvalidDeviceFunction): invalid device function
O3         exit=134   what():  cudaFuncGetAttributes(&attr, func) error( cudaErrorInvalidDeviceFunction): invalid device function
O2_unity   exit=0     PASS: v(0) = 1, expected 1
```

`O3` is built with `-O3 -DNDEBUG`. `O2_unity` is `-O2` with `-DCMAKE_UNITY_BUILD=ON
-DCMAKE_UNITY_BUILD_BATCH_SIZE=0`.

Toolchain: GCC 11.5.0 (host compiler, through `nvcc_wrapper`), CUDA 12.5 (non-RDC), Kokkos 4.6.02
built with `Kokkos_ARCH_ADA89=ON`, `Kokkos_ENABLE_CUDA_LAMBDA=ON`, `Kokkos_ENABLE_DEBUG=ON` and shared
libraries; RTX 4060 (sm_89).

## The code

`structure.hpp` defines a class template with:

- a **virtual** member function `rebuild()` that launches a Kokkos kernel through `KOKKOS_LAMBDA`
  (defined outside the class body to match pumi-pic, though an in-class definition fails the same
  way);
- a **user-provided destructor, defined outside the class body**, that frees a heap member.

This is the shape of `pumipic::DPS<...>`, whose `rebuild` is virtual (declared in `ParticleStructure`)
and defined in `dps_rebuild.hpp`, and whose destructor is `DPS<...>::~DPS() { delete aosoa_; }`.

| File | Does | Comet counterpart |
|---|---|---|
| `destroy.cpp` | only `delete`s the object | `comet_init_objects.cpp`, `comet_main_loop.cpp` |
| `make.cpp` | constructs the object | `comet_particle.cpp` (`initializeMolecule`) |
| `main.cpp` | calls the virtual `rebuild()` | `comet_move.cpp` |

`destroy.cpp` is listed first in `CMakeLists.txt`, so the linker keeps its copies of the shared
(COMDAT) code. In Comet, `comet_init_objects.cpp.o` is the corresponding object.

## Mechanism (each step observed in this reproducer)

1. **A host stub without device code.** `destroy.cpp` never calls `rebuild()`, but GCC emits the
   class's vtable there (the destructor needs it), and emitting the vtable instantiates every virtual
   function, so `rebuild()` and the host stub of its Kokkos kernel are compiled into `destroy.cpp.o`.
   nvcc's device pass does not instantiate `rebuild()` in this file. So `destroy.cpp.o` holds a host
   stub for the kernel but no device code for it, and its static constructor never registers that
   stub with the CUDA runtime (`__cudaRegisterFunction`).

   | Object (`-O2`) | `rebuild` kernel host stubs | `rebuild` in device code |
   |---|---|---|
   | `destroy.cpp.o` | 1 | 0 |
   | `make.cpp.o` | 1 | 19 strings |
   | `main.cpp.o` | 0 | 0 |

2. **Kokkos declares its kernel `static`**
   (`__global__ static void cuda_parallel_launch_local_memory(...)`, `Kokkos_Cuda_KernelLaunch.hpp:85`).
   Each translation unit therefore has its own private stub, while the code that takes the stub's
   address (`Kokkos::Impl::ParallelFor<...>`, `get_cuda_kernel_func_attributes<...>`) is shared
   template code in a COMDAT group, of which the linker keeps one copy.

3. **At `-O2`, GCC moves the unregistered stub into that COMDAT group.** Nothing else in
   `destroy.cpp.o` refers to the stub (no registration code does), so GCC places it in the COMDAT group
   of the `ParallelFor` code that launches it.

   | `destroy.cpp.o` | local kernel stubs | inside a COMDAT group |
   |---|---|---|
   | `-O1` | 1 | 0 |
   | `-O2` | 2 | 1 |

   At `-O1` the stub stays in `.text`; in this reproducer `destroy.cpp.o` then carries no `rebuild`
   stub at all, and the copy that runs is `make.cpp`'s.

4. **The linker keeps `destroy.cpp`'s copy of the launch code, and with it the unregistered stub.**
   In the linked `-O2` binary:

   | `rebuild` kernel stub | registered | referenced by |
   |---|---|---|
   | `0x4051f0` (from `destroy.cpp.o`, in the COMDAT group) | **no** | the kept `ParallelFor` code at `0x406cc0` |
   | `0x407e40` (from `make.cpp.o`) | yes | (not used by the kept launch code) |

   The backtrace (gdb, `catch throw`) is `main` → `Structure<double>::rebuild` →
   `Kokkos::parallel_for` → `Kokkos::Impl::ParallelFor<...>` (`0x406ccf`) →
   `get_cuda_kernel_func_attributes` → `cudaFuncGetAttributes` on the unregistered stub →
   `cudaErrorInvalidDeviceFunction`.

The root defect is that shared (COMDAT) template code takes the address of a `static`, per-translation-
unit kernel stub, which violates the One Definition Rule (no diagnostic required). The program then
works or fails depending on how GCC and the linker lay the copies out. The missing device code in
`destroy.cpp` (step 1) is what makes one copy unregistered; the `-O2` placement (step 3) is what makes
the linker pick that copy.

## Workaround

Compile everything that launches the kernel as one translation unit (CMake unity build,
`-DCMAKE_UNITY_BUILD=ON -DCMAKE_UNITY_BUILD_BATCH_SIZE=0`). There is then one stub, registered by the
same object that launches it. `O2_unity` above passes. The same workaround makes Comet's `-O3 -DNDEBUG`
build run correctly (see the Comet write-up below).

## How to run

```bash
cd minimal_kokkos_only
# defaults point at /hdd1/dsmc/comet/comet_kokkos4.6.02; override as needed:
#   export KOKKOS_ROOT=<kokkos install prefix>  NVCC_WRAPPER=<kokkos>/bin/nvcc_wrapper  CUDA_ROOT=<cuda>
./run_all.sh                 # all five builds
./build.sh O2 "-O2" && ./build_O2/repro    # a single build
```

Each build writes `build_<tag>/` next to the sources.

## What is necessary

Each of these was found necessary while reducing the reproducer:

- **A file that only destroys the object.** Without it, every file with the host stub also has its
  device code, and the program passes at every level.
- **The destroying file must not call `rebuild()`.** A call makes nvcc generate the device code in
  that file too, and its stub is then registered.
- **A user-provided destructor defined outside the class body.** With the implicit destructor, GCC
  at `-O1` and `-O2` no longer emits the vtable, and with it the stub, in `destroy.cpp`.

Not necessary:

- defining `rebuild()` outside the class body: with an in-class definition the reproducer still
  passes at `-O1` and fails at `-O2`;
- in the pumi-pic version, a second argument to `rebuild()`, or pumi-pic's own `parallel_for`:
  removing either still fails at `-O2`.

## Related

- Comet write-up of the root cause and the unity-build fix:
  `/hdd1/dsmc/comet/comet_cases/2d_cases/2d_flow_over_cylinder/coarse_mesh/postproc_release_O1_vs_debug_cba5d59_step10000/comet_release_build_invalid_device_function_fix.md`
# kokkos_static_kernel_reproducer
