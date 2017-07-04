#ifndef JLCXX_HPP
#define JLCXX_HPP

#include <cassert>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <sstream>
#include <typeinfo>
#include <typeindex>
#include <vector>

#include "array.hpp"
#include "smart_pointers.hpp"
#include "type_conversion.hpp"

namespace jlcxx
{

/// Compatibility between 0.6 and 0.7
jl_datatype_t* new_datatype(jl_sym_t *name,
                            jl_module_t* module,
                            jl_datatype_t *super,
                            jl_svec_t *parameters,
                            jl_svec_t *fnames, jl_svec_t *ftypes,
                            int abstract, int mutabl,
                            int ninitialized);

/// Some helper functions
namespace detail
{

// Need to treat void specially
template<typename R, typename... Args>
struct ReturnTypeAdapter
{
  using return_type = decltype(convert_to_julia(std::declval<R>()));

  inline return_type operator()(const void* functor, mapped_julia_type<Args>... args)
  {
    auto std_func = reinterpret_cast<const std::function<R(Args...)>*>(functor);
    assert(std_func != nullptr);
    return convert_to_julia((*std_func)(convert_to_cpp<mapped_reference_type<Args>>(args)...));
  }
};

template<typename... Args>
struct ReturnTypeAdapter<void, Args...>
{
  inline void operator()(const void* functor, mapped_julia_type<Args>... args)
  {
    auto std_func = reinterpret_cast<const std::function<void(Args...)>*>(functor);
    assert(std_func != nullptr);
    (*std_func)(convert_to_cpp<mapped_reference_type<Args>>(args)...);
  }
};

/// Call a C++ std::function, passed as a void pointer since it comes from Julia
template<typename R, typename... Args>
struct CallFunctor
{
  using return_type = decltype(ReturnTypeAdapter<R, Args...>()(std::declval<const void*>(), std::declval<mapped_julia_type<Args>>()...));

  static return_type apply(const void* functor, mapped_julia_type<Args>... args)
  {
    try
    {
      return ReturnTypeAdapter<R, Args...>()(functor, args...);
    }
    catch(const std::exception& err)
    {
      jl_error(err.what());
    }

    return return_type();
  }
};

/// Make a vector with the types in the variadic template parameter pack
template<typename... Args>
std::vector<jl_datatype_t*> argtype_vector()
{
  return {julia_type<dereference_for_mapping<Args>>()...};
}
template<typename... Args>
std::vector<jl_datatype_t*> reference_argtype_vector()
{
  return {julia_reference_type<dereference_for_mapping<Args>>()...};
}


template<typename... Args>
struct NeedConvertHelper
{
  bool operator()()
  {
    for(const bool b : {std::is_same<remove_const_ref<mapped_julia_type<Args>>,remove_const_ref<Args>>::value...})
    {
      if(!b)
        return true;
    }
    return false;
  }
};

template<>
struct NeedConvertHelper<>
{
  bool operator()()
  {
    return false;
  }
};

} // end namespace detail

/// Convenience function to create an object with a finalizer attached
template<typename T, typename... ArgsT>
jl_value_t* create(ArgsT&&... args)
{
  jl_datatype_t* dt = static_type_mapping<T>::julia_allocated_type();
  assert(!jl_isbits(dt));

  T* cpp_obj = new T(std::forward<ArgsT>(args)...);

  return boxed_cpp_pointer(cpp_obj, dt, true);
}

/// Safe downcast to base type
template<typename T>
struct DownCast
{
  static inline supertype<T>& apply(T& base)
  {
    return static_cast<supertype<T>&>(base);
  }
};

// The CxxWrap Julia module
extern jl_module_t* g_cxxwrap_module;
extern jl_datatype_t* g_cppfunctioninfo_type;

/// Abstract base class for storing any function
class FunctionWrapperBase
{
public:
  FunctionWrapperBase(jl_datatype_t* return_type) : m_return_type(return_type)
  {
  }

  /// Function pointer as void*, since that's what Julia expects
  virtual void* pointer() = 0;

  /// The thunk (i.e. std::function) to pass as first argument to the function pointed to by function_pointer
  virtual void* thunk() = 0;

  /// Types of the arguments (used in the wrapper signature)
  virtual std::vector<jl_datatype_t*> argument_types() const = 0;

