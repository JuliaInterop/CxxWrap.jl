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
