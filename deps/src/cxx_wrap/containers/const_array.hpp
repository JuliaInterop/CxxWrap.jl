#ifndef CONST_ARRAY_HPP
#define CONST_ARRAY_HPP

#include "../cxx_wrap.hpp"

#include "tuple.hpp"

namespace cxx_wrap
{

namespace detail
{
  // Helper to make a C++ tuple of longs based on the number of elements
  template<long N, typename... TypesT>
  struct LongNTuple
  {
    typedef typename LongNTuple<N-1, long, TypesT...>::type type;
  };

  template<typename... TypesT>
  struct LongNTuple<0, TypesT...>
  {
    typedef std::tuple<TypesT...> type;
  };
}

/// Wrap a const pointer
template<typename T>
struct ConstPtr
{
  const T* ptr;
};

template<typename T> struct IsBits<ConstPtr<T>> : std::true_type {};

template<typename T>
struct InstantiateParametricType<ConstPtr<T>>
{
  int operator()(Module& m) const
  {
    // Register the Julia type if not already instantiated
    if(!static_type_mapping<ConstPtr<T>>::has_julia_type())
    {
      jl_datatype_t* dt = (jl_datatype_t*)jl_apply_type((jl_value_t*)julia_type("ConstPtr"), jl_svec1(static_type_mapping<T>::julia_type()));
      set_julia_type<ConstPtr<T>>(dt);
      protect_from_gc(dt);
    }
    return 0;
  }
};

/// Wrap a pointer, providing the Julia array interface for it
/// The parameter N represents the number of dimensions
template<typename T, long N>
class ConstArray
{
public:
  typedef typename detail::LongNTuple<N>::type size_t;

  template<typename... SizesT>
  ConstArray(const T* ptr, const SizesT... sizes) :
    m_arr(ptr),
    m_sizes(sizes...)
  {
  }

  T getindex(const int i) const
  {
    return m_arr[i-1];
  }

  size_t size() const
  {
    return m_sizes;
  }

  const T* ptr() const
  {
    return m_arr;
  }

private:
  const T* m_arr;
  const size_t m_sizes;
};

template<typename T, typename... SizesT>
ConstArray<T, sizeof...(SizesT)> make_const_array(const T* p, const SizesT... sizes)
{
  return ConstArray<T, sizeof...(SizesT)>(p, sizes...);
}

template<typename T, long N> struct IsImmutable<ConstArray<T,N>> : std::true_type {};

template<typename T, long N>
struct ConvertToJulia<ConstArray<T,N>, false, true, false>
{
  jl_value_t* operator()(const ConstArray<T,N>& arr)
  {
    jl_value_t* result = nullptr;
    jl_value_t* ptr = nullptr;
    jl_value_t* size = nullptr;
    JL_GC_PUSH3(&result, &ptr, &size);
    ptr = convert_to_julia(ConstPtr<T>({arr.ptr()}));
    size = convert_to_julia(arr.size());
    result = jl_new_struct(julia_type<ConstArray<T,N>>(), ptr, size);
    JL_GC_POP();
    return result;
  }
};

template<typename T, long N>
struct InstantiateParametricType<ConstArray<T,N>>
{
  int operator()(Module& m) const
  {
    // Register the Julia type if not already instantiated
    if(!static_type_mapping<ConstArray<T,N>>::has_julia_type())
    {
      jl_datatype_t* pdt = julia_type("ConstArray");
      jl_value_t* boxed_n = box(N);
      JL_GC_PUSH1(&boxed_n);
      jl_datatype_t* app_dt = (jl_datatype_t*)jl_apply_type((jl_value_t*)pdt, jl_svec2(julia_type<T>(), boxed_n));
      protect_from_gc(app_dt);
      set_julia_type<ConstArray<T,N>>(app_dt);
      TypeWrapper<ConstArray<T,N>> wrapped(m, app_dt);
      wrapped.method("getindex", &ConstArray<T,N>::getindex);
      JL_GC_POP();
    }
    return 0;
  }
};

} // namespace cxx_wrap
#endif
