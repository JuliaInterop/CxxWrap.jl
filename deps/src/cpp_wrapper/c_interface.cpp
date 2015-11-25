#include "array.hpp"
#include "cpp_wrapper.hpp"

extern "C"
{

using namespace cpp_wrapper;

/// Create a new registry
void* create_registry()
{
	return static_cast<void*>(new ModuleRegistry());
}

jl_array_t* get_modules(void* void_registry)
{
  assert(void_registry != nullptr);
	const ModuleRegistry& registry = *reinterpret_cast<ModuleRegistry*>(void_registry);
	Array<void*> array;

	registry.for_each_module([&](Module& mod)
	{
		array.push_back(static_cast<void*>(&mod));
	});

	return array.wrapped();
}

jl_value_t* get_module_name(void* void_module)
{
	assert(void_module != nullptr);
	const Module& module = *reinterpret_cast<Module*>(void_module);
	return convert_to_julia(module.name());
}

jl_array_t* get_functions(void* void_module)
{
	assert(void_module != nullptr);
	const Module& module = *reinterpret_cast<Module*>(void_module);
	Array<void*> array;
	module.for_each_function([&](FunctionWrapperBase& mod)
	{
		array.push_back(static_cast<void*>(&mod));
	});

	return array.wrapped();
}

jl_value_t* get_function_name(void* void_function)
{
  assert(void_function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return convert_to_julia(function.name());
}

void* get_function_pointer(void* void_function)
{
  assert(void_function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return function.pointer();
}

void* get_function_thunk(void* void_function)
{
  assert(void_function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return function.thunk();
}

jl_array_t* get_function_arguments(void* void_function)
{
  assert(void_function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	const std::vector<jl_datatype_t*> types_vec = function.argument_types();
	Array<jl_datatype_t*> julia_array;
	for(const auto& t : types_vec)
	{
		julia_array.push_back(t);
	}

	return julia_array.wrapped();
}

jl_datatype_t* get_function_return_type(void* void_function)
{
  assert(void_function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return function.return_type();
}

void create_types(jl_value_t* julia_module, void* void_module)
{
	assert(jl_is_module(julia_module));
	assert(void_module != nullptr);
	const Module& cpp_module = *reinterpret_cast<Module*>(void_module);
	cpp_module.bind_julia_types((jl_module_t*)julia_module);
}


}
