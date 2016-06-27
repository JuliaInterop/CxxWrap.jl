#include "array.hpp"
#include "cxx_wrap.hpp"

extern "C"
{

using namespace cxx_wrap;

jl_datatype_t* g_any_type = nullptr;

/// Initialize the module
CXX_WRAP_EXPORT void initialize(jl_value_t* julia_module, jl_value_t* cpp_any_type, jl_value_t* cppfunctioninfo_type)
{
  g_cxx_wrap_module = (jl_module_t*)julia_module;
  g_any_type = (jl_datatype_t*)cpp_any_type;
  g_cppfunctioninfo_type = (jl_datatype_t*)cppfunctioninfo_type;
}

CXX_WRAP_EXPORT jl_datatype_t* get_any_type()
{
  return g_any_type;
}

CXX_WRAP_EXPORT jl_module_t* get_cxxwrap_module()
{
  return g_cxx_wrap_module;
}

/// Create a new registry
CXX_WRAP_EXPORT void* create_registry()
{
  return static_cast<void*>(new ModuleRegistry());
}

/// Get the names of all modules in the registry
CXX_WRAP_EXPORT jl_array_t* get_module_names(void* void_registry)
{
  assert(void_registry != nullptr);
  const ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  Array<std::string> names_array;
  JL_GC_PUSH1(names_array.gc_pointer());
  registry.for_each_module([&](Module& module)
  {
    names_array.push_back(module.name());
  });
  JL_GC_POP();
  return names_array.wrapped();
}

/// Bind jl_datatype_t structures to corresponding Julia symbols in the given module
CXX_WRAP_EXPORT void bind_module_types(void* void_registry, jl_value_t* module_any)
{
  assert(void_registry != nullptr);
  ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  jl_module_t* mod = (jl_module_t*)module_any;
  const std::string mod_name = symbol_name(mod->name);
  registry.get_module(mod_name).bind_types(mod);
}

/// Get the functions defined in the modules. Any classes used by these functions must be defined on the Julia side first
CXX_WRAP_EXPORT jl_array_t* get_module_functions(void* void_registry)
{
  assert(void_registry != nullptr);
  const ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  Array<jl_value_t*> module_array((jl_datatype_t*)jl_apply_array_type(g_cppfunctioninfo_type,1));
  JL_GC_PUSH1(module_array.gc_pointer());
  registry.for_each_module([&](Module& module)
  {
    Array<jl_value_t*> function_array(g_cppfunctioninfo_type);
    JL_GC_PUSH1(function_array.gc_pointer());

    module.for_each_function([&](FunctionWrapperBase& f)
    {
      const std::vector<jl_datatype_t*> types_vec = f.argument_types();
      Array<jl_datatype_t*> arg_types_array;
      JL_GC_PUSH1(arg_types_array.gc_pointer());

      for(const auto& t : types_vec)
      {
        arg_types_array.push_back(t);
      }

      function_array.push_back(jl_new_struct(g_cppfunctioninfo_type,
        convert_to_julia(f.name()),
        arg_types_array.wrapped(),
        f.return_type(),
        jl_box_voidpointer(f.pointer()),
        jl_box_voidpointer(f.thunk())
      ));

      JL_GC_POP();
    });

    module_array.push_back((jl_value_t*)function_array.wrapped());

    JL_GC_POP();
  });
  JL_GC_POP();
  return module_array.wrapped();
}

CXX_WRAP_EXPORT jl_array_t* get_exported_symbols(void* void_registry, jl_value_t* mod_name)
{
  assert(void_registry != nullptr);
  ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  Array<std::string> syms;
  for(auto&& sym_name : registry.get_module(convert_to_cpp<std::string>(mod_name)).exported_symbols())
  {
    syms.push_back(sym_name);
  }

  return syms.wrapped();
}

}
