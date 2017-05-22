#include <string>

#include "jlcxx/jlcxx.hpp"

std::string greet()
{
   return "hello, world";
}

JULIA_CPP_MODULE_BEGIN(registry)
  jlcxx::Module& hello = registry.create_module("CppHello");
  hello.method("greet", &greet);
JULIA_CPP_MODULE_END
