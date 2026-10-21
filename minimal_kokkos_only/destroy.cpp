#include "structure.hpp"
// Only deletes. The host compiler emits Structure<double>'s vtable here (the
// destructor needs it), which instantiates rebuild() and its kernel stub.
// nvcc's device pass does not instantiate rebuild() here, so this object carries
// a host stub for the kernel that it never registers with the CUDA runtime.
void destroy_only(Structure<double>* s) { delete s; }
