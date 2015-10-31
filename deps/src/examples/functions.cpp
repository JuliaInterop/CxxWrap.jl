#include <cpp_wrapper.hpp>


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

void init_functions_module()
{
	cpp_wrapper::module& mod = cpp_wrapper::register_module("functions");

	// register a standard C++ function
	mod.def("half_d", &half_function);

	// register some template instantiations
	mod.def("half_i", &half_template<int>);
	mod.def("half_u", &half_template<unsigned int>);

	// Register a lambda
	mod.def("third_lambda", std::function<double(double)>([](const double a) {return a/3.;}));
}

}

extern "C"
{
  void init()
  {
		functions::init_functions_module();
  }
}
