#include "cpp_wrapper.hpp"

#include <julia.h>

namespace cpp_wrapper
{

jl_module_t* g_cpp_wrapper_module;
jl_datatype_t* g_cppclassinfo_type;
jl_datatype_t* g_cppfunctioninfo_type;

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
