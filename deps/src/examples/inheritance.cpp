#include <string>

#include <cpp_wrapper.hpp>

struct A
{
  virtual std::string message() = 0;
};

struct B : A
{
  virtual std::string message()
  {
    return "B";
  }
};

JULIA_CPP_MODULE_BEGIN(registry)
  cpp_wrapper::Module& types = registry.create_module("CppInheritance");
  types.add_abstract<A>("A")
    .def("message", &A::message);
  types.add_type<B>("B");
JULIA_CPP_MODULE_END
