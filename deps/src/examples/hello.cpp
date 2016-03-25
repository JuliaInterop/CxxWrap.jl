#include <string>

#include <cxx_wrap.hpp>

std::string greet()
{
   return "hello, world";
}

JULIA_CPP_MODULE_BEGIN(registry)
  cxx_wrap::Module& hello = registry.create_module("CppHello");
  hello.method("greet", &greet);
JULIA_CPP_MODULE_END
