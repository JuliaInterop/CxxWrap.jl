#ifndef TYPE_CONVERSION_HPP
#define TYPE_CONVERSION_HPP

#include <julia.h>

#include <string>
#include <typeinfo>
#include <typeindex>
#include <type_traits>

namespace cpp_wrapper
{

/// Register a new mapping
void register_type_mapping(const std::type_info& cpp_type, jl_datatype_t* julia_type);

/// Template version
template<typename T>
void register_type_mapping(jl_datatype_t* julia_type)
{
	register_type_mapping(typeid(T), julia_type);
}

/// Get the Julia datatype corresponding to the given C++ type
jl_datatype_t* type(const std::type_index& cpp_type);

/// Template version
template<typename T>
jl_datatype_t* type()
{
	return type(typeid(T));
}

/// Register a conversion function to convert the given C++ type to a jl_value_t*
void register_conversion_function(const std::type_index& cpp_type, void* fpointer);

/// Get a conversion function for the given C++ type, or null if it doesn't exist
void* conversion_function(const std::type_index& cpp_type);

/// Convert a value from SourceT to TargetT. Specialize for functionality
template<typename TargetT, typename SourceT>
TargetT convert(const SourceT& val);

template<>
inline jl_value_t* convert(void* const& void_ptr)
{
	return jl_box_voidpointer(void_ptr);
}

template<>
inline jl_value_t* convert(const std::string& str)
{
	return jl_cstr_to_string(str.c_str());
}

/// Static mapping base template
template<typename SourceT> struct static_type_mapping { typedef void type; };

/// Using declaration to avoid having to write typename all the time
template<typename SourceT> using mapped_type = typename static_type_mapping<SourceT>::type;

/// Specialzations
template<> struct static_type_mapping<int> { typedef int type; };
template<> struct static_type_mapping<unsigned int> { typedef unsigned int type; };
template<> struct static_type_mapping<double> { typedef double type; };
template<> struct static_type_mapping<std::string> { typedef jl_value_t* type; };

/// Auto-conversion to the statically mapped target type.
template<typename T>
mapped_type<T> auto_convert_to_julia(const T& cpp_val)
{
	static_assert(!std::is_void<mapped_type<T>>::value, "Unimplemented conversion");
	return cpp_val;
}

template<>
mapped_type<std::string> auto_convert_to_julia(const std::string& s)
{

}

}

#endif
