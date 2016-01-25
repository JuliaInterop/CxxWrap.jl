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

JULIA_CPP_MODULE_BEGIN(registry)
  cpp_wrapper::Module& types = registry.create_module("CppTypes");
  types.add_type<World>("World", [](auto& wrapped)
  {
    wrapped.template constructor<const std::string&>();
    wrapped.def("set", &World::set);
    wrapped.def("greet", &World::greet);
  });
  types.add_type<NonCopyable>("NonCopyable", [](auto&) {});
JULIA_CPP_MODULE_END
