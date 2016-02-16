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
struct TemplateType
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

// Template containing a non-type parameter
template<typename T, T I>
struct NonTypeParam
{
  typedef T type;
  NonTypeParam(T v = I) : i(v)
  {
  }

  T i = I;
};

// Helper to wrap TemplateType instances. May also be a C++14 lambda, see README.md
struct WrapTemplateType
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&& wrapped)
  {
    typedef typename TypeWrapperT::type WrappedT;
    wrapped.method("get_first", &WrappedT::get_first);
    wrapped.method("get_second", &WrappedT::get_second);
  }
};

// Helper to wrap NonTypeParam instances
struct WrapNonTypeParam
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&& wrapped)
  {
    typedef typename TypeWrapperT::type WrappedT;
    wrapped.template constructor<typename WrappedT::type>();
    // Access the module to add a free function
    wrapped.module().method("get_nontype", [](const WrappedT& w) { return w.i; });
  }
};

} // namespace parametric

namespace cpp_wrapper
{
  // Match type followed by non-type of the same type
  template<typename NonTT, NonTT Val, template<typename, NonTT> class T>
  struct BuildParameterList<T<NonTT, Val>>
  {
    typedef ParameterList<NonTT, std::integral_constant<NonTT, Val>> type;
  };
} // namespace cpp_wrapper

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cpp_wrapper;
  using namespace parametric;
  Module& types = registry.create_module("ParametricTypes");

  types.add_type<P1>("P1");
  types.add_type<P2>("P2");

  types.add_type<Parametric<TypeVar<1>, TypeVar<2>>>("TemplateType")
    .apply<TemplateType<P1,P2>, TemplateType<P2,P1>>(WrapTemplateType());


  types.add_type<Parametric<cpp_wrapper::TypeVar<1>, cpp_wrapper::TypeVar<2>>>("NonTypeParam")
    .apply<NonTypeParam<int, 1>, NonTypeParam<unsigned int, 2>, NonTypeParam<int64_t, 64>>(WrapNonTypeParam());
JULIA_CPP_MODULE_END
