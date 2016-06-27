#include <cxx_wrap.hpp>
#include <array.hpp>

#include <algorithm>
#include <sstream>

// C function for performance comparison
extern "C" CXX_WRAP_EXPORT double half_c(const double d)
{
  return 0.5*d;
}

namespace functions
{

double half_function(const double d)
{
  return 0.5*d;
}

template<typename T>
T half_template (const T x)
{
  return x / static_cast<T>(2);
}

bool test_int32_array(int32_t* f)
{
  return f[0] == 1 && f[1] == 2;
}

bool test_int64_array(int64_t* f)
{
  return f[0] == 1 && f[1] == 2;
}

bool test_float_array(float* f)
{
  return f[0] == 1. && f[1] == 2.;
}

bool test_double_array(double* f)
{
  return f[0] == 1. && f[1] == 2.;
}

std::size_t test_array_len(cxx_wrap::ArrayRef<double> a)
{
  return a.size();
}

double test_array_get(cxx_wrap::ArrayRef<double> a, const int64_t i)
{
  return a[i];
}

void test_array_set(cxx_wrap::ArrayRef<double> a, const int64_t i, const double v)
{
  a[i] = v;
}

void test_exception()
{
  throw std::runtime_error("This is an exception");
}

std::string test_type_name(const std::string& name)
{
  return cxx_wrap::julia_type_name(cxx_wrap::julia_type(name));
}

void init_half_module(cxx_wrap::Module& mod)
{
  // register a standard C++ function
  mod.method("half_d", half_function);

  // register some template instantiations
  mod.method("half_i", half_template<int>);
  mod.method("half_u", half_template<unsigned int>);

  // Register a lambda
  mod.method("half_lambda", [](const double a) {return a*0.5;});

  // Looping function
  mod.method("half_loop_cpp!",
  [](cxx_wrap::ArrayRef<double> in, cxx_wrap::ArrayRef<double> out)
  {
    std::transform(in.begin(), in.end(), out.begin(), [](const double d) { return 0.5*d; });
  });
}

// Test for string conversion. Pointer to this function is passed to Julia as-is.
std::string concatenate_numbers(int i, double d)
{
  std::stringstream stream;
  stream << i << d;
  return stream.str();
}

std::string concatenate_strings(const int n, std::string s, const std::string& s2)
{
  std::string result;
  for(int i = 0; i != n; ++i)
  {
    result += s + s2;
  }
  return result;
}

void init_test_module(cxx_wrap::Module& mod)
{
  mod.method("concatenate_numbers", &concatenate_numbers);
  mod.method("concatenate_strings", &concatenate_strings);
  mod.method("test_int32_array", test_int32_array);
  mod.method("test_int64_array", test_int64_array);
  mod.method("test_float_array", test_float_array);
  mod.method("test_double_array", test_double_array);
  mod.method("test_exception", test_exception, true);
  mod.method("test_array_len", test_array_len);
  mod.method("test_array_set", test_array_set);
  mod.method("test_array_get", test_array_get);
  mod.method("test_type_name", test_type_name);
}

}

JULIA_CPP_MODULE_BEGIN(registry)
  functions::init_half_module(registry.create_module("CppHalfFunctions"));
  functions::init_test_module(registry.create_module("CppTestFunctions"));
JULIA_CPP_MODULE_END