  /// Reference type for the arguments (used in the ccall type list)
  virtual std::vector<jl_datatype_t*> reference_argument_types() const = 0;

  /// Return type
  jl_datatype_t* return_type() const { return m_return_type; }

  void set_return_type(jl_datatype_t* dt) { m_return_type = dt; }

  virtual ~FunctionWrapperBase() {}

  inline void set_name(jl_value_t* name)
  {
    protect_from_gc(name);
    m_name = name;
  }

  inline jl_value_t* name() const
  {
    return m_name;
  }

private:
  jl_value_t* m_name;
  jl_datatype_t* m_return_type = nullptr;
};

/// Implementation of function storage, case of std::function
template<typename R, typename... Args>
class FunctionWrapper : public FunctionWrapperBase
{
public:
  typedef std::function<R(Args...)> functor_t;

  FunctionWrapper(const functor_t& function) : FunctionWrapperBase(julia_return_type<R>()), m_function(function)
  {
  }

  virtual void* pointer()
  {
    return reinterpret_cast<void*>(detail::CallFunctor<R, Args...>::apply);
  }

  virtual void* thunk()
  {
    return reinterpret_cast<void*>(&m_function);
  }

  virtual std::vector<jl_datatype_t*> argument_types() const
  {
    return detail::argtype_vector<Args...>();
  }

  virtual std::vector<jl_datatype_t*> reference_argument_types() const
  {
    return detail::reference_argtype_vector<Args...>();
  }

private:
  functor_t m_function;
};

/// Implementation of function storage, case of a function pointer
template<typename R, typename... Args>
class FunctionPtrWrapper : public FunctionWrapperBase
{
public:
  typedef std::function<R(Args...)> functor_t;

  FunctionPtrWrapper(R(*f)(Args...)) : FunctionWrapperBase(julia_return_type<R>()), m_function(f)
  {
  }

  virtual void* pointer()
  {
    return reinterpret_cast<void*>(m_function);
  }

  virtual void* thunk()
  {
    return nullptr;
  }

  virtual std::vector<jl_datatype_t*> argument_types() const
  {
    return detail::argtype_vector<Args...>();
  }

  virtual std::vector<jl_datatype_t*> reference_argument_types() const
  {
    return detail::reference_argtype_vector<Args...>();
  }

private:
  R(*m_function)(Args...);
};

/// Indicate that a parametric type is to be added
template<typename... ParametersT>
struct Parametric
{
};

template<typename T>
class TypeWrapper;

class JLCXX_API Module;

/// Specialise this to instantiate parametric types when first used in a wrapper
template<typename T>
struct InstantiateParametricType
{
  // Returns int to expand parameter packs into an initilization list
  int operator()(Module&) const
  {
    return 0;
  }
};

template<typename... TypesT>
void instantiate_parametric_types(Module& m)
{
  auto unused = {InstantiateParametricType<remove_const_ref<TypesT>>()(m)...};
}

namespace detail
{

template<typename T>
struct GetJlType
{
  jl_datatype_t* operator()() const
  {
    try
    {
      return julia_type<remove_const_ref<T>>();
    }
    catch(...)
    {
      // The assumption here is that unmapped types are not needed, i.e. in default argument lists
      return nullptr;
    }
  }
};

template<int I>
struct GetJlType<TypeVar<I>>
{
  jl_tvar_t* operator()() const
  {
    return TypeVar<I>::tvar();
  }
};

template<typename T, T Val>
struct GetJlType<std::integral_constant<T, Val>>
{
  jl_value_t* operator()() const
   {
    return box(convert_to_julia(Val));
  }
};

template<typename T>
struct IsParametric
{
  static constexpr bool value = false;
};

template<template<typename...> class T, int I, typename... ParametersT>
struct IsParametric<T<TypeVar<I>, ParametersT...>>
{
  static constexpr bool value = true;
};

template<typename... ArgsT>
inline jl_value_t* make_fname(const std::string& nametype, ArgsT... args)
{
  jl_value_t* name = nullptr;
  JL_GC_PUSH1(&name);
  name = jl_new_struct(julia_type(nametype), args...);
  protect_from_gc(name);
  JL_GC_POP();

  return name;
}

} // namespace detail

// Encapsulate a list of parameters, using types only
template<typename... ParametersT>
struct ParameterList
{
  static constexpr int nb_parameters = sizeof...(ParametersT);

