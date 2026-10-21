#include <cstdio>
#include "structure.hpp"
int main(int argc, char* argv[]) {
  Kokkos::ScopeGuard guard(argc, argv);
  Structure<double>* s = make(100);
  Base<double>* b = s;
  b->rebuild();   // virtual call
  auto h = Kokkos::create_mirror_view_and_copy(Kokkos::HostSpace(), s->v);
  const bool ok = (h(0) == 1.0);
  printf("%s: v(0) = %g, expected 1\n", ok ? "PASS" : "FAIL", h(0));
  destroy_only(s);
  return ok ? 0 : 1;
}
