#include <string>

#include <cxx_wrap.hpp>

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
  std::string greet() { return msg; }
  std::string msg;
  ~World() { std::cout << "Destroying World with message " << msg << std::endl; }
};

struct NonCopyable
{
  NonCopyable() {}
  NonCopyable& operator=(const NonCopyable&) = delete;
  NonCopyable(const NonCopyable&) = delete;
};

class ImmutableDouble
{
public:
  ImmutableDouble(const double value = 0) : m_value(value)
  {
  }

  double get_value() const
  {
    return m_value;
  }

private:
  double m_value;
};

struct BitsClass
{
  double a;
  double b;

  double get_b() const
  {
    return b;
  }

  void set_b(const double x)
  {
    b = x;
  }

  ~BitsClass() {}
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

} // namespace cpp_types

namespace cxx_wrap
{
  template<> struct IsImmutable<cpp_types::ImmutableDouble> : std::true_type {};
  template<> struct IsBits<cpp_types::BitsClass> : std::true_type {};
}

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cpp_types;

  cxx_wrap::Module& types = registry.create_module("CppTypes");

  types.add_type<DoubleData>("DoubleData");

  types.add_type<World>("World")
    .constructor<const std::string&>()
    .method("set", &World::set)
    .method("greet", &World::greet);
  types.method("world_factory", []()
  {
    return new World("factory hello");
  });

  types.method("shared_world_factory", []()
  {
    return std::shared_ptr<World>(new World("shared factory hello"));
  });
  // Shared ptr overload for greet
  types.method("greet", [](const std::shared_ptr<World>& w)
  {
    return w->greet();
  });

  types.method("unique_world_factory", []()
  {
    return std::unique_ptr<World>(new World("unique factory hello"));
  });

  types.add_type<NonCopyable>("NonCopyable");

  // ImmutableDouble
  types.add_immutable<ImmutableDouble>("ImmutableDouble", cxx_wrap::FieldList<double>("value"))
    .constructor<double>()
    .method("getvalue", &ImmutableDouble::get_value);
  types.method("convert", [](cxx_wrap::SingletonType<double>, const ImmutableDouble& a) { return a.get_value(); });
  types.method("+", [](const ImmutableDouble& a, const ImmutableDouble& b) { return ImmutableDouble(a.get_value() + b.get_value()); });
  types.method("==", [](const ImmutableDouble& a, const double b) { return a.get_value() == b; } );
  types.method("==", [](const double b, const ImmutableDouble& a) { return a.get_value() == b; } );

  types.add_bits<BitsClass>("BitsClass");
  types.method("make_bits", [](const double a, const double b)
  {
    BitsClass result;
    result.a = a;
    result.set_b(b);
    return result;
  });

  types.method("get_bits_a", [](const BitsClass bits)
  {
    return bits.a;
  });

  types.method("get_bits_b", [](const BitsClass bits)
  {
    return bits.get_b();
  });

  types.add_type<AConstRef>("AConstRef").method("value", &AConstRef::value);
  types.add_type<ReturnConstRef>("ReturnConstRef").method("value", &ReturnConstRef::operator());

  types.export_symbols("get_bits_a", "get_bits_b", "make_bits");
  types.export_symbols("BitsClass", "AConstRef", "ReturnConstRef", "value");
JULIA_CPP_MODULE_END