  jl_svec_t* operator()(const int n = nb_parameters)
  {
    jl_svec_t* result = jl_svec(n, detail::GetJlType<ParametersT>()()...);
    for(int i = 0; i != n; ++i)
    {
      if(jl_svecref(result,i) == nullptr)
      {
        throw std::runtime_error("Attempt to use unmapped type in parameter list");
      }
    }
    return result;
  }
};

/// Store all exposed C++ functions associated with a module
class JLCXX_API Module
{
public:

  Module(const std::string& name, jl_module_t* jl_mod);

  void append_function(FunctionWrapperBase* f)
  {
    m_functions.resize(m_functions.size()+1);
    m_functions.back().reset(f);
  }

  /// Define a new function
  template<typename R, typename... Args>
  FunctionWrapperBase& method(const std::string& name,  std::function<R(Args...)> f)
  {
    instantiate_parametric_types<R, Args...>(*this);
    auto* new_wrapper = new FunctionWrapper<R, Args...>(f);
    new_wrapper->set_name((jl_value_t*)jl_symbol(name.c_str()));
    append_function(new_wrapper);
    return *new_wrapper;
  }

  /// Define a new function. Overload for pointers
  template<typename R, typename... Args>
  FunctionWrapperBase& method(const std::string& name,  R(*f)(Args...), const bool force_convert = false)
  {
    bool need_convert = force_convert || !std::is_same<mapped_julia_type<R>,remove_const_ref<R>>::value || detail::NeedConvertHelper<Args...>()();

    // Conversion is automatic when using the std::function calling method, so if we need conversion we use that
    if(need_convert)
    {
      return method(name, std::function<R(Args...)>(f));
    }

    instantiate_parametric_types<R, Args...>(*this);

    // No conversion needed -> call can be through a naked function pointer
    auto* new_wrapper = new FunctionPtrWrapper<R, Args...>(f);
    new_wrapper->set_name((jl_value_t*)jl_symbol(name.c_str()));
    append_function(new_wrapper);
    return *new_wrapper;
  }

  /// Define a new function. Overload for lambda
  template<typename LambdaT>
  FunctionWrapperBase& method(const std::string& name, LambdaT&& lambda)
  {
    return add_lambda(name, std::forward<LambdaT>(lambda), &LambdaT::operator());
  }

  /// Add a constructor with the given argument types for the given datatype (used to get the name)
  template<typename T, typename... ArgsT>
  void constructor(jl_datatype_t* dt)
  {
    FunctionWrapperBase& new_wrapper = method("dummy", [](ArgsT... args) { return create<T>(args...); });
    new_wrapper.set_name(detail::make_fname("ConstructorFname", dt));
  }

  /// Loop over the functions
  template<typename F>
  void for_each_function(const F f) const
  {
    for(const auto& item : m_functions)
    {
      f(*item);
    }
  }

  /// Add a composite type
  template<typename T, typename SuperParametersT=ParameterList<>>
  TypeWrapper<T> add_type(const std::string& name, jl_datatype_t* super = julia_type<CppAny>());

  template<typename T>
  void add_bits(const std::string& name, jl_datatype_t* super = julia_type("CppBits"));

  /// Set a global constant value at the module level
  template<typename T>
  void set_const(const std::string& name, T&& value)
  {
    if(m_jl_constants.count(name) != 0)
    {
      throw std::runtime_error("Duplicate registration of constant " + name);
    }
    jl_value_t* boxed_const = box(std::forward<T>(value));
    if(gc_index_map().count(boxed_const) == 0)
    {
      protect_from_gc(boxed_const);
    }
    m_jl_constants[name] = boxed_const;
  }

  const std::string& name() const
  {
    return m_name;
  }

  void bind_constants(jl_module_t* mod)
  {
    for(auto& dt_pair : m_jl_constants)
    {
      jl_set_const(mod, jl_symbol(dt_pair.first.c_str()), dt_pair.second);
    }
  }

  /// Export the given symbols
  template<typename... ArgsT>
  void export_symbols(ArgsT... args)
  {
    m_exported_symbols.insert(m_exported_symbols.end(), {args...});
  }

  const std::vector<std::string>& exported_symbols()
  {
    return m_exported_symbols;
  }

  jl_datatype_t* get_julia_type(const char* name)
  {
    if(m_jl_constants.count(name) != 0 && jl_is_datatype(m_jl_constants[name]))
    {
      return (jl_datatype_t*)m_jl_constants[name];
    }

    return nullptr;
  }

