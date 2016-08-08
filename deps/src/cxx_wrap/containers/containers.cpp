#include <string>

#include "../cxx_wrap.hpp"

#include "const_array.hpp"

namespace cxx_wrap
{

jl_datatype_t* g_constptr_dt;

template<int I>
struct static_type_mapping<ConstPtr<TypeVar<I>>>
{
  typedef jl_datatype_t* type;
  static jl_datatype_t* julia_type()
  {
    static jl_datatype_t* result = nullptr;
    if(result == nullptr)
    {
      result = (jl_datatype_t*)jl_apply_type((jl_value_t*)g_constptr_dt, jl_svec1(TypeVar<I>::tvar()));
      protect_from_gc(result);
    }
    return result;
  }
  template<typename T2> using remove_const_ref = cxx_wrap::remove_const_ref<T2>;
};

RegisterHook const_array_reg([]() {
  Module m("CxxWrap");
  g_constptr_dt = m.add_bits<ConstPtr<TypeVar<1>>>("ConstPtr").dt();
  m.add_immutable<Parametric<TypeVar<1>, TypeVar<2>>>("ConstArray", FieldList<ConstPtr<TypeVar<1>>, NTuple<TypeVar<2>, long>>("ptr", "size"), julia_type("CppArray"));
  m.bind_types(g_cxx_wrap_module);
});

}
