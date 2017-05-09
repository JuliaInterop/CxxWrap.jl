#include "array.hpp"
#include "cxx_wrap.hpp"
#include "functions.hpp"
#include "cxx_wrap_config.hpp"

#include <julia.h>
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR > 4
#include <julia_threads.h>
#endif

namespace cxx_wrap
{

jl_module_t* g_cxx_wrap_module;
jl_datatype_t* g_cppfunctioninfo_type;

CXXWRAP_API jl_array_t* gc_protected()
{
  static jl_array_t* m_arr = nullptr;
  if (m_arr == nullptr)
  {
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR > 4
    jl_value_t* array_type = apply_array_type(jl_any_type, 1);
    m_arr = jl_alloc_array_1d(array_type, 0);
#else
    m_arr = jl_alloc_cell_1d(0);
#endif
    jl_set_const(g_cxx_wrap_module, jl_symbol("_gc_protected"), (jl_value_t*)m_arr);
  }
  return m_arr;
}

CXXWRAP_API std::stack<std::size_t>& gc_free_stack()
{
  static std::stack<std::size_t> m_stack;
  return m_stack;
}

CXXWRAP_API std::map<jl_value_t*, std::pair<std::size_t,std::size_t>>& gc_index_map()
{
  static std::map<jl_value_t*, std::pair<std::size_t,std::size_t>> m_map;
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

CXXWRAP_API jl_datatype_t* julia_type(const std::string& name, const std::string& module_name)
{
  for(jl_module_t* mod : {jl_base_module, g_cxx_wrap_module, jl_current_module, jl_current_module->parent, module_name.empty() ? nullptr : (jl_module_t*)jl_get_global(jl_current_module, jl_symbol(module_name.c_str()))})
  {
    if(mod == nullptr)
    {
      continue;
    }

    jl_value_t* gval = jl_get_global(mod, jl_symbol(name.c_str()));
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 6
    if(gval != nullptr && jl_is_datatype(gval))
#else
    if(gval != nullptr && (jl_is_datatype(gval) || jl_is_unionall(gval)))
#endif
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

CXXWRAP_API jl_value_t* apply_type(jl_value_t* tc, jl_svec_t* params)
{
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 6
  return jl_apply_type(tc, params);
#else
  return jl_apply_type(jl_is_unionall(tc) ? tc : ((jl_datatype_t*)tc)->name->wrapper, jl_svec_data(params), jl_svec_len(params));
#endif
}

jl_value_t* ConvertToJulia<std::wstring, false, false, false>::operator()(const std::wstring& str) const
{
  static const JuliaFunction wstring_to_julia("wstring_to_julia", "CxxWrap");
  return wstring_to_julia(str.c_str(), static_cast<int_t>(str.size()));
}

std::wstring ConvertToCpp<std::wstring, false, false, false>::operator()(jl_value_t* jstr) const
{
  static const JuliaFunction wstring_to_cpp("wstring_to_cpp", "CxxWrap");
  ArrayRef<wchar_t> arr((jl_array_t*)wstring_to_cpp(jstr));
  return std::wstring(arr.data(), arr.size());
}

}