  void register_type_pair(jl_datatype_t* reference_type, jl_datatype_t* allocated_type)
  {
    m_reference_types.push_back(reference_type);
    m_allocated_types.push_back(allocated_type);
  }

  const std::vector<jl_datatype_t*> reference_types() const
  {
    return m_reference_types;
  }

  const std::vector<jl_datatype_t*> allocated_types() const
  {
    return m_allocated_types;
  }

  jl_module_t* julia_module() const
  {
    return m_jl_mod;
  }

private:

  template<typename T>
  void add_default_constructor(std::true_type, jl_datatype_t* dt);

  template<typename T>
  void add_default_constructor(std::false_type, jl_datatype_t*)
  {
  }

  template<typename T>
  void add_copy_constructor(std::true_type, jl_datatype_t*)
  {
    method("deepcopy_internal", [this](const T& other, ObjectIdDict)
    {
      return create<T>(other);
    });
  }

  template<typename T>
  void add_copy_constructor(std::false_type, jl_datatype_t*)
  {
  }

  template<typename T, typename SuperParametersT>
  TypeWrapper<T> add_type_internal(const std::string& name, jl_datatype_t* super);

  template<typename R, typename LambdaT, typename... ArgsT>
  FunctionWrapperBase& add_lambda(const std::string& name, LambdaT&& lambda, R(LambdaT::*)(ArgsT...) const)
  {
    return method(name, std::function<R(ArgsT...)>(std::forward<LambdaT>(lambda)));
  }

  std::string m_name;
  jl_module_t* m_jl_mod;
  std::vector<std::shared_ptr<FunctionWrapperBase>> m_functions;
  std::map<std::string, jl_value_t*> m_jl_constants;
  std::vector<std::string> m_exported_symbols;
  std::vector<jl_datatype_t*> m_reference_types;
  std::vector<jl_datatype_t*> m_allocated_types;

  template<class T> friend class TypeWrapper;
};

template<typename T>
void Module::add_default_constructor(std::true_type, jl_datatype_t* dt)
{
  this->constructor<T>(dt);
}

// Specialize this to build the correct parameter list, wrapping non-types in integral constants
// There is no way to provide a template here that matchs all possible combinations of type and non-type arguments
template<typename T>
struct BuildParameterList
{
  typedef ParameterList<> type;
};

template<typename T> using parameter_list = typename BuildParameterList<T>::type;

// Match any combination of types only
template<template<typename...> class T, typename... ParametersT>
struct BuildParameterList<T<ParametersT...>>
{
  typedef ParameterList<ParametersT...> type;
};

// Match any number of int parameters
template<template<int...> class T, int... ParametersT>
struct BuildParameterList<T<ParametersT...>>
{
  typedef ParameterList<std::integral_constant<int, ParametersT>...> type;
};

namespace detail
{
  template<typename... Types>
  struct DoApply;

  template<>
  struct DoApply<>
  {
    template<typename WrapperT, typename FunctorT>
    void operator()(WrapperT&, FunctorT&&)
    {
    }
  };

  template<typename AppT>
  struct DoApply<AppT>
  {
    template<typename WrapperT, typename FunctorT>
    void operator()(WrapperT& w, FunctorT&& ftor)
    {
      w.template apply<AppT>(std::forward<FunctorT>(ftor));
    }
  };

  template<typename... Types>
  struct DoApply<ParameterList<Types...>>
  {
    template<typename WrapperT, typename FunctorT>
    void operator()(WrapperT& w, FunctorT&& ftor)
    {
      DoApply<Types...>()(w, std::forward<FunctorT>(ftor));
    }
  };

