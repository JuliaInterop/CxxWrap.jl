#ifndef ARRAY_HPP
#define ARRAY_HPP

#include <julia.h>

#include "type_conversion.hpp"

namespace cpp_wrapper
{

/// Wrap a Julia 1D array in a C++ class. Array is allocated on the C++ side
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

/// Reference a Julia array in an STL-compatible wrapper
template<typename ValueT>
class ArrayRef
{
public:
	ArrayRef(jl_array_t** arr) : m_array(arr)
	{
		assert(m_array != nullptr);
		assert(*m_array != nullptr);
	}

	jl_array_t** wrapped()
	{
		return m_array;
	}

	typedef mapped_type<ValueT> julia_t;

	template<typename PointedT>
	class iterator_base : public std::iterator<std::random_access_iterator_tag, PointedT>
	{
	public:
		explicit iterator_base(PointedT* p)
			: m_ptr(p) {}

		template <class OtherPointedT>
		iterator_base(iterator_base<OtherPointedT> const& other)
			: m_ptr(other.m_node) {}

	private:
		PointedT* m_ptr;
	};

	typedef iterator_base<julia_t> iterator;
	typedef iterator_base<julia_t const> const_iterator;

	iterator begin()
	{
		return iterator(static_cast<julia_t*>(jl_array_data(*m_array)));
	}

	const_iterator begin() const
	{
		return const_iterator(static_cast<julia_t*>(jl_array_data(*m_array)));
	}

	iterator end()
	{
		return iterator(static_cast<julia_t*>(jl_array_data(*m_array)) + jl_array_len(*m_array));
	}

	const_iterator end() const
	{
		return const_iterator(static_cast<julia_t*>(jl_array_data(*m_array)) + jl_array_len(*m_array));
	}

private:
	jl_array_t** m_array;
};

// Conversions
template<typename T> struct static_type_mapping<ArrayRef<T>> { typedef jl_array_t** type; };

template<typename T>
inline mapped_type<std::string> convert_to_julia(const ArrayRef<T>& arr)
{
	return arr.wrapped();
}

template<typename ArrRefT>
inline ArrRefT convert_to_cpp(jl_array_t** const& arr)
{
	return ArrRefT(arr);
}

}

#endif
