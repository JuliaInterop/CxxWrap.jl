#include <type_traits>
#include <string>
#include <memory>
#include <iostream>

#include "jlcxx/jlcxx.hpp"
#include "jlcxx/functions.hpp"

namespace cpp_types
{

// Custom minimal smart pointer type
template<typename T>
struct MySmartPointer
{
  MySmartPointer(T* ptr) : m_ptr(ptr)
  {
  }

  MySmartPointer(std::shared_ptr<T> ptr) : m_ptr(ptr.get())
  {
  }

  T& operator*() const
  {
    return *m_ptr;
  }

  T* m_ptr;
};

struct DoubleData
{
  double a[4];
};

struct World
{
  World(const std::string& message = "default hello") : msg(message){}
  void set(const std::string& msg) { this->msg = msg; }
  const std::string& greet() const { return msg; }
  std::string msg;
  ~World() { std::cout << "Destroying World with message " << msg << std::endl; }
};

struct NonCopyable
{
  NonCopyable() {}
  NonCopyable& operator=(const NonCopyable&) = delete;
  NonCopyable(const NonCopyable&) = delete;
};

struct AConstRef
{
  int value() const
  {
    return 42;
  }
};

struct ReturnConstRef
{
  const AConstRef& operator()()
  {
    return m_val;
  }

  AConstRef m_val;
};

struct CallOperator
{
  int operator()() const
  {
    return 43;
  }
};

struct ConstPtrConstruct
{
  ConstPtrConstruct(const World* w) : m_w(w)
  {
  }

  const std::string& greet() { return m_w->greet(); }

  const World* m_w;
};

// Call a function on a type that is defined in Julia
struct JuliaTestType {
  double a;
  double b;
};
void call_testype_function()
{
  JuliaTestType A = {2., 3.};
  jl_value_t* result = jl_new_struct_uninit(jlcxx::julia_type("JuliaTestType"));
  *reinterpret_cast<JuliaTestType*>(result) = A;
  jlcxx::JuliaFunction("julia_test_func")(result);
}

enum CppEnum
{
  EnumValA,
  EnumValB
};

} // namespace cpp_types

namespace jlcxx
{
  template<> struct IsBits<cpp_types::CppEnum> : std::true_type {};
  template<typename T> struct IsSmartPointerType<cpp_types::MySmartPointer<T>> : std::true_type { };
  template<typename T> struct ConstructorPointerType<cpp_types::MySmartPointer<T>> { typedef std::shared_ptr<T> type; };
}

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cpp_types;

  jlcxx::Module& types = registry.create_module("CppTypes");

  types.method("call_testype_function", call_testype_function);

  types.add_type<DoubleData>("DoubleData");

  types.add_type<World>("World")
    .constructor<const std::string&>()
    .method("set", &World::set)
    .method("greet", &World::greet);
  types.method("world_factory", []()
  {
    return new World("factory hello");
  });

  types.method("shared_world_factory", []() -> const std::shared_ptr<World>
  {
    return std::shared_ptr<World>(new World("shared factory hello"));
  });
  // Shared ptr overload for greet
  types.method("greet_shared", [](const std::shared_ptr<World>& w)
  {
    return w->greet();
  });
  types.method("greet_shared_const", [](const std::shared_ptr<const World>& w)
  {
    return w->greet();
  });

  types.method("smart_world_factory", []()
  {
    return MySmartPointer<World>(new World("smart factory hello"));
  });
  // smart ptr overload for greet
  types.method("greet_smart", [](const MySmartPointer<World>& w)
  {
    return (*w).greet();
  });

  // weak ptr overload for greet
  types.method("greet_weak", [](const std::weak_ptr<World>& w)
  {
    return w.lock()->greet();
  });

  types.method("unique_world_factory", []()
  {
    return std::unique_ptr<const World>(new World("unique factory hello"));
  });

  types.method("world_by_value", [] () -> World
  {
    return World("world by value hello");
  });

  types.method("boxed_world_factory", []()
  {
    static World w("boxed world");
    return jlcxx::box(w);
  });

  types.method("boxed_world_pointer_factory", []()
  {
    static World w("boxed world pointer");
    return jlcxx::box(&w);
  });

  types.add_type<NonCopyable>("NonCopyable");

  types.add_type<AConstRef>("AConstRef").method("value", &AConstRef::value);
  types.add_type<ReturnConstRef>("ReturnConstRef").method("value", &ReturnConstRef::operator());

  types.add_type<CallOperator>("CallOperator").method(&CallOperator::operator());

  types.add_type<ConstPtrConstruct>("ConstPtrConstruct")
    .constructor<const World*>()
    .method("greet", &ConstPtrConstruct::greet);

  // Enum
  types.add_bits<CppEnum>("CppEnum", jlcxx::julia_type("CppEnum"));
  types.set_const("EnumValA", EnumValA);
  types.set_const("EnumValB", EnumValB);
  types.method("enum_to_int", [] (const CppEnum e) { return static_cast<int>(e); });
  types.method("get_enum_b", [] () { return EnumValB; });

  types.export_symbols("enum_to_int", "get_enum_b", "World");
  types.export_symbols("AConstRef", "ReturnConstRef", "value", "CallOperator", "ConstPtrConstruct");
JULIA_CPP_MODULE_END
