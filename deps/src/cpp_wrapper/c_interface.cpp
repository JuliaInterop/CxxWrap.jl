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
	assert(registry != nullptr);
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
	assert(function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return convert_to_julia(function.name());
}

void* get_function_pointer(void* void_function)
{
	assert(function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return function.pointer();
}

void* get_function_thunk(void* void_function)
{
	assert(function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return function.thunk();
}

jl_array_t* get_function_arguments(void* void_function)
{
	assert(function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	const std::vector<std::type_index> types_vec = function.argument_types();
	Array<jl_datatype_t*> julia_array;
	for(const auto& t_idx : types_vec)
	{
		julia_array.push_back(type(t_idx));
	}

	return julia_array.wrapped();
}

jl_datatype_t* get_function_return_type(void* void_function)
{
	assert(function != nullptr);
	FunctionWrapperBase& function = *reinterpret_cast<FunctionWrapperBase*>(void_function);
	return type(function.return_type());
}

}
