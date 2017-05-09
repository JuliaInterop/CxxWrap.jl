#include "functions.hpp"

// This header provides helper functions to call Julia functions from C++

namespace cxx_wrap
{

JuliaFunction::JuliaFunction(const std::string& name, const std::string& module_name)
{
  jl_module_t* mod = module_name.empty() ? jl_current_module : (jl_module_t*)jl_get_global(jl_current_module, jl_symbol(module_name.c_str()));
  if(mod == nullptr)
  {
    throw std::runtime_error("Could not find module " + module_name + " when looking up function " + module_name);
  }

  m_function = jl_get_function(mod, name.c_str());
  if(m_function == nullptr)
  {
    throw std::runtime_error("Could not find function " + name);
  }
}

JuliaFunction::JuliaFunction(jl_function_t* fpointer)
{
  if(fpointer == nullptr)
  {
    throw std::runtime_error("Storing a null function pointer in a JuliaFunction is not allowed");
  }
  m_function = fpointer;
}

}