  template<typename T1, typename... Types>
  struct DoApply<T1, Types...>
  {
    template<typename WrapperT, typename FunctorT>
    void operator()(WrapperT& w, FunctorT&& ftor)
    {
      DoApply<T1>()(w, std::forward<FunctorT>(ftor));
      DoApply<Types...>()(w, std::forward<FunctorT>(ftor));
    }
  };
}

/// Execute a functor on each type
template<typename... Types>
struct ForEachType;

template<>
struct ForEachType<>
{
  template<typename FunctorT>
  void operator()(FunctorT&&)
  {
  }
};

template<typename AppT>
struct ForEachType<AppT>
{
  template<typename FunctorT>
  void operator()(FunctorT&& ftor)
  {
#ifdef _MSC_VER
    ftor.operator()<AppT>();
#else 
    ftor.template operator()<AppT>();
#endif
  }
};

template<typename... Types>
struct ForEachType<ParameterList<Types...>>
{
  template<typename FunctorT>
  void operator()(FunctorT&& ftor)
  {
    ForEachType<Types...>()(std::forward<FunctorT>(ftor));
  }
};

template<typename T1, typename... Types>
struct ForEachType<T1, Types...>
{
  template<typename FunctorT>
  void operator()(FunctorT&& ftor)
  {
    ForEachType<T1>()(std::forward<FunctorT>(ftor));
    ForEachType<Types...>()(std::forward<FunctorT>(ftor));
  }
};

template<typename T, typename FunctorT>
void for_each_type(FunctorT&& f)
{
  ForEachType<T>()(f);
}

/// Trait to allow user-controlled disabling of the default constructor
template<typename T>
struct DefaultConstructible : std::is_default_constructible<T>
{
};

/// Trait to allow user-controlled disabling of the copy constructor
template<typename T>
struct CopyConstructible : std::is_copy_constructible<T>
{
};

template<typename... Types>
struct UnpackedTypeList
{
};

template<typename ApplyT, typename... TypeLists>
struct CombineTypes;

template<typename ApplyT, typename... UnpackedTypes>
struct CombineTypes<ApplyT, UnpackedTypeList<UnpackedTypes...>>
{
  typedef typename ApplyT::template apply<UnpackedTypes...> type;
};

template<typename ApplyT, typename... UnpackedTypes, typename... Types, typename... OtherTypeLists>
struct CombineTypes<ApplyT, UnpackedTypeList<UnpackedTypes...>, ParameterList<Types...>, OtherTypeLists...>
{
  typedef CombineTypes<ApplyT, UnpackedTypeList<UnpackedTypes...>, ParameterList<Types...>, OtherTypeLists...> ThisT;
  template<typename T1> using type_unpack = CombineTypes<ApplyT, UnpackedTypeList<UnpackedTypes..., T1>, OtherTypeLists...>;
  typedef ParameterList<typename ThisT::template type_unpack<Types>::type...> type;
};

template<typename ApplyT, typename... Types, typename... OtherTypeLists>
struct CombineTypes<ApplyT, ParameterList<Types...>, OtherTypeLists...>
{
  typedef CombineTypes<ApplyT, ParameterList<Types...>, OtherTypeLists...> ThisT;
  template<typename T1> using type_unpack = CombineTypes<ApplyT, UnpackedTypeList<T1>, OtherTypeLists...>;
  typedef ParameterList<typename ThisT::template type_unpack<Types>::type...> type;
};

// Default ApplyT implementation
template<template<typename...> class TemplateT>
struct ApplyType
{
  template<typename... Types> using apply = TemplateT<Types...>;
};

/// Helper class to wrap type methods
template<typename T>
class TypeWrapper
{
public:
  typedef T type;

  TypeWrapper(Module& mod, jl_datatype_t* dt, jl_datatype_t* ref_dt, jl_datatype_t* alloc_dt) :
    m_module(mod),
    m_dt(dt),
    m_ref_dt(ref_dt),
    m_alloc_dt(alloc_dt)
  {
  }

  /// Add a constructor with the given argument types
  template<typename... ArgsT>
  TypeWrapper<T>& constructor()
  {
    m_module.constructor<T, ArgsT...>(m_dt);
    return *this;
  }

  /// Define a member function
  template<typename R, typename CT, typename... ArgsT>
  TypeWrapper<T>& method(const std::string& name, R(CT::*f)(ArgsT...))
  {
    m_module.method(name, [f](T& obj, ArgsT... args) -> R { return (obj.*f)(args...); } );
    return *this;
  }

  /// Define a member function, const version
  template<typename R, typename CT, typename... ArgsT>
  TypeWrapper<T>& method(const std::string& name, R(CT::*f)(ArgsT...) const)
  {
    m_module.method(name, [f](const T& obj, ArgsT... args) -> R { return (obj.*f)(args...); } );
    return *this;
  }

