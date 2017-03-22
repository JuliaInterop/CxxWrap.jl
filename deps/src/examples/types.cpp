#include <string>

#include <cxx_wrap.hpp>
#include <functions.hpp>

namespace cpp_types
{

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
  jl_value_t* result = jl_new_struct_uninit(cxx_wrap::julia_type("JuliaTestType"));
  *reinterpret_cast<JuliaTestType*>(result) = A;
  cxx_wrap::JuliaFunction("julia_test_func")(result);
}

enum CppEnum
{
  EnumValA,
  EnumValB
};

} // namespace cpp_types

namespace cxx_wrap
{
  template<> struct IsBits<cpp_types::CppEnum> : std::true_type {};
}

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cpp_types;

  cxx_wrap::Module& types = registry.create_module("CppTypes");

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

  // types.method("shared_world_factory", []()
  // {
  //   return std::shared_ptr<World>(new World("shared factory hello"));
  // });
  // // Shared ptr overload for greet
  // types.method("greet", [](const std::shared_ptr<World>& w)
  // {
  //   return w->greet();
  // });
  //
  // types.method("unique_world_factory", []()
  // {
  //   return std::unique_ptr<World>(new World("unique factory hello"));
  // });

  types.add_type<NonCopyable>("NonCopyable");

  types.add_type<AConstRef>("AConstRef").method("value", &AConstRef::value);
  types.add_type<ReturnConstRef>("ReturnConstRef").method("value", &ReturnConstRef::operator());

  types.add_type<CallOperator>("CallOperator").method(&CallOperator::operator());

  types.add_type<ConstPtrConstruct>("ConstPtrConstruct")
    .constructor<const World*>()
    .method("greet", &ConstPtrConstruct::greet);

  // Enum
  types.add_bits<CppEnum>("CppEnum");
  types.set_const("EnumValA", EnumValA);
  types.set_const("EnumValB", EnumValB);
  types.method("enum_to_int", [] (const CppEnum e) { return static_cast<int>(e); });
  types.method("get_enum_b", [] () { return EnumValB; });

  types.export_symbols("enum_to_int", "get_enum_b", "World");
  types.export_symbols("AConstRef", "ReturnConstRef", "value", "CallOperator", "ConstPtrConstruct");
JULIA_CPP_MODULE_END
