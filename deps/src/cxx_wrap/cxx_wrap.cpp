#include "cxx_wrap.hpp"

#include <julia.h>
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR > 4
#include <julia_threads.h>
#endif

namespace cxx_wrap
{

jl_module_t* g_cxx_wrap_module;
jl_datatype_t* g_cppfunctioninfo_type;

CXX_WRAP_EXPORT jl_array_t* gc_protected()
{
  static jl_array_t* m_arr = nullptr;
  if (m_arr == nullptr)
  {
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR > 4
    jl_value_t* array_type = jl_apply_array_type(jl_any_type, 1);
    m_arr = jl_alloc_array_1d(array_type, 0);
#else
    m_arr = jl_alloc_cell_1d(0);
#endif
    jl_set_const(g_cxx_wrap_module, jl_symbol("_gc_protected"), (jl_value_t*)m_arr);
  }
  return m_arr;
}

Module::Module(const std::string& name) : m_name(name)
{
}

Module& ModuleRegistry::create_module(const std::string &name)
{
  if(m_modules.count(name))
    throw std::runtime_error("Error registering module: " + name + " was already registered");

  Module* mod = new Module(name);
  m_modules[name].reset(mod);
  return *mod;
}

CXX_WRAP_EXPORT jl_datatype_t* julia_type(const std::string& name)
{
  for(jl_module_t* mod : {jl_base_module, g_cxx_wrap_module, jl_current_module})
  {
    jl_value_t* gval = jl_get_global(mod, jl_symbol(name.c_str()));
    if(gval != nullptr && jl_is_datatype(gval))
    {
      return (jl_datatype_t*)gval;
    }
  }
  throw std::runtime_error("Symbol for type " + name + " was not found");
}

} // End namespace Julia