  /// Call operator overload. For both reference and allocated type to work around https://github.com/JuliaLang/julia/issues/14919
  template<typename R, typename CT, typename... ArgsT>
  TypeWrapper<T>& method(R(CT::*f)(ArgsT...))
  {
    m_module.method("operator()", [f](T& obj, ArgsT... args) -> R { return (obj.*f)(args...); } )
      .set_name(detail::make_fname("CallOpOverload", m_ref_dt));
    m_module.method("operator()", [f](T& obj, ArgsT... args) -> R { return (obj.*f)(args...); } )
      .set_name(detail::make_fname("CallOpOverload", m_alloc_dt));
    return *this;
  }
  template<typename R, typename CT, typename... ArgsT>
  TypeWrapper<T>& method(R(CT::*f)(ArgsT...) const)
  {
    m_module.method("operator()", [f](const T& obj, ArgsT... args) -> R { return (obj.*f)(args...); } )
      .set_name(detail::make_fname("CallOpOverload", m_ref_dt));
    m_module.method("operator()", [f](const T& obj, ArgsT... args) -> R { return (obj.*f)(args...); } )
      .set_name(detail::make_fname("CallOpOverload", m_alloc_dt));
    return *this;
  }

  template<typename... AppliedTypesT, typename FunctorT>
  TypeWrapper<T>& apply(FunctorT&& apply_ftor)
  {
    static_assert(detail::IsParametric<T>::value, "Apply can only be called on parametric types");
    auto dummy = {apply_internal<AppliedTypesT>(std::forward<FunctorT>(apply_ftor))...};
    return *this;
  }

  /// Apply all possible combinations of the given types (see example)
  template<template<typename...> class TemplateT, typename... TypeLists, typename FunctorT>
  void apply_combination(FunctorT&& ftor);

  template<typename ApplyT, typename... TypeLists, typename FunctorT>
  void apply_combination(FunctorT&& ftor);

  // Access to the module
  Module& module()
  {
    return m_module;
  }

  jl_datatype_t* dt()
  {
    return m_dt;
  }

private:

