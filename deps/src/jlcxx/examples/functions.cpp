#include <algorithm>
#include <sstream>
#include <cstddef>

#include "jlcxx/jlcxx.hpp"
#include "jlcxx/array.hpp"
#include "jlcxx/functions.hpp"

#ifdef _WIN32
  #ifdef JLCXX_EXAMPLES_EXPORTS
      #define JLCXX_EXAMPLES_API __declspec(dllexport)
  #else
      #define JLCXX_EXAMPLES_API __declspec(dllimport)
  #endif
#else
  #define JLCXX_EXAMPLES_API
#endif

// C function for performance comparison
extern "C" JLCXX_EXAMPLES_API double half_c(const double d)
{
  return 0.5 * d;
}

namespace functions
{

double half_function(const double d)
{
  return 0.5 * d;
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

std::size_t test_array_len(jlcxx::ArrayRef<double> a)
{
  return a.size();
}

double test_array_get(jlcxx::ArrayRef<double> a, const int64_t i)
{
  return a[i];
}

void test_array_set(jlcxx::ArrayRef<double> a, const int64_t i, const double v)
{
  a[i] = v;
}

long long int test_long_long()
{
  return 42;
}

short test_short()
{
  return 43;
}

void test_exception()
{
  throw std::runtime_error("This is an exception");
}

std::string test_type_name(const std::string& name)
{
  return jlcxx::julia_type_name(jlcxx::julia_type(name));
}

void init_half_module(jlcxx::Module& mod)
{
  // register a standard C++ function
  mod.method("half_d", half_function);

  // register some template instantiations
  mod.method("half_i", half_template<int>);
  mod.method("half_u", half_template<unsigned int>);

  // Register a lambda
  mod.method("half_lambda", [](const double a) {return a*0.5;});

  // Strict number typing
  mod.method("strict_half", [](const jlcxx::StrictlyTypedNumber<double> a) {return a.value*0.5;});

  // Looping function
  mod.method("half_loop_cpp!",
  [](jlcxx::ArrayRef<double> in, jlcxx::ArrayRef<double> out)
  {
    std::transform(in.begin(), in.end(), out.begin(), [](const double d) { return 0.5*d; });
  });

  // Looping function calling Julia
  mod.method("half_loop_jlcall!",
  [](jlcxx::ArrayRef<double> in, jlcxx::ArrayRef<double> out)
  {
    jlcxx::JuliaFunction f("half_julia");
    std::transform(in.begin(), in.end(), out.begin(), [=](const double d)
    {
      return jl_unbox_float64(f(d));
    });
  });

  // Looping function calling Julia cfunction
  mod.method("half_loop_cfunc!",
  [](jlcxx::ArrayRef<double> in, jlcxx::ArrayRef<double> out, double(*f)(const double))
  {
    std::transform(in.begin(), in.end(), out.begin(), f);
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

double g_test_double = 0.0;
double& get_test_double_ref()
{
  return g_test_double;
}

double get_test_double()
{
  return g_test_double;
}

void init_test_module(jlcxx::Module& mod)
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
  mod.method("test_long_long", test_long_long);
  mod.method("test_short", test_short);
  mod.method("test_julia_call", [](double a, double b)
  {
    jlcxx::JuliaFunction julia_max("max");
    return julia_max(a, b);
  });
  mod.method("test_string_array", [](jlcxx::ArrayRef<std::string> arr)
  {
    return arr[0] == "first" && arr[1] == "second" && *(arr.begin()) == "first" && *(++arr.begin()) == "second";
  });
  mod.method("test_append_array!", [](jlcxx::ArrayRef<double> arr)
  {
    arr.push_back(3.);
  });
  // Typed callback
  mod.method("test_safe_cfunction", [](jlcxx::SafeCFunction f_data)
  {
    auto f = jlcxx::make_function_pointer<double(double,double)>(f_data);
    std::cout << "callback result for function " << f_data.fptr << " is " << f(1.,2.) << std::endl;
    if(f(1.,2.) != 3.)
    {
      throw std::runtime_error("Incorrect callback result, expected 3");
    }
  });
  // Typed callback, using a pointer
  mod.method("test_safe_cfunction2", [](double(*f)(double,double))
  {
    std::cout << "callback result for function " << (void*)f << " is " << f(1.,2.) << std::endl;
    if(f(1.,2.) != 3.)
    {
      throw std::runtime_error("Incorrect callback result, expected 3");
    }
  });
  mod.method("test_safe_cfunction3", [](void (*f) (const double* const, int_t))
  {
    static const double arr[] = {1.0, 2.0};
    f(arr,2);
  });
  // Write to reference
  mod.method("test_double_ref", [](double& d) { d = 1.0; });
  mod.method("get_test_double_ref", get_test_double_ref);
  mod.method("get_test_double", get_test_double);

  // Const string return
  mod.method("test_const_string_return", []() -> const std::string { return "test"; });
  mod.method("test_datatype_conversion", [] (jlcxx::SingletonType<double>) { return jl_float64_type; });
  mod.method("test_double_pointer", [] () { return static_cast<double*>(nullptr); });
  mod.method("test_double2_pointer", [] () { return static_cast<double**>(nullptr); });
  mod.method("test_double3_pointer", [] () { return static_cast<double***>(nullptr); });

  // wstring
  mod.method("test_wstring_to_julia", [] () { return std::wstring(L"šČô_φ_привет_일보"); });
  mod.method("test_wstring_to_cpp", [] (const std::wstring& ws) { return ws == L"šČô_φ_привет_일보"; });

  // complex
  mod.method("real_part", [](std::complex<double> c) { return c.real(); } );
  mod.method("imag_part", [](const std::complex<double>& c) { return c.imag(); } );
  mod.method("make_complex", [](const float a, const float b) { return std::complex<float>(a,b); });

  // Irrational
  mod.method("process_irrational", [] (const double irr, const double fact) { return irr*fact; });
}

}

JULIA_CPP_MODULE_BEGIN(registry)
  functions::init_half_module(registry.create_module("CppHalfFunctions"));
  functions::init_test_module(registry.create_module("CppTestFunctions"));
JULIA_CPP_MODULE_END
