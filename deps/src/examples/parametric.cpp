#include <string>

#include <cpp_wrapper.hpp>

namespace parametric
{

struct P1
{
  typedef int val_type;
  val_type value() const
  {
    return 1;
  }
};

struct P2
{
  typedef double val_type;
  val_type value() const
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

} // namespace parametric

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace parametric;
  cpp_wrapper::Module& types = registry.create_module("ParametricTypes");

  types.add_parametric<Parametric<cpp_wrapper::TypeParameters<P1, P2>, cpp_wrapper::TypeParameters<P2, P1>>>("Parametric", [](auto& wrapped)
  {
    // WrappedT is the concrete Parametric with the template parameters defined, i.e. Parametric<P1,P2> or Parametric<P2,P1> in this case
    typedef cpp_wrapper::get_wrappped_type<decltype(wrapped)> WrappedT;
    wrapped.def("get_first", &WrappedT::get_first);
    wrapped.def("get_second", &WrappedT::get_second);
  });

JULIA_CPP_MODULE_END
