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

} // namespace parametric

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace parametric;
  cpp_wrapper::Module& types = registry.create_module("ParametricTypes");

  types.add_type<P1>("P1");
  types.add_type<P2>("P2");

  types.add_parametric<Parametric<cpp_wrapper::TypeVar<1>, cpp_wrapper::TypeVar<2>>>("Parametric");
  apply_parametric<P1,P2>(types);
  apply_parametric<P2,P1>(types);


JULIA_CPP_MODULE_END
