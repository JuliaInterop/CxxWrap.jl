#include "cpp_wrapper.hpp"
#include <iostream>

#include <julia.h>

namespace cpp_wrapper
{

module::module(const std::string& name) : m_name(name)
{
}

void* module::get_function(const std::string& name)
{
	return m_functions[name]->function_pointer();
}

void* module::get_data(const std::string& name)
{
	return m_functions[name]->data_pointer();
}

typedef std::map<std::string, std::unique_ptr<module>> modules_t;
modules_t& modules()
{
	static modules_t modules_map;
	return modules_map;
}

module& register_module(const std::string &name)
{
	if(modules().count(name))
		throw std::runtime_error("Error registering module: module " + name + " was already registerd");

	modules()[name].reset(new module(name));
	return *modules()[name];
}

} // End namespace Julia

void* get_function(const char* module_name, const char* function_name)
{
	return cpp_wrapper::modules()[module_name]->get_function(function_name);
}

void* get_data(const char* module_name, const char* function_name)
{
	return cpp_wrapper::modules()[module_name]->get_data(function_name);
}

