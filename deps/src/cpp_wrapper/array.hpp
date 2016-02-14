#ifndef ARRAY_HPP
#define ARRAY_HPP

#include <julia.h>

#include "type_conversion.hpp"

namespace cpp_wrapper
{

template<typename PointedT, typename CppT>
class array_iterator_base
{
  // TODO
  static_assert(std::is_same<CppT, PointedT>::value, "Iterator not implemented if Array C++ and Julia types differ");
};

template<typename PointedT>
class array_iterator_base<PointedT, PointedT> : public std::iterator<std::random_access_iterator_tag, PointedT>
{
public:
  array_iterator_base() : m_ptr(nullptr)
  {
  }

	explicit array_iterator_base(PointedT* p) : m_ptr(p)
	{
	}

  template <class OtherPointedT>
	array_iterator_base(array_iterator_base<OtherPointedT, OtherPointedT> const& other) : m_ptr(other.m_ptr) {}

  PointedT& operator*()
  {
		return *m_ptr;
  }

  array_iterator_base<PointedT, PointedT>& operator++()
  {
    ++m_ptr;
    return *this;
  }

  array_iterator_base<PointedT, PointedT>& operator--()
  {
    --m_ptr;
    return *this;
  }

  array_iterator_base<PointedT, PointedT>& operator+=(std::ptrdiff_t n)
  {
    m_ptr += n;
    return *this;
  }

  array_iterator_base<PointedT, PointedT>& operator-=(std::ptrdiff_t n)
  {
    m_ptr -= n;
    return *this;
  }

  const PointedT* ptr() const
  {
    return m_ptr;
  }

private:
  PointedT* m_ptr;
};

/// Wrap a Julia 1D array in a C++ class. Array is allocated on the C++ side
template<typename ValueT>
class Array
{
public:
	Array(const size_t n = 0)
	{
		jl_value_t* array_type = jl_apply_array_type(static_type_mapping<ValueT>::julia_type(), 1);
		m_array = jl_alloc_array_1d(array_type, n);
	}

  Array(jl_datatype_t* applied_type, const size_t n = 0)
	{
		jl_value_t* array_type = jl_apply_array_type(applied_type, 1);
		m_array = jl_alloc_array_1d(array_type, n);
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

  // access to the pointer for GC macros
  jl_array_t** gc_pointer()
  {
    return &m_array;
  }

private:
	jl_array_t* m_array;
};

/// Reference a Julia array in an STL-compatible wrapper
template<typename ValueT, int Dim = 1>
class ArrayRef
{
public:
  ArrayRef(jl_array_t* arr) : m_array(arr)
	{
    assert(m_array != nullptr);
	}

  /// Convert from existing C-array
  ArrayRef(ValueT* ptr, const int rows, const int cols);

  jl_array_t* wrapped()
	{
		return m_array;
	}

	typedef mapped_julia_type<ValueT> julia_t;

	typedef array_iterator_base<julia_t, ValueT> iterator;
  typedef array_iterator_base<julia_t const, ValueT const> const_iterator;

	iterator begin()
	{
    return iterator(static_cast<julia_t*>(jl_array_data(m_array)));
	}

	const_iterator begin() const
	{
    return const_iterator(static_cast<julia_t*>(jl_array_data(m_array)));
	}

	iterator end()
	{
    return iterator(static_cast<julia_t*>(jl_array_data(m_array)) + jl_array_len(m_array));
	}

	const_iterator end() const
	{
    return const_iterator(static_cast<julia_t*>(jl_array_data(m_array)) + jl_array_len(m_array));
	}

  const ValueT* data() const
  {
    return (ValueT*)jl_array_data(m_array);
  }

private:
  jl_array_t* m_array;
};

// Conversions
template<typename T, int Dim> struct static_type_mapping<ArrayRef<T, Dim>>
{
  typedef jl_array_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)jl_apply_array_type(static_type_mapping<T>::julia_type(), Dim); }
  template<typename T2> using remove_const_ref = cpp_wrapper::remove_const_ref<T2>;
};

template<typename ValueT, int Dim> ArrayRef<ValueT, Dim>::ArrayRef(ValueT* c_ptr, const int rows, const int cols)
{
  jl_datatype_t* dt = static_type_mapping<ArrayRef<ValueT, Dim>>::julia_type();
  jl_value_t *dims = jl_new_struct((jl_datatype_t*)jl_tupletype_fill(Dim, (jl_value_t*)jl_long_type), jl_box_long(rows), jl_box_long(cols));
  m_array = jl_ptr_to_array((jl_value_t*)dt, c_ptr, dims, 0);
}

template<typename T, int Dim>
inline mapped_julia_type<ArrayRef<T,Dim>> convert_to_julia(ArrayRef<T,Dim>&& arr)
{
	return arr.wrapped();
}

template<typename ArrRefT>
inline ArrRefT convert_to_cpp(jl_array_t* const& arr)
{
	return ArrRefT(arr);
}

// Iterator operator implementation
template<typename L, typename R>
bool operator!=(const array_iterator_base<L,L>& l, const array_iterator_base<R,R>& r)
{
  return r.ptr() != l.ptr();
}

template<typename L, typename R>
bool operator==(const array_iterator_base<L,L>& l, const array_iterator_base<R,R>& r)
{
  return r.ptr() == l.ptr();
}

template<typename L, typename R>
bool operator<=(const array_iterator_base<L,L>& l, const array_iterator_base<R,R>& r)
{
  return r.ptr() <= l.ptr();
}

template<typename L, typename R>
bool operator>=(const array_iterator_base<L,L>& l, const array_iterator_base<R,R>& r)
{
  return r.ptr() >= l.ptr();
}

template<typename L, typename R>
bool operator>(const array_iterator_base<L,L>& l, const array_iterator_base<R,R>& r)
{
  return r.ptr() > l.ptr();
}

template<typename L, typename R>
bool operator<(const array_iterator_base<L,L>& l, const array_iterator_base<R,R>& r)
{
  return r.ptr() < l.ptr();
}

template<typename T>
bool operator+(const array_iterator_base<T,T>& l, const std::ptrdiff_t n)
{
  return l.ptr() + n;
}

template<typename T>
bool operator+(const std::ptrdiff_t n, const array_iterator_base<T,T>& r)
{
  return r.ptr() + n;
}

template<typename T>
bool operator-(const array_iterator_base<T,T>& l, const std::ptrdiff_t n)
{
  return l.ptr() - n;
}

/// Julia Matrix parametric type
struct JuliaMatrix {};

template<> struct static_type_mapping<JuliaMatrix>
{
  typedef jl_datatype_t* type;
	static jl_datatype_t* julia_type()
  {
    static jl_tvar_t* this_tvar = jl_new_typevar(jl_symbol("T"), (jl_value_t*)jl_bottom_type, (jl_value_t*)jl_any_type);
    return (jl_datatype_t*)jl_apply_type((jl_value_t*)jl_type_type,
                                              jl_svec1(jl_apply_type((jl_value_t*)jl_array_type, jl_svec2(this_tvar, jl_box_long(2)))));
  }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

}

#endif
