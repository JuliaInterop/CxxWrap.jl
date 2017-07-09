#include <type_traits>

#include "jlcxx/jlcxx.hpp"

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
  void operator()(TypeWrapperT&&)
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

struct Foo3FreeMethod
{
  Foo3FreeMethod(jlcxx::Module& mod) : m_module(mod)
  {
  }

  template<typename T>
  void operator()()
  {
    m_module.method("foo3_free_method", [] (T) {});
  }

  jlcxx::Module& m_module;
};

template<typename T1, bool B = false>
struct Foo2
{
};

struct ApplyFoo2
{
  template<typename T> using apply = Foo2<T>;
};

struct WrapFoo2
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&& wrapped)
  {
    typedef typename TypeWrapperT::type WrappedT;
    wrapped.module().method("foo2_method", [] (const WrappedT&) {});
  }
};

template<typename T>
struct CppVector
{
};

struct WrapCppVector
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&&)
  {
  }
};

template<typename T1, typename T2>
struct CppVector2
{
};

struct WrapCppVector2
{
  template<typename TypeWrapperT>
  void operator()(TypeWrapperT&&)
  {
  }
};

} // namespace parametric

namespace jlcxx
{
  // Match type followed by non-type of the same type
  template<typename NonTT, NonTT Val, template<typename, NonTT> class T>
  struct BuildParameterList<T<NonTT, Val>>
  {
    typedef ParameterList<NonTT, std::integral_constant<NonTT, Val>> type;
  };

  template<typename T>
  struct BuildParameterList<parametric::Foo2<T>>
  {
    typedef ParameterList<T> type;
  };
} // namespace jlcxx

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace jlcxx;
  using namespace parametric;
  Module& types = registry.create_module("ParametricTypes");

  types.add_type<P1>("P1");
  types.add_type<P2>("P2");

  types.add_type<Parametric<TypeVar<1>, TypeVar<2>>>("TemplateType")
    .apply<TemplateType<P1,P2>, TemplateType<P2,P1>>(WrapTemplateType());

  types.add_type<Parametric<TypeVar<1>>>("TemplateDefaultType")
    .apply<TemplateDefaultType<P1>, TemplateDefaultType<P2>>(WrapTemplateDefaultType());

  types.add_type<Parametric<jlcxx::TypeVar<1>, jlcxx::TypeVar<2>>>("NonTypeParam")
    .apply<NonTypeParam<int, 1>, NonTypeParam<unsigned int, 2>, NonTypeParam<int64_t, 64>>(WrapNonTypeParam());

  auto abstract_template = types.add_type<Parametric<jlcxx::TypeVar<1>>>("AbstractTemplate");
  abstract_template.apply<AbstractTemplate<double>>(WrapAbstractTemplate());

  types.add_type<Parametric<jlcxx::TypeVar<1>>>("ConcreteTemplate", abstract_template.dt()).apply<ConcreteTemplate<double>>(WrapConcreteTemplate());

  types.add_type<Parametric<TypeVar<1>, TypeVar<2>, TypeVar<3>>, ParameterList<TypeVar<1>>>("Foo3", abstract_template.dt())
    .apply_combination<Foo3, ParameterList<int32_t, double>, ParameterList<P1,P2,bool>, ParameterList<float>>(WrapFoo3());

  /// Add a non-member function that uses Foo3
  typedef jlcxx::combine_types<jlcxx::ApplyType<Foo3>, ParameterList<int32_t, double>, ParameterList<P1,P2,bool>, ParameterList<float>> foo3_types;
  jlcxx::for_each_type<foo3_types>(Foo3FreeMethod(types));

  types.add_type<Parametric<TypeVar<1>>>("Foo2")
    .apply_combination<ApplyFoo2, ParameterList<int32_t, double>>(WrapFoo2());

  types.add_type<Parametric<TypeVar<1>>>("CppVector", jlcxx::julia_type("AbstractVector"))
    .apply<CppVector<double>>(WrapCppVector());

  types.add_type<Parametric<TypeVar<1>, TypeVar<2>>, ParameterList<TypeVar<1>>>("CppVector2", jlcxx::julia_type("AbstractVector"))
    .apply<CppVector2<double,float>>(WrapCppVector2());
JULIA_CPP_MODULE_END
