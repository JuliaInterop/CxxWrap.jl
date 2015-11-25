#include <string>

#include <cpp_wrapper.hpp>

struct World
{
  void set(const std::string& msg) { this->msg = msg; }
  std::string greet() { return msg; }
  std::string msg;
};

JULIA_CPP_MODULE_BEGIN(registry)
  cpp_wrapper::Module& types = registry.create_module("CppTypes");
  types.add_type<World>("World")
    .def("set", &World::set)
    .def("greet", &World::greet);
JULIA_CPP_MODULE_END
