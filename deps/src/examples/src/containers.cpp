#include <tuple>

#include "cxx_wrap/array.hpp"
#include "cxx_wrap/cxx_wrap.hpp"
#include "cxx_wrap/tuple.hpp"
#include "cxx_wrap/const_array.hpp"

const double* const_vector()
{
  static double d[] = {1., 2., 3};
  return d;
}

const double* const_matrix()
{
  static double d[2][3] = {{1., 2., 3}, {4., 5., 6.}};
  return &d[0][0];
}

double mutable_array[2][3] = {{1., 2., 3}, {4., 5., 6.}};

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cxx_wrap;

  cxx_wrap::Module& containers = registry.create_module("Containers");

  containers.method("test_tuple", []() { return std::make_tuple(1, 2., 3.f); });
  containers.method("const_ptr", []() { return ConstPtr<double>({const_vector()}); });
  containers.method("const_ptr_arg", [](ConstPtr<double> p) { return std::make_tuple(p.ptr[0], p.ptr[1], p.ptr[2]); });
  containers.method("const_vector", []() { return cxx_wrap::make_const_array(const_vector(), 3); });
  // Note the column-major order for matrices
  containers.method("const_matrix", []() { return cxx_wrap::make_const_array(const_matrix(), 3, 2); });

  containers.method("mutable_array", []() { return (jl_value_t*)cxx_wrap::ArrayRef<double, 2>(&mutable_array[0][0], 3, 2).wrapped(); });
  containers.method("check_mutable_array", [](cxx_wrap::ArrayRef<double, 2> arr)
  {
    for(auto el : arr)
    {
      if(el != 1.0)
      {
        return false;
      }
    }
    return true;
  });

  containers.export_symbols("test_tuple", "const_ptr", "const_ptr_arg", "const_vector", "const_matrix");
JULIA_CPP_MODULE_END
