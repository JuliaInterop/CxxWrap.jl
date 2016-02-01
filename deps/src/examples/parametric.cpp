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

template<typename T>
struct SimpleParametric
{
  SimpleParametric()
  {
    std::cout << "Created SimpleParametric";
  }

  T value;
};

} // namespace parametric

JULIA_CPP_MODULE_BEGIN(registry)
  using namespace parametric;
  cpp_wrapper::Module& types = registry.create_module("ParametricTypes");


  types.add_parametric<SimpleParametric<cpp_wrapper::TypeVar<1>>>("SimpleParametric");
  types.apply<SimpleParametric<int>>();

  types.add_parametric<Parametric<cpp_wrapper::TypeVar<1>, cpp_wrapper::TypeVar<2>>>("Parametric", cpp_wrapper::TypeList<int, double>("a", "b"));

JULIA_CPP_MODULE_END
