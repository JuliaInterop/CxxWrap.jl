#include <cxx_wrap.hpp>
#include <containers/tuple.hpp>

JULIA_CPP_MODULE_BEGIN(registry)
  cxx_wrap::Module& containers = registry.create_module("Containers");

  containers.method("test_tuple", []() { return std::make_tuple(1, 2., 3.f); });

  containers.export_symbols("test_tuple");
JULIA_CPP_MODULE_END
