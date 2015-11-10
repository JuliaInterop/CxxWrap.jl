#ifndef ARRAY_HPP
#define ARRAY_HPP

#include <julia.h>

#include "type_conversion.hpp"

namespace cpp_wrapper
{

/// Wrap a Julia 1D array in a C++ class
template<typename ValueT>
class Array
{
public:
	Array(const size_t n = 0)
	{
		JL_GC_PUSH1(&m_array);
		jl_value_t* array_type = jl_apply_array_type(type<ValueT>(), 1);
		m_array = jl_alloc_array_1d(array_type, n);
		JL_GC_POP();
	}

	/// Overload for void pointer
	void push_back(const ValueT& val)
	{
		JL_GC_PUSH1(&m_array);
		const size_t pos = jl_array_len(m_array);
		jl_array_grow_end(m_array, 1);
		jl_arrayset(m_array, (jl_value_t*)(convert_to_julia(val)), pos);
		JL_GC_POP();
	}

	/// Access to the wrapped array
	jl_array_t* wrapped()
	{
		return m_array;
	}

private:
	jl_array_t* m_array;
};

}

#endif
