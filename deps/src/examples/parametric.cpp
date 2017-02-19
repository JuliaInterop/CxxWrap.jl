#include <string>

#include <cxx_wrap.hpp>

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

template<typename A, typename B=void>
struct TemplateDefaultType
{
};

template<typename T>
struct AbstractTemplate
{
};

template<typename T>
struct ConcreteTemplate : public AbstractTemplate<T>
{
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

struct WrapTemplateDefaultType
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&& wrapped)
  {
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

struct WrapAbstractTemplate
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&&)
  {
  }
};

struct WrapConcreteTemplate
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&& w)
  {
    typedef typename TypeWrapperT::type WrappedT;
    w.module().method("to_base", [] (WrappedT* w) { return static_cast<AbstractTemplate<double>*>(w); });
  }
};

template<typename T1, typename T2, typename T3>
struct Foo3
{
};

struct WrapFoo3
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&& wrapped)
  {
    typedef typename TypeWrapperT::type WrappedT;
    wrapped.module().method("foo3_method", [] (const WrappedT&) {});
  }
};

} // namespace parametric

namespace cxx_wrap
{
  // Match type followed by non-type of the same type
  template<typename NonTT, NonTT Val, template<typename, NonTT> class T>
  struct BuildParameterList<T<NonTT, Val>>
  {
    typedef ParameterList<NonTT, std::integral_constant<NonTT, Val>> type;
  };
} // namespace cxx_wrap

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace cxx_wrap;
  using namespace parametric;
  Module& types = registry.create_module("ParametricTypes");

  types.add_type<P1>("P1");
  types.add_type<P2>("P2");

  types.add_type<Parametric<TypeVar<1>, TypeVar<2>>>("TemplateType")
    .apply<TemplateType<P1,P2>, TemplateType<P2,P1>>(WrapTemplateType());

  types.add_type<Parametric<TypeVar<1>>>("TemplateDefaultType")
    .apply<TemplateDefaultType<P1>, TemplateDefaultType<P2>>(WrapTemplateDefaultType());

  types.add_type<Parametric<cxx_wrap::TypeVar<1>, cxx_wrap::TypeVar<2>>>("NonTypeParam")
    .apply<NonTypeParam<int, 1>, NonTypeParam<unsigned int, 2>, NonTypeParam<int64_t, 64>>(WrapNonTypeParam());

  auto abstract_template = types.add_abstract<Parametric<cxx_wrap::TypeVar<1>>>("AbstractTemplate");
  abstract_template.apply<AbstractTemplate<double>>(WrapAbstractTemplate());

  types.add_type<Parametric<cxx_wrap::TypeVar<1>>>("ConcreteTemplate", abstract_template.dt()).apply<ConcreteTemplate<double>>(WrapConcreteTemplate());

  types.add_type<Parametric<TypeVar<1>, TypeVar<2>, TypeVar<3>>>("Foo3")
    .apply_combination<Foo3, ParameterList<int32_t, double>, ParameterList<P1,P2,bool>, ParameterList<float>>(WrapFoo3());
JULIA_CPP_MODULE_END
