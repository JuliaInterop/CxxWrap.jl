#include <string>

#include <cxx_wrap.hpp>

namespace extended
{

struct ExtendedWorld
{
  ExtendedWorld(const std::string& message = "default hello") : msg(message){}
  std::string greet() { return msg; }
  std::string msg;
};

} // namespace extended

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace extended;

  cxx_wrap::Module& types = registry.create_module("ExtendedTypes");

  types.add_type<ExtendedWorld>("ExtendedWorld")
    .method("greet", &ExtendedWorld::greet);

JULIA_CPP_MODULE_END
