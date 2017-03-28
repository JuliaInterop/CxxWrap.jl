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

struct C : B
{
  virtual std::string message()
  {
    return "C";
  }
};

struct D : A
{
  virtual std::string message()
  {
    return "D";
  }
};

B b;

A* create_abstract()
{
  b = B();
  return &b;
}

namespace cxx_wrap
{
  // Needed for shared pointer downcasting
  template<> struct SuperType<D> { typedef A type; };
  template<> struct SuperType<C> { typedef B type; };
  template<> struct SuperType<B> { typedef A type; };
}

JULIA_CPP_MODULE_BEGIN(registry)
  cxx_wrap::Module& types = registry.create_module("CppInheritance");
  types.add_type<A>("A").method("message", &A::message);
  types.add_type<B>("B", cxx_wrap::julia_type<A>());
  types.add_type<C>("C", cxx_wrap::julia_type<B>());
  types.add_type<D>("D", cxx_wrap::julia_type<A>());
  types.method("create_abstract", create_abstract);

  types.method("shared_b", []() { return std::make_shared<B>(); });
  types.method("shared_c", []() { return std::make_shared<C>(); });
  types.method("shared_d", []() { return std::make_shared<D>(); });
  types.method("shared_ptr_message", [](const std::shared_ptr<A>& x) { return x->message(); });

  types.export_symbols("A", "B", "C", "D", "message", "create_abstract", "shared_ptr_message", "shared_b", "shared_c", "shared_d");
JULIA_CPP_MODULE_END
