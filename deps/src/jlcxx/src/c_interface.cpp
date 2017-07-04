#include "jlcxx/array.hpp"
#include "jlcxx/jlcxx.hpp"
#include "jlcxx/jlcxx_config.hpp"

extern "C"
{

using namespace jlcxx;

jl_datatype_t* g_any_type = nullptr;

/// Initialize the module
JLCXX_API void initialize(jl_value_t* julia_module, jl_value_t* cpp_any_type, jl_value_t* cppfunctioninfo_type)
{
  g_cxxwrap_module = (jl_module_t*)julia_module;
  g_any_type = (jl_datatype_t*)cpp_any_type;
  g_cppfunctioninfo_type = (jl_datatype_t*)cppfunctioninfo_type;

  InitHooks::instance().run_hooks();
}

JLCXX_API jl_datatype_t* get_any_type()
{
  return g_any_type;
}

JLCXX_API jl_module_t* get_cxxwrap_module()
{
  return g_cxxwrap_module;
}

/// Create a new registry
JLCXX_API void* create_registry(jl_value_t* parent_module, jl_value_t* wrapped_module)
{
  jl_module_t* mod = jl_is_nothing(wrapped_module) ? nullptr : (jl_module_t*)wrapped_module;
  return static_cast<void*>(new ModuleRegistry((jl_module_t*)parent_module, mod));
}

/// Get the names of all modules in the registry
JLCXX_API jl_array_t* get_modules(void* void_registry)
{
  assert(void_registry != nullptr);
  const ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  Array<jl_value_t*> modules_array;
  JL_GC_PUSH1(modules_array.gc_pointer());
  registry.for_each_module([&](Module& module)
  {
    modules_array.push_back((jl_value_t*)module.julia_module());
  });
  JL_GC_POP();
  return modules_array.wrapped();
}

/// Bind jl_datatype_t structures to corresponding Julia symbols in the given module
JLCXX_API void bind_module_constants(void* void_registry, jl_value_t* module_any)
{
  assert(void_registry != nullptr);
  ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  jl_module_t* mod = (jl_module_t*)module_any;
  const std::string mod_name = symbol_name(mod->name);
  registry.get_module(mod_name).bind_constants(mod);
}

void fill_types_vec(Array<jl_datatype_t*>& types_array, const std::vector<jl_datatype_t*>& types_vec)
{
  for(const auto& t : types_vec)
  {
    types_array.push_back(t);
  }
}

/// Get the functions defined in the modules. Any classes used by these functions must be defined on the Julia side first
JLCXX_API jl_array_t* get_module_functions(void* void_registry)
{
  assert(void_registry != nullptr);
  const ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  Array<jl_value_t*> module_array((jl_datatype_t*)apply_array_type(g_cppfunctioninfo_type,1));
  JL_GC_PUSH1(module_array.gc_pointer());
  registry.for_each_module([&](Module& module)
  {
    Array<jl_value_t*> function_array(g_cppfunctioninfo_type);
    JL_GC_PUSH1(function_array.gc_pointer());

    module.for_each_function([&](FunctionWrapperBase& f)
    {
      Array<jl_datatype_t*> arg_types_array, ref_arg_types_array;
      jl_value_t* boxed_f = nullptr;
      jl_value_t* boxed_thunk = nullptr;
      JL_GC_PUSH4(arg_types_array.gc_pointer(), ref_arg_types_array.gc_pointer(), &boxed_f, &boxed_thunk);

      fill_types_vec(arg_types_array, f.argument_types());
      fill_types_vec(ref_arg_types_array, f.reference_argument_types());

      boxed_f = jl_box_voidpointer(f.pointer());
      boxed_thunk = jl_box_voidpointer(f.thunk());

      function_array.push_back(jl_new_struct(g_cppfunctioninfo_type,
        f.name(),
        arg_types_array.wrapped(),
        ref_arg_types_array.wrapped(),
        f.return_type(),
        boxed_f,
        boxed_thunk
      ));

      JL_GC_POP();
    });

    module_array.push_back((jl_value_t*)function_array.wrapped());

    JL_GC_POP();
  });
  JL_GC_POP();
  return module_array.wrapped();
}

JLCXX_API jl_array_t* get_exported_symbols(void* void_registry, jl_value_t* mod_name)
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

jl_array_t* convert_type_vector(const std::vector<jl_datatype_t*> types_vec)
{
  Array<jl_datatype_t*> datatypes;
  JL_GC_PUSH1(datatypes.gc_pointer());
  for(jl_datatype_t* dt : types_vec)
  {
    datatypes.push_back(dt);
  }
  JL_GC_POP();
  return datatypes.wrapped();
}

JLCXX_API jl_array_t* get_reference_types(void* void_registry, jl_value_t* mod_name)
{
  assert(void_registry != nullptr);
  ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  return convert_type_vector(registry.get_module(convert_to_cpp<std::string>(mod_name)).reference_types());
}

JLCXX_API jl_array_t* get_allocated_types(void* void_registry, jl_value_t* mod_name)
{
  assert(void_registry != nullptr);
  ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
  return convert_type_vector(registry.get_module(convert_to_cpp<std::string>(mod_name)).allocated_types());
}

}
