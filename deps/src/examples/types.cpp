#include <string>

#include <cpp_wrapper.hpp>

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
  void set_value(double v)
  {
    m_value = v;
  }

  double get_value() const
  {
    return m_value;
  }

  double m_value = 0.;
};

JULIA_CPP_MODULE_BEGIN(registry)
  cpp_wrapper::Module& types = registry.create_module("CppTypes");

  types.add_type<World>("World")
    .constructor<const std::string&>()
    .method("set", &World::set)
    .method("greet", &World::greet);

  types.add_type<NonCopyable>("NonCopyable");

  types.add_type<BoxedDouble>("BoxedDouble")
    .method("set_value", &BoxedDouble::set_value)
    .method("get_value", &BoxedDouble::get_value);
  types.method("convert", [](cpp_wrapper::SingletonType<double>, const BoxedDouble& d) { return d.get_value(); });
JULIA_CPP_MODULE_END
