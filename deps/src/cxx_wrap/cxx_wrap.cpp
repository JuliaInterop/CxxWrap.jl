#include "cxx_wrap.hpp"

#include <julia.h>

namespace cxx_wrap
{

jl_module_t* g_cxx_wrap_module;
jl_datatype_t* g_cppfunctioninfo_type;

CXX_WRAP_EXPORT jl_array_t* gc_protected()
{
	static jl_array_t* m_arr = nullptr;
	if (m_arr == nullptr)
	{
		m_arr = jl_alloc_cell_1d(0);
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

jl_datatype_t* julia_type(const std::string& name)
{
	jl_value_t* gval = jl_get_global(jl_base_module, jl_symbol(name.c_str()));
	if(gval == nullptr)
	{
		throw std::runtime_error("Symbol " + name + " was not found");
	}
	if(!jl_is_datatype(gval))
	{
		throw std::runtime_error("Symbol " + name + " is not a type");
	}
	return (jl_datatype_t*)gval;
}

} // End namespace Julia
