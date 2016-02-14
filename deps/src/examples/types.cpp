#include <string>

#include <cpp_wrapper.hpp>

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

class ImmutableInt64
{
public:
  ImmutableInt64(const int64_t value = 0) : m_value(value)
  {
  }

  int64_t get_value() const
  {
    return m_value;
  }

private:
  int64_t m_value;
};

struct BitsClass
{
  double a;
  int64_t b;

  int64_t get_b() const
  {
    return b;
  }

  void set_b(const int64_t x)
  {
    b = x;
  }

  ~BitsClass() {}

};

} // namespace cpp_types

namespace cpp_wrapper
{
  template<> struct IsImmutable<cpp_types::ImmutableInt64> : std::true_type {};
  template<> struct IsBits<cpp_types::BitsClass> : std::true_type {};
}

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cpp_types;

  cpp_wrapper::Module& types = registry.create_module("CppTypes");

  types.add_type<DoubleData>("DoubleData");

  types.add_type<World>("World")
    .constructor<const std::string&>()
    .method("set", &World::set)
    .method("greet", &World::greet);

  types.add_type<NonCopyable>("NonCopyable");

  // ImmutableInt64
  types.add_immutable<ImmutableInt64>("ImmutableInt64", cpp_wrapper::FieldList<int64_t>("value"))
    .constructor<int64_t>()
    .method("getvalue", &ImmutableInt64::get_value);
  types.method("convert", [](cpp_wrapper::SingletonType<int64_t>, const ImmutableInt64& a) { return a.get_value(); });
  types.method("+", [](const ImmutableInt64& a, const ImmutableInt64& b) { return ImmutableInt64(a.get_value() + b.get_value()); });
  types.method("==", [](const ImmutableInt64& a, const int64_t b) { return a.get_value() == b; } );
  types.method("==", [](const int64_t b, const ImmutableInt64& a) { return a.get_value() == b; } );

  types.add_bits<BitsClass>("BitsClass");
  types.method("make_bits", [](const double a, const int64_t b)
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
JULIA_CPP_MODULE_END
