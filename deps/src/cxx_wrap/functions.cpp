#include "functions.hpp"

// This header provides helper functions to call Julia functions from C++

namespace cxx_wrap
{

CXX_WRAP_EXPORT jl_function_t* julia_function(const std::string& name, const std::string& module_name)
{
  jl_module_t* mod = module_name.empty() ? jl_current_module : (jl_module_t*)jl_get_global(jl_current_module, jl_symbol(module_name.c_str()));
  if(mod == nullptr)
  {
    throw std::runtime_error("Could not find module " + module_name + " when looking up function " + module_name);
  }

  jl_function_t* f = jl_get_function(mod, name.c_str());
  if(f == nullptr)
  {
    throw std::runtime_error("Could not find function " + name);
  }

  return f;
}

}
