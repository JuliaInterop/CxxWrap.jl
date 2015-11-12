#ifndef TYPE_CONVERSION_HPP
#define TYPE_CONVERSION_HPP

#include <julia.h>

#include <string>
#include <typeinfo>
#include <typeindex>
#include <type_traits>

namespace cpp_wrapper
{

/// Helper to easily remove a ref to a const
template<typename T> using remove_const_ref = typename std::remove_const<typename std::remove_reference<T>::type>::type;

/// Static mapping base template. Convert fundamental types to the same target type
template<typename SourceT> struct static_type_mapping
{
	static_assert(std::is_empty<SourceT>::value && !std::is_empty<SourceT>::value, "Unimplemented static_type_mapping");
	// Should have:
	// typedef <julia datatype> type;
	// static jl_datatype_t* julia_type() { return <julia type pointer>; }
};

/// Using declaration to avoid having to write typename all the time
template<typename SourceT> using mapped_type = typename static_type_mapping<SourceT>::type;

template<> struct static_type_mapping<void>
{
	typedef void type;
	static jl_datatype_t* julia_type() { return jl_void_type; }
};

template<> struct static_type_mapping<double>
{
	typedef double type;
	static jl_datatype_t* julia_type() { return jl_float64_type; }
};

template<> struct static_type_mapping<int>
{
	typedef int type;
	static jl_datatype_t* julia_type() { return jl_int32_type; }
};

template<> struct static_type_mapping<unsigned int>
{
	typedef unsigned int type;
	static jl_datatype_t* julia_type() { return jl_uint32_type; }
};

/// Specializations
template<> struct static_type_mapping<std::string>
{
	typedef jl_value_t* type;
	static jl_datatype_t* julia_type() { return jl_any_type; }
};

template<> struct static_type_mapping<void*>
{
	typedef jl_value_t* type;
	static jl_datatype_t* julia_type() { return jl_voidpointer_type; }
};

template<> struct static_type_mapping<jl_datatype_t*>
{
	typedef jl_datatype_t* type; // Debatable if this should be jl_value_t*
	static jl_datatype_t* julia_type() { return jl_datatype_type; }
};

/// Auto-conversion to the statically mapped target type.
template<typename T>
inline mapped_type<T> convert_to_julia(const T& cpp_val)
{
	static_assert(std::is_fundamental<T>::value, "Unimplemented convert_to_julia");
	return cpp_val;
}

template<>
inline mapped_type<std::string> convert_to_julia(const std::string& str)
{
	return jl_cstr_to_string(str.c_str());
}

template<>
inline mapped_type<void*> convert_to_julia(void* const& p)
{
	return jl_box_voidpointer(p);
}

template<>
inline mapped_type<jl_datatype_t*> convert_to_julia(jl_datatype_t* const& dt)
{
	return dt;
}

template<typename CppT, typename JuliaT>
inline CppT convert_to_cpp(const JuliaT& julia_val)
{
	static_assert(std::is_fundamental<CppT>::value, "Unimplemented convert_to_cpp");
	return julia_val;
}

template<>
inline std::string convert_to_cpp(jl_value_t* const& julia_string)
{
	return std::string(jl_bytestring_ptr(julia_string));
}

}

#endif
