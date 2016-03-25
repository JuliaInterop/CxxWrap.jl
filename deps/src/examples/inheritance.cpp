#include <string>

#include <cxx_wrap.hpp>

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

struct AWrapper
{
  template<typename T>
  void operator()(T& wrapped)
  {

  }
};

struct BWrapper
{
  template<typename T>
  void operator()(T& wrapped)
  {
  }
};

JULIA_CPP_MODULE_BEGIN(registry)
  cxx_wrap::Module& types = registry.create_module("CppInheritance");
  types.add_abstract<A>("A").method("message", &A::message);
  types.add_type<B>("B", cxx_wrap::julia_type<A>());
JULIA_CPP_MODULE_END