  template<typename AppliedT, typename FunctorT>
  int apply_internal(FunctorT&& apply_ftor)
  {
    static_assert(parameter_list<AppliedT>::nb_parameters != 0, "No parameters found when applying type. Specialize jlcxx::BuildParameterList for your combination of type and non-type parameters.");
    static_assert(parameter_list<AppliedT>::nb_parameters >= parameter_list<T>::nb_parameters, "Parametric type applied to wrong number of parameters.");
    const bool is_abstract = jl_is_abstracttype(m_dt);

    jl_datatype_t* app_dt = (jl_datatype_t*)apply_type((jl_value_t*)m_dt, parameter_list<AppliedT>()(parameter_list<T>::nb_parameters));
    jl_datatype_t* app_ref_dt = (jl_datatype_t*)apply_type((jl_value_t*)m_ref_dt, parameter_list<AppliedT>()(parameter_list<T>::nb_parameters));
    jl_datatype_t* app_alloc_dt = (jl_datatype_t*)apply_type((jl_value_t*)m_alloc_dt, parameter_list<AppliedT>()(parameter_list<T>::nb_parameters));

    set_julia_type<AppliedT>(app_dt);
    m_module.add_default_constructor<AppliedT>(DefaultConstructible<AppliedT>(), app_dt);
    m_module.add_copy_constructor<AppliedT>(CopyConstructible<AppliedT>(), app_dt);
    static_type_mapping<AppliedT>::set_reference_type(app_ref_dt);
    static_type_mapping<AppliedT>::set_allocated_type(app_alloc_dt);

    apply_ftor(TypeWrapper<AppliedT>(m_module, app_dt, app_ref_dt, app_alloc_dt));

    m_module.register_type_pair(app_ref_dt, app_alloc_dt);

    if(!std::is_same<supertype<AppliedT>,AppliedT>::value)
    {
      m_module.method("cxxdowncast", DownCast<AppliedT>::apply);
    }

    return 0;
  }
  Module& m_module;
  jl_datatype_t* m_dt;
  jl_datatype_t* m_ref_dt;
  jl_datatype_t* m_alloc_dt;
};

template<typename ApplyT, typename... TypeLists> using combine_types = typename CombineTypes<ApplyT, TypeLists...>::type;

template<typename T>
template<template<typename...> class TemplateT, typename... TypeLists, typename FunctorT>
void TypeWrapper<T>::apply_combination(FunctorT&& ftor)
{
  apply_combination<ApplyType<TemplateT>, TypeLists...>(std::forward<FunctorT>(ftor));
}

template<typename T>
template<typename ApplyT, typename... TypeLists, typename FunctorT>
void TypeWrapper<T>::apply_combination(FunctorT&& ftor)
{
  typedef typename CombineTypes<ApplyT, TypeLists...>::type applied_list;
  detail::DoApply<applied_list>()(*this, std::forward<FunctorT>(ftor));
}

template<typename T, typename SuperParametersT>
TypeWrapper<T> Module::add_type_internal(const std::string& name, jl_datatype_t* super)
{
  static constexpr bool is_parametric = detail::IsParametric<T>::value;
  static_assert(!IsImmutable<T>::value, "Immutable types (marked with IsImmutable) can't be added using add_type, map them directly to a struct instead");
  static_assert(!IsBits<T>::value, "Bits types must be added using add_bits");

  if(m_jl_constants.count(name) > 0)
  {
    throw std::runtime_error("Duplicate registration of type or constant " + name);
  }

  jl_svec_t* parameters = nullptr;
  jl_svec_t* super_parameters = nullptr;
  jl_svec_t* fnames = nullptr;
  jl_svec_t* ftypes = nullptr;
  JL_GC_PUSH5(&super, &parameters, &super_parameters, &fnames, &ftypes);

  parameters = is_parametric ? parameter_list<T>()() : jl_emptysvec;
  fnames = jl_svec1(jl_symbol("cpp_object"));
  ftypes = jl_svec1(jl_voidpointer_type);

  size_t n_super_params = jl_nparams(super);
  if(is_parametric && n_super_params != 0)
  {
    super_parameters = SuperParametersT::nb_parameters == 0 ? parameter_list<T>()() : SuperParametersT()();
    if(n_super_params == jl_svec_len(super_parameters))
    {
      super = (jl_datatype_t*)apply_type((jl_value_t*)super, super_parameters);
    }
    else
    {
      std::stringstream err_msg;
      err_msg << "Invalid number of parameters for supertype " << julia_type_name(super) << ": wanted " << n_super_params << " parameters, " << " got " << jl_svec_len(super_parameters) << " parameters" << std::endl;
      throw std::runtime_error(err_msg.str());
    }
  }

  const std::string refname = name+"Ref";
  const std::string allocname = name+"Allocated";

  // Create the datatypes
  jl_datatype_t* base_dt = new_datatype(jl_symbol(name.c_str()), m_jl_mod, super, parameters, jl_emptysvec, jl_emptysvec, 1, 0, 0);
  protect_from_gc(base_dt);

  super = is_parametric ? (jl_datatype_t*)apply_type((jl_value_t*)base_dt, parameters) : base_dt;

  jl_datatype_t* ref_dt = new_datatype(jl_symbol(refname.c_str()), m_jl_mod, super, parameters, fnames, ftypes, 0, 0, 1);
  protect_from_gc(ref_dt);
  jl_datatype_t* alloc_dt = new_datatype(jl_symbol(allocname.c_str()), m_jl_mod, super, parameters, fnames, ftypes, 0, 1, 1);
  protect_from_gc(alloc_dt);

  // Register the type
  if(!is_parametric)
  {
    set_julia_type<T>(base_dt);
    add_default_constructor<T>(DefaultConstructible<T>(), base_dt);
    add_copy_constructor<T>(CopyConstructible<T>(), base_dt);
    static_type_mapping<T>::set_reference_type(ref_dt);
    static_type_mapping<T>::set_allocated_type(alloc_dt);
  }

#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 6
  m_jl_constants[name] = (jl_value_t*)base_dt;
  m_jl_constants[refname] = (jl_value_t*)ref_dt;
  m_jl_constants[allocname] = (jl_value_t*)alloc_dt;
#else
  m_jl_constants[name] = is_parametric ? base_dt->name->wrapper : (jl_value_t*)base_dt;
  m_jl_constants[refname] = is_parametric ? ref_dt->name->wrapper : (jl_value_t*)ref_dt;
  m_jl_constants[allocname] = is_parametric ? alloc_dt->name->wrapper : (jl_value_t*)alloc_dt;
#endif

  if(!is_parametric)
  {
    this->register_type_pair(ref_dt, alloc_dt);
  }

  if(!is_parametric && !std::is_same<supertype<T>,T>::value)
  {
    method("cxxdowncast", DownCast<T>::apply);
  }

  JL_GC_POP();
  return TypeWrapper<T>(*this, base_dt, ref_dt, alloc_dt);
}

/// Add a composite type
template<typename T, typename SuperParametersT>
TypeWrapper<T> Module::add_type(const std::string& name, jl_datatype_t* super)
{
  return add_type_internal<T, SuperParametersT>(name, super);
}

namespace detail
{
  template<typename T, bool>
  struct dispatch_set_julia_type;

