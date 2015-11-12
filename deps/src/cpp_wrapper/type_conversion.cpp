#include "type_conversion.hpp"
#include <map>
#include <string>
#include <typeindex>
#include "array.hpp"

namespace cpp_wrapper
{

std::map<std::type_index, jl_datatype_t*>& cpp_to_julia_map()
{
	static std::map<std::type_index, jl_datatype_t*> map_instance;

	// Register the built-in mapping at first access
	if(map_instance.empty())
	{
		map_instance[typeid(double)] = jl_float64_type;
		map_instance[typeid(int)] = jl_int32_type; // TODO: Verify if this is always compatible
		map_instance[typeid(unsigned int)] = jl_uint32_type; // TODO: Verify if this is always compatible
		map_instance[typeid(void)] = jl_void_type;
		map_instance[typeid(void*)] = jl_voidpointer_type;
		map_instance[typeid(std::string)] = jl_any_type;
		map_instance[typeid(jl_datatype_t*)] = jl_datatype_type;
		map_instance[typeid(ArrayRef<double>)] = jl_ref_type;//(jl_datatype_t*)jl_apply_array_type(jl_float64_type, 1);
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

}
