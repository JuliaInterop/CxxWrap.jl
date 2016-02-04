#include <string>

#include <cpp_wrapper.hpp>

namespace parametric
{

struct P1
{
  typedef int val_type;
  static val_type value()
  {
    return 1;
  }
};

struct P2
{
  typedef double val_type;
  static val_type value()
  {
    return 10.;
  }
};

template<typename A, typename B>
struct Parametric
{
  typedef typename A::val_type first_val_type;
  typedef typename B::val_type second_val_type;

  first_val_type get_first()
  {
    return A::value();
  }

  second_val_type get_second()
  {
    return B::value();
  }
};

template<typename A, typename B>
void apply_parametric(cpp_wrapper::Module& types)
{
  types.apply<Parametric<A,B>>()
    .method("get_first", &Parametric<A,B>::get_first)
    .method("get_second", &Parametric<A,B>::get_second);
}

// Template containing a non-type parameter
template<typename T, T I>
struct NonTypeParam
{
  NonTypeParam(T v = I) : i(v)
  {
  }

  T i = I;
};

// Wrap it, so we only have type parameters
template<typename T1, typename T2>
struct NonTypeParam_ : NonTypeParam<T1, T2::value>
{
  using NonTypeParam<T1, T2::value>::NonTypeParam;
};

// Add methods
template<typename T, T I>
void apply_nontype(cpp_wrapper::Module& types)
{
  typedef NonTypeParam_<T, std::integral_constant<T, I>> WrappedT;
  types.apply<WrappedT>()
    .template constructor<T>();
  types.method("get_nontype", [](const WrappedT& w) { return w.i; });
}

} // namespace parametric

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace parametric;
  cpp_wrapper::Module& types = registry.create_module("ParametricTypes");

  types.add_type<P1>("P1");
  types.add_type<P2>("P2");

  types.add_parametric<Parametric<cpp_wrapper::TypeVar<1>, cpp_wrapper::TypeVar<2>>>("Parametric");
  apply_parametric<P1,P2>(types);
  apply_parametric<P2,P1>(types);

  types.add_parametric<NonTypeParam_<cpp_wrapper::TypeVar<1>, cpp_wrapper::TypeVar<2>>>("NonTypeParam");
  apply_nontype<int, 1>(types);
  apply_nontype<unsigned int, 2>(types);
  apply_nontype<int64_t, 64>(types);
JULIA_CPP_MODULE_END
