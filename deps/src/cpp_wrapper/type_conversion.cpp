#include "type_conversion.hpp"
#include <map>
#include <string>
#include <typeindex>

namespace cpp_wrapper
{

std::map<std::type_index, jl_datatype_t*>& cpp_to_julia_map()
{
	static std::map<std::type_index, jl_datatype_t*> map_instance;

	// Register the built-in mapping at first access
	if(map_instance.empty())
	{
		map_instance[typeid(double)] = jl_float64_type;
		map_instance[typeid(int)] = jl_int64_type;
		map_instance[typeid(unsigned int)] = jl_uint64_type;
		map_instance[typeid(void)] = jl_void_type;
		map_instance[typeid(void*)] = jl_voidpointer_type;
		map_instance[typeid(std::string)] = jl_ascii_string_type;
	}

	return map_instance;
}

std::map<std::type_index, void*> conversion_functions()
{
	static std::map<std::type_index, void*> map_instance;

	// Register default conversions
	if(map_instance.empty())
	{
		map_instance[typeid(std::string)] = reinterpret_cast<void*>(&convert<jl_value_t*, std::string>);
	}

	return map_instance;
}

void register_type_mapping(const std::type_info &cpp_type, jl_datatype_t *julia_type)
{
	const std::type_index idx(cpp_type);
	if(cpp_to_julia_map().count(idx) != 0)
		throw std::runtime_error("Type " + std::string(cpp_type.name()) + " was already registered");

	cpp_to_julia_map()[idx] = julia_type;
}

jl_datatype_t* type(const std::type_index& cpp_type)
{
	if(cpp_to_julia_map().count(cpp_type) == 0)
		throw std::runtime_error("Type was not registered");

	return cpp_to_julia_map()[cpp_type];
}

void register_conversion_function(const std::type_index& cpp_type, void* fpointer)
{
	if(conversion_functions().count(cpp_type) != 0)
		throw std::runtime_error("Conversion was already registered");

	conversion_functions()[cpp_type] = fpointer;
}

void* conversion_function(const std::type_index& cpp_type)
{
	if(conversion_functions().count(cpp_type) == 0)
		return nullptr;

	return conversion_functions()[cpp_type];
}

}