  // non-parametric
  template<typename T>
  struct dispatch_set_julia_type<T, false>
  {
    void operator()(jl_datatype_t* dt)
    {
      set_julia_type<T>(dt);
    }
  };

  // parametric
  template<typename T>
  struct dispatch_set_julia_type<T, true>
  {
    void operator()(jl_datatype_t*)
    {
    }
  };
}

/// Add a bits type
template<typename T>
void Module::add_bits(const std::string& name, jl_datatype_t* super)
{
  static constexpr bool is_parametric = detail::IsParametric<T>::value;
  static_assert(IsBits<T>::value || is_parametric, "Bits types must be marked as such by specializing the IsBits template");
  static_assert(std::is_scalar<T>::value, "Bits types must be a scalar type");
  jl_svec_t* params = is_parametric ? parameter_list<T>()() : jl_emptysvec;
  JL_GC_PUSH1(&params);
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 6
  jl_datatype_t* dt = jl_new_bitstype((jl_value_t*)jl_symbol(name.c_str()), super, params, 8*sizeof(T));
#elif JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 7
  jl_datatype_t* dt = jl_new_primitivetype((jl_value_t*)jl_symbol(name.c_str()), super, params, 8*sizeof(T));
#else
  jl_datatype_t* dt = jl_new_primitivetype((jl_value_t*)jl_symbol(name.c_str()), m_jl_mod, super, params, 8*sizeof(T));
#endif
  protect_from_gc(dt);
  JL_GC_POP();
  detail::dispatch_set_julia_type<T, is_parametric>()(dt);
  m_jl_constants[name] = (jl_value_t*)dt;
}

/// Registry containing different modules
class JLCXX_API ModuleRegistry
{
public:

  ModuleRegistry(jl_module_t* parent_mod, jl_module_t* mod) : m_parent_mod(parent_mod), m_jl_mod(mod)
  {
  }

  /// Create a module and register it
  Module& create_module(const std::string& name);

  /// Loop over the modules
  template<typename F>
  void for_each_module(const F f) const
  {
    for(const auto& item : m_modules)
    {
      f(*item.second);
    }
  }

  Module& get_module(const std::string& name)
  {
    const auto iter = m_modules.find(name);
    if(iter == m_modules.end())
    {
      throw std::runtime_error("Module with name " + name + " was not found in registry");
    }

    return *(iter->second);
  }

private:
  std::map<std::string, std::shared_ptr<Module>> m_modules;
  jl_module_t* m_parent_mod;
  jl_module_t* m_jl_mod;
};

/// Registry for functions that are called when the CxxWrap module is initialized
class InitHooks
{
public:
  typedef std::function<void()> hook_t;

  // Singleton implementation
  static InitHooks& instance();

  // add a new hook
  void add_hook(const hook_t hook);

  // run all hooks
  void run_hooks();
private:
  InitHooks();
  std::vector<hook_t> m_hooks;
};

/// Helper to register a hook on library load
struct RegisterHook
{
  template<typename F>
  RegisterHook(F&& f)
  {
    InitHooks::instance().add_hook(InitHooks::hook_t(f));
  }
};

} // namespace jlcxx

#ifdef _WIN32
   #define JLCXX_ONLY_EXPORTS __declspec(dllexport)
#else
   #define JLCXX_ONLY_EXPORTS
#endif

/// Register a new module
#define JULIA_CPP_MODULE_BEGIN(registry) \
extern "C" JLCXX_ONLY_EXPORTS void register_julia_modules(void* void_reg) { \
  jlcxx::ModuleRegistry& registry = *reinterpret_cast<jlcxx::ModuleRegistry*>(void_reg); \
  try {

#define JULIA_CPP_MODULE_END } catch (const std::runtime_error& e) { jl_error(e.what()); } }

#endif
