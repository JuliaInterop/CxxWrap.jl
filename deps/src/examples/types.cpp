#include <string>

#include <cpp_wrapper.hpp>

namespace cpp_types
{

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

class BitsInt64
{
public:
  BitsInt64(const int64_t value = 0) : m_value(value)
  {
  }

  int64_t get_value() const
  {
    return m_value;
  }

private:
  int64_t m_value;
};

} // namespace cpp_types

namespace cpp_wrapper { template<> struct IsBits<cpp_types::BitsInt64> : std::true_type {}; }

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cpp_types;

  cpp_wrapper::Module& types = registry.create_module("CppTypes");

  types.add_type<World>("World")
    .constructor<const std::string&>()
    .method("set", &World::set)
    .method("greet", &World::greet);

  types.add_type<NonCopyable>("NonCopyable");

  // BitsInt64
  types.add_bits<BitsInt64>("BitsInt64", cpp_wrapper::FieldList<int64_t>("value"))
    .constructor<int64_t>()
    .method("getvalue", &BitsInt64::get_value);
  types.method("convert", [](cpp_wrapper::SingletonType<int64_t>, const BitsInt64& a) { return a.get_value(); });
  types.method("+", [](const BitsInt64& a, const BitsInt64& b) { return BitsInt64(a.get_value() + b.get_value()); });
  types.method("==", [](const BitsInt64& a, const int64_t b) { return a.get_value() == b; } );
  types.method("==", [](const int64_t b, const BitsInt64& a) { return a.get_value() == b; } );
JULIA_CPP_MODULE_END
