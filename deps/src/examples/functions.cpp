#include <cpp_wrapper.hpp>
#include <sstream>

extern "C" double half_c(const double input)
{
  return input*0.5;
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

void init_half_module(cpp_wrapper::Module& mod)
{
	// register a standard C++ function
	mod.def("half_d", &half_function);

	// register some template instantiations
	mod.def("half_i", &half_template<int>);
	mod.def("half_u", &half_template<unsigned int>);

	// Register a lambda
  mod.def("half_lambda", std::function<double(double)>([](const double a) {return a*0.5;}));
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

void init_test_module(cpp_wrapper::Module& mod)
{
  mod.def("concatenate_numbers", &concatenate_numbers);
  mod.def("concatenate_strings", &concatenate_strings);
}

}

JULIA_CPP_MODULE_BEGIN(registry)
  functions::init_half_module(registry.create_module("CppHalfFunctions"));
  functions::init_test_module(registry.create_module("CppTestFunctions"));
JULIA_CPP_MODULE_END
