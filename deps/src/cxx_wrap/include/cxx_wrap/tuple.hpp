#ifndef CXXWRAP_TUPLE_HPP
#define CXXWRAP_TUPLE_HPP

#include <tuple>

#include "type_conversion.hpp"

namespace cxx_wrap
{

namespace detail
{
  template<typename CppT, typename JuliaT>
  struct TupleBox
  {
    jl_value_t* operator()(CppT&& v)
    {
      return box(v);
    }
  };

  template<typename CppT>
  struct TupleBox<CppT, jl_value_t*>
  {
    jl_value_t* operator()(CppT&& v)
    {
      return convert_to_julia(v);
    }
  };

  /// Box primitive types for tuple construction
  template<typename T>
  int tuple_add(jl_value_t* tup, std::size_t i, T&& v)
  {
    jl_value_t* boxed_val = TupleBox<T, mapped_reference_type<T>>()(std::forward<T>(v));
    JL_GC_PUSH1(&boxed_val);
    jl_set_nth_field(tup, i, boxed_val);
    JL_GC_POP();
    return 0;
  }

  // From http://stackoverflow.com/questions/7858817/unpacking-a-tuple-to-call-a-matching-function-pointer
  template<int...>
  struct Sequence
  {
  };

  template<int N, int... S>
  struct GenerateSequence : GenerateSequence<N-1, N-1, S...>
  {
  };

  template<int... S>
  struct GenerateSequence<0, S...>
  {
    typedef Sequence<S...> type;
  };

  template<typename TupleT, int... S>
  jl_value_t* new_jl_tuple(Sequence<S...>, jl_datatype_t* dt, const TupleT& tp)
  {
    jl_value_t* result = nullptr;
    JL_GC_PUSH1(&result);
    result = jl_new_struct_uninit(dt);
    auto dummy = {tuple_add(result, S, std::get<S>(tp))...};
    JL_GC_POP();
    return result;
  }
}

template<typename... TypesT> struct static_type_mapping<std::tuple<TypesT...>>
{
  typedef jl_value_t* type;

  static jl_datatype_t* julia_type()
  {
    static jl_datatype_t* tuple_type = nullptr;
    if(tuple_type == nullptr)
    {
      jl_svec_t* params = nullptr;
      JL_GC_PUSH2(&tuple_type, &params);
      params = jl_svec(sizeof...(TypesT), cxx_wrap::julia_type<TypesT>()...);
      tuple_type = jl_apply_tuple_type(params);
      protect_from_gc(tuple_type);
      JL_GC_POP();
    }
    return tuple_type;
  }
};

template<typename... TypesT>
struct ConvertToJulia<std::tuple<TypesT...>, false, false, false>
{
  jl_value_t* operator()(const std::tuple<TypesT...>& tp)
  {
    return detail::new_jl_tuple(typename detail::GenerateSequence<sizeof...(TypesT)>::type(), julia_type<std::tuple<TypesT...>>(), tp);
  }
};

// Wrap NTuple type
template<typename N, typename T>
struct NTuple
{
};

template<typename N, typename T>
struct static_type_mapping<NTuple<N,T>>
{
  typedef jl_datatype_t* type;
  static jl_datatype_t* julia_type()
  {
    jl_datatype_t* dt = nullptr;
    if(dt == nullptr)
    {
      dt = (jl_datatype_t*)jl_apply_tuple_type(jl_svec1(apply_type((jl_value_t*)jl_vararg_type, jl_svec2(static_type_mapping<T>::julia_type(), static_type_mapping<N>::julia_type()))));
      protect_from_gc(dt);
    }
    return dt;
  }
};

} // namespace cxx_wrap
#endif
