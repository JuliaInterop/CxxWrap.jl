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

class BoxedDouble
{
public:
  BoxedDouble(const double value = 0.) : m_value(value)
  {
  }

  const double get_value() const
  {
    return m_value;
  }

  void print() const
  {
    std::cout << "boxed double has value " << m_value << std::endl;
  }

  ~BoxedDouble()
  {
    std::cout << "Deleting BoxedDouble with value " << m_value << std::endl;
  }

private:
  const double m_value;
};

} // namespace cpp_types

namespace cpp_wrapper { template<> struct IsBits<cpp_types::BoxedDouble> : std::true_type {}; }

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cpp_types;

  cpp_wrapper::Module& types = registry.create_module("CppTypes");

  types.add_type<World>("World")
    .constructor<const std::string&>()
    .method("set", &World::set)
    .method("greet", &World::greet);

  types.add_type<NonCopyable>("NonCopyable");

  types.add_bits<BoxedDouble>("BoxedDouble")
    .constructor<const double>()
    .method("print", &BoxedDouble::print);
  types.method("convert", [](cpp_wrapper::SingletonType<double>, const BoxedDouble& d) { return d.get_value(); });
  // types.method("+", [](const BoxedDouble& a, const BoxedDouble& b)
  // {
  //   return BoxedDouble(a.get_value() + b.get_value());
  // });
  // types.method("==", [](const BoxedDouble& a, const double b) { return a.get_value() == b; });
  // types.method("==", [](const double b, const BoxedDouble& a) { return a.get_value() == b; });
JULIA_CPP_MODULE_END
