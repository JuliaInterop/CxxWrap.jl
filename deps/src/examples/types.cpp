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

JULIA_CPP_MODULE_BEGIN(registry)
  cpp_wrapper::Module& types = registry.create_module("CppTypes");
  types.add_type<World>("World")
    .constructor<const std::string&>()
    .def("set", &World::set)
    .def("greet", &World::greet);
JULIA_CPP_MODULE_END
