// Minimal reproducer: Comet Release build "cudaErrorInvalidDeviceFunction".
// A class template with a VIRTUAL member function, defined outside the class body,
// that launches a Kokkos kernel (the shape of pumipic::DPS<...>::rebuild).
#pragma once
#include <Kokkos_Core.hpp>

template <class T>
struct Base {
  virtual ~Base() {}
  virtual void rebuild() = 0;
};

template <class T>
struct Structure : Base<T> {
  Kokkos::View<T*> v;
  int* buffer;                       // heap member freed by the destructor, like DPS::aosoa_
  explicit Structure(int n) : v("v", n), buffer(new int[n]) {}
  ~Structure();                      // user-provided, defined outside the class, like DPS::~DPS
  void rebuild() override;
};

template <class T>
Structure<T>::~Structure() { delete[] buffer; }

template <class T>
void Structure<T>::rebuild() {
  auto v_ = v;
  Kokkos::parallel_for("rebuild", v_.extent(0), KOKKOS_LAMBDA(const int i) { v_(i) += 1; });
}

Structure<double>* make(int n);           // make.cpp:    constructs the object
void destroy_only(Structure<double>* s);  // destroy.cpp: only deletes the object
