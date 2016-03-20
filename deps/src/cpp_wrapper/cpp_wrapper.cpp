#include "cpp_wrapper.hpp"

#include <julia.h>

namespace cpp_wrapper
{

jl_module_t* g_cpp_wrapper_module;
jl_datatype_t* g_cppfunctioninfo_type;

CPP_WRAPPER_EXPORT jl_array_t* gc_protected()
{
	static jl_array_t* m_arr = nullptr;
	if (m_arr == nullptr)
	{
		m_arr = jl_alloc_cell_1d(0);
		jl_set_const(g_cpp_wrapper_module, jl_symbol("_gc_protected"), (jl_value_t*)m_arr);
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

} // End namespace Julia
