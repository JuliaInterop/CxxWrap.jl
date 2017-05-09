#include <string>
#include <memory>

#include "cxx_wrap/cxx_wrap.hpp"

struct A
{
  virtual std::string message() const = 0;
  std::string data = "mydata";
};

struct B : A
{
  virtual std::string message() const
  {
    return "B";
  }
};

struct C : B
{
  C() { this->data = "C"; }
  virtual std::string message() const
  {
    return "C";
  }
};

struct D : A
{
  virtual std::string message() const
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

std::string take_ref(A& a)
{
  return a.message();
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

  types.method("weak_ptr_message_a", [](const std::weak_ptr<A>& x) { return x.lock()->message(); });
  types.method("weak_ptr_message_b", [](const std::weak_ptr<B>& x) { return x.lock()->message(); });

  types.method("dynamic_message_c", [](const A* c) { return dynamic_cast<const C*>(c)->data; });

  types.method("take_ref", take_ref);

  types.export_symbols("A", "B", "C", "D", "message", "create_abstract", "shared_ptr_message", "shared_b", "shared_c", "shared_d", "weak_ptr_message_a", "weak_ptr_message_b", "dynamic_message_c", "take_ref");
JULIA_CPP_MODULE_END
