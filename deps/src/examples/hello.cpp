#include <string>

#include <cpp_wrapper.hpp>

std::string greet()
{
   return "hello, world";
}

JULIA_CPP_MODULE_BEGIN(registry)
  cpp_wrapper::Module& hello = registry.create_module("CppHello");
  hello.def("greet", &greet);
JULIA_CPP_MODULE_END
