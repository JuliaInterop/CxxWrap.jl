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

CXX_WRAP_EXPORT std::stack<std::size_t>& gc_free_stack()
{
  static std::stack<std::size_t> m_stack;
  return m_stack;
}

CXX_WRAP_EXPORT std::map<jl_value_t*, std::size_t>& gc_index_map()
{
  static std::map<jl_value_t*, std::size_t> m_map;
  return m_map;
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

CXX_WRAP_EXPORT jl_datatype_t* julia_type(const std::string& name, const std::string& module_name)
{
  for(jl_module_t* mod : {jl_base_module, g_cxx_wrap_module, jl_current_module, module_name.empty() ? nullptr : (jl_module_t*)jl_get_global(jl_current_module, jl_symbol(module_name.c_str()))})
  {
    if(mod == nullptr)
    {
      continue;
    }

    jl_value_t* gval = jl_get_global(mod, jl_symbol(name.c_str()));
    if(gval != nullptr && jl_is_datatype(gval))
    {
      return (jl_datatype_t*)gval;
    }
  }
  throw std::runtime_error("Symbol for type " + name + " was not found");
}

InitHooks& InitHooks::instance()
{
  static InitHooks hooks;
  return hooks;
}

InitHooks::InitHooks()
{
}

void InitHooks::add_hook(const hook_t hook)
{
  m_hooks.push_back(hook);
}

void InitHooks::run_hooks()
{
  for(const hook_t& h : m_hooks)
  {
    h();
  }
}

} // End namespace Julia
