#ifndef CXX_WRAP_HPP
#define CXX_WRAP_HPP

#include <cassert>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <typeinfo>
#include <typeindex>
#include <vector>

#include "array.hpp"
#include "type_conversion.hpp"

namespace cxx_wrap
{

/// Some helper functions
namespace detail
{

// Need to treat void specially
template<typename R, typename... Args>
struct ReturnTypeAdapter
{
	inline mapped_julia_type<remove_const_ref<R>> operator()(const void* functor, mapped_julia_type<mapped_reference_type<Args>>... args)
	{
		auto std_func = reinterpret_cast<const std::function<R(Args...)>*>(functor);
		assert(std_func != nullptr);
		return convert_to_julia((*std_func)(convert_to_cpp<mapped_reference_type<Args>>(args)...));
	}
};

template<typename... Args>
struct ReturnTypeAdapter<void, Args...>
{
	inline void operator()(const void* functor, mapped_julia_type<mapped_reference_type<Args>>... args)
	{
		auto std_func = reinterpret_cast<const std::function<void(Args...)>*>(functor);
		assert(std_func != nullptr);
		(*std_func)(convert_to_cpp<mapped_reference_type<Args>>(args)...);
	}
};

/// Call a C++ std::function, passed as a void pointer since it comes from Julia
template<typename R, typename... Args>
mapped_julia_type<remove_const_ref<R>> call_functor(const void* functor, mapped_julia_type<remove_const_ref<Args>>... args)
{
	try
	{
		return ReturnTypeAdapter<R, Args...>()(functor, args...);
	}
	catch(const std::runtime_error& err)
	{
		jl_error(err.what());
		return mapped_julia_type<remove_const_ref<R>>();
	}
}

/// Make a vector with the types in the variadic template parameter pack
template<typename... Args>
std::vector<jl_datatype_t*> typeid_vector()
{
  return {static_type_mapping<remove_const_ref<Args>>::julia_type()...};
}

template<typename... Args>
struct NeedConvertHelper
{
	bool operator()()
	{
		for(const bool b : {std::is_same<mapped_julia_type<remove_const_ref<Args>>,remove_const_ref<Args>>::value...})
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

template<bool>
struct CreateChooser
{};

// Normal types
template<>
struct CreateChooser<false>
{
	template<typename T, typename... ArgsT>
	static jl_value_t* create(SingletonType<T>, ArgsT&&... args)
	{
		jl_datatype_t* dt = static_type_mapping<T>::julia_type();
		assert(!jl_isbits(dt));

		T* cpp_obj = new T(std::forward<ArgsT>(args)...);

		jl_value_t* result = convert_to_julia(cpp_obj);
		JL_GC_PUSH1(&result);
		jl_gc_add_finalizer(result, static_type_mapping<T>::finalizer());
		JL_GC_POP();

		assert(convert_to_cpp<T*>(result) == cpp_obj);
		return result;
	}
};

// Immutable-as-bits types
template<>
struct CreateChooser<true>
{
	template<typename T, typename... ArgsT>
	static jl_value_t* create(SingletonType<T>, ArgsT&&... args)
	{
		assert(jl_isbits(static_type_mapping<T>::julia_type()));
		T result(std::forward<ArgsT>(args)...);
		return convert_to_julia(result);
	}
};

/// Convenience function to create an object with a finalizer attached
template<typename T, typename... ArgsT>
jl_value_t* create(ArgsT&&... args)
{
	return CreateChooser<IsImmutable<T>::value>::create(SingletonType<T>(), std::forward<ArgsT>(args)...);
}

// The CxxWrap Julia module
extern jl_module_t* g_cxx_wrap_module;
extern jl_datatype_t* g_cppfunctioninfo_type;

/// Abstract base class for storing any function
class FunctionWrapperBase
{
public:
	/// Function pointer as void*, since that's what Julia expects
	virtual void* pointer() = 0;

	/// The thunk (i.e. std::function) to pass as first argument to the function pointed to by function_pointer
	virtual void* thunk() = 0;

	/// Types of the arguments
	virtual std::vector<jl_datatype_t*> argument_types() const = 0;

	/// Return type
	virtual jl_datatype_t* return_type() const = 0;

	virtual ~FunctionWrapperBase() {}

	inline void set_name(const std::string& name)
	{
		m_name = name;
	}

	inline const std::string& name() const
	{
		return m_name;
	}

private:
	std::string m_name;
};

/// Implementation of function storage, case of std::function
template<typename R, typename... Args>
class FunctionWrapper : public FunctionWrapperBase
{
public:
	typedef std::function<R(Args...)> functor_t;

	FunctionWrapper(const functor_t& function) : m_function(function)
	{
	}

	virtual void* pointer()
	{
		return reinterpret_cast<void*>(detail::call_functor<R, Args...>);
	}

	virtual void* thunk()
	{
		return reinterpret_cast<void*>(&m_function);
	}

	virtual std::vector<jl_datatype_t*> argument_types() const
	{
		return detail::typeid_vector<Args...>();
	}

	virtual jl_datatype_t* return_type() const
	{
		return static_type_mapping<R>::julia_type();
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

	FunctionPtrWrapper(R(*f)(Args...)) : m_function(f)
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
		return detail::typeid_vector<Args...>();
	}

	virtual jl_datatype_t* return_type() const
	{
		return static_type_mapping<R>::julia_type();
	}

private:
	R(*m_function)(Args...);
};

/// Encapsulate a list of fields, for the field list of a Julia composite type
template<typename... TypesT>
struct FieldList
{
	template<typename... StringT>
	FieldList(StringT... names)
	{
		static_assert(sizeof...(TypesT) == sizeof...(StringT), "Number of types must be equal to number of field names");
		field_names = jl_svec(sizeof...(TypesT), jl_symbol(names)...);
	}

	jl_svec_t* field_names;
};

/// Indicate that a parametric type is to be added
template<typename... ParametersT>
struct Parametric
{
};

/// Represent a Julia TypeVar in the template parameter list
template<int I>
struct TypeVar
{
	static constexpr int value = I;

	static jl_tvar_t* tvar()
	{
		static jl_tvar_t* this_tvar = build_tvar();
		return this_tvar;
	}

	static jl_tvar_t* build_tvar()
	{
		jl_tvar_t* result = jl_new_typevar(jl_symbol((std::string("T") + std::to_string(I)).c_str()), (jl_value_t*)jl_bottom_type, (jl_value_t*)jl_any_type);
		protect_from_gc(result);
		return result;
	}
};

template<typename T>
class TypeWrapper;

/// Store all exposed C++ functions associated with a module
class CXX_WRAP_EXPORT Module
{
public:

	Module(const std::string& name);

	/// Define a new function
	template<typename R, typename... Args>
	void method(const std::string& name,  std::function<R(Args...)> f)
	{
		auto* new_wrapper = new FunctionWrapper<R, Args...>(f);
		new_wrapper->set_name(name);
		m_functions.resize(m_functions.size()+1);
		m_functions.back().reset(new_wrapper);
	}

	/// Define a new function. Overload for pointers
	template<typename R, typename... Args>
	void method(const std::string& name,  R(*f)(Args...), const bool force_convert = false)
	{
		bool need_convert = force_convert || !std::is_same<mapped_julia_type<R>,remove_const_ref<R>>::value || detail::NeedConvertHelper<Args...>()();

		// Conversion is automatic when using the std::function calling method, so if we need conversion we use that
		if(need_convert)
		{
			method(name, std::function<R(Args...)>(f));
			return;
		}

		// No conversion needed -> call can be through a naked function pointer
		auto* new_wrapper = new FunctionPtrWrapper<R, Args...>(f);
		new_wrapper->set_name(name);
		m_functions.resize(m_functions.size()+1);
		m_functions.back().reset(new_wrapper);
	}

	/// Define a new function. Overload for lambda
	template<typename LambdaT>
	void method(const std::string& name,  LambdaT&& lambda)
	{
		add_lambda(name, lambda, &LambdaT::operator());
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
	template<typename T>
	TypeWrapper<T> add_type(const std::string& name, jl_datatype_t* super = julia_type<CppAny>());

	/// Add an abstract type
	template<typename T, typename... ArgsT>
	TypeWrapper<T> add_abstract(const std::string& name, jl_datatype_t* super = julia_type<CppAny>());

	/// Add type T as a struct that can be captured as bits type, using an immutable in Julia
	template<typename T, typename FieldListT>
	TypeWrapper<T> add_immutable(const std::string& name, FieldListT&& field_list, jl_datatype_t* super = julia_type<CppAny>());

	template<typename T>
	TypeWrapper<T> add_bits(const std::string& name, jl_datatype_t* super = julia_type<CppAny>());

	const std::string& name() const
	{
		return m_name;
	}

	void bind_types(jl_module_t* mod)
	{
		for(auto& dt_pair : m_jl_datatypes)
		{
			jl_set_const(mod, jl_symbol(dt_pair.first.c_str()), (jl_value_t*)dt_pair.second);
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

private:

	template<typename T>
	void add_default_constructor(std::true_type, jl_datatype_t* dt = nullptr);

	template<typename T>
	void add_default_constructor(std::false_type, jl_datatype_t* dt = nullptr)
	{
	}

	template<typename T>
	void add_copy_constructor(std::true_type, jl_datatype_t* dt = nullptr)
	{
		method("deepcopy_internal", [this](const T& other, ObjectIdDict)
		{
			return CreateChooser<IsImmutable<T>::value>::create(SingletonType<T>(), other);
		});
	}

	template<typename T>
	void add_copy_constructor(std::false_type, jl_datatype_t* dt = nullptr)
	{
		method("deepcopy_internal", [this](const T& other, ObjectIdDict)
		{
			throw std::runtime_error("Copy construction not supported for C++ type ");
			return static_cast<jl_value_t*>(nullptr);
		});
	}

	template<typename T, bool AddBits, typename FieldListT=FieldList<>>
	TypeWrapper<T> add_type_internal(const std::string& name, jl_datatype_t* super, int abstract, FieldListT&& = FieldList<>());

	template<typename R, typename LambdaRefT, typename LambdaT, typename... ArgsT>
	void add_lambda(const std::string& name, LambdaRefT&& lambda, R(LambdaT::*f)(ArgsT...) const)
	{
		method(name, std::function<R(ArgsT...)>(lambda));
	}

	std::string m_name;
	std::vector<std::shared_ptr<FunctionWrapperBase>> m_functions;
	std::map<std::string, jl_datatype_t*> m_jl_datatypes;
  std::vector<std::string> m_exported_symbols;

	template<class T> friend class TypeWrapper;
};

namespace detail
{

template<typename T>
void add_smart_pointer_types(jl_datatype_t* dt, Module& mod)
{
	jl_datatype_t* sp_dt = (jl_datatype_t*)jl_apply_type(jl_get_global(get_cxxwrap_module(), jl_symbol("SharedPtr")), jl_svec1(static_type_mapping<T>::julia_type()));
	static_type_mapping<std::shared_ptr<T>>::set_julia_type(sp_dt);
	static_type_mapping<std::shared_ptr<T>*>::set_julia_type(sp_dt);
	jl_datatype_t* up_dt = (jl_datatype_t*)jl_apply_type(jl_get_global(get_cxxwrap_module(), jl_symbol("UniquePtr")), jl_svec1(static_type_mapping<T>::julia_type()));
	static_type_mapping<std::unique_ptr<T>>::set_julia_type(up_dt);
	static_type_mapping<std::unique_ptr<T>*>::set_julia_type(up_dt);

	mod.method("get", [](const std::shared_ptr<T>& ptr)
	{
		return ptr.get();
	});
	mod.method("get", [](const std::unique_ptr<T>& ptr)
	{
		return ptr.get();
	});
}

}

template<typename T>
void Module::add_default_constructor(std::true_type, jl_datatype_t* dt)
{
	TypeWrapper<T>(*this, dt).template constructor<>();
}

namespace detail
{

template<typename T>
struct GetJlType
{
	jl_datatype_t* operator()() const
	{
		return julia_type<T>();
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

template<typename... ParametersT>
struct IsParametric<Parametric<ParametersT...>>
{
	static constexpr int nb_parameters = 0;
	static constexpr bool value = true;
};

} // namespace detail

// Encapsulate a list of parameters, using types only
template<typename... ParametersT>
struct ParameterList
{
  static constexpr int nb_parameters = sizeof...(ParametersT);

	jl_svec_t* operator()()
	{
		return jl_svec(sizeof...(ParametersT), detail::GetJlType<ParametersT>()()...);
	}
};

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

/// Helper class to wrap type methods
template<typename T>
class TypeWrapper
{
public:
	typedef T type;

	TypeWrapper(Module& mod, jl_datatype_t* dt) : m_module(mod), m_dt(dt)
	{
	}

	/// Add a constructor with the given argument types
	template<typename... ArgsT>
	TypeWrapper<T>& constructor()
	{
		m_module.method("call", [](SingletonType<T>, ArgsT... args) { return create<T>(args...); });
		return *this;
	}

	/// Define a member function
	template<typename R, typename CT, typename... ArgsT>
	TypeWrapper<T>& method(const std::string& name, R(CT::*f)(ArgsT...))
	{
		m_module.method(name, [f](T& obj, ArgsT... args) { return (obj.*f)(args...); } );
		return *this;
	}

	/// Define a member function, const version
	template<typename R, typename CT, typename... ArgsT>
	TypeWrapper<T>& method(const std::string& name, R(CT::*f)(ArgsT...) const)
	{
		m_module.method(name, [f](const T& obj, ArgsT... args) { return (obj.*f)(args...); } );
		return *this;
	}

	template<typename... AppliedTypesT, typename FunctorT>
	TypeWrapper<T>& apply(FunctorT&& apply_ftor)
	{
		static_assert(detail::IsParametric<T>::value, "Apply can only be called on parametric types");
		auto dummy = {apply_internal<AppliedTypesT>(std::forward<FunctorT>(apply_ftor))...};
		return *this;
	}

	// Access to the module
	Module& module()
	{
		return m_module;
	}

private:

	template<typename AppliedT, typename FunctorT>
	int apply_internal(FunctorT&& apply_ftor)
	{
		static_assert(parameter_list<AppliedT>::nb_parameters != 0, "No parameters found when applying type. Specialize cxx_wrap::BuildParameterList for your combination of type and non-type parameters.");
		static_assert(parameter_list<AppliedT>::nb_parameters == parameter_list<T>::nb_parameters, "Parametric type applied to wrong number of parameters.");
		jl_datatype_t* app_dt = (jl_datatype_t*)jl_apply_type((jl_value_t*)m_dt, parameter_list<AppliedT>()());

		static_type_mapping<AppliedT>::set_julia_type(app_dt);
		m_module.add_default_constructor<AppliedT>(std::is_default_constructible<AppliedT>(), app_dt);
		if(!IsImmutable<AppliedT>::value)
		{
			m_module.add_copy_constructor<AppliedT>(std::is_copy_constructible<AppliedT>(), app_dt);
			static_type_mapping<AppliedT*>::set_julia_type(app_dt);
			detail::add_smart_pointer_types<AppliedT>(app_dt, m_module);
		}

		apply_ftor(TypeWrapper<AppliedT>(m_module, app_dt));

		return 0;
	}
	Module& m_module;
	jl_datatype_t* m_dt;
};

template<typename T, bool AddBits, typename FieldListT>
TypeWrapper<T> Module::add_type_internal(const std::string& name, jl_datatype_t* super, int abstract, FieldListT&& field_list)
{
	static constexpr bool is_parametric = detail::IsParametric<T>::value;
	static_assert(((!IsImmutable<T>::value && !AddBits) || AddBits) || is_parametric, "Immutable types (marked with IsImmutable) can't be added using add_type, use add_immutable instead");
	static_assert(((std::is_standard_layout<T>::value && AddBits) || !AddBits) || is_parametric, "Immutable types must be standard layout");
	static_assert(((IsImmutable<T>::value && AddBits) || !AddBits) || is_parametric, "Immutable types must be marked as such by specializing the IsImmutable template");
	if(m_jl_datatypes.count(name) > 0)
	{
		throw std::runtime_error("Duplicate registration of type " + name);
	}

	jl_svec_t* parameters = nullptr;
	jl_svec_t* fnames = nullptr;
	jl_svec_t* ftypes = nullptr;
	JL_GC_PUSH4(&super, &parameters, &fnames, &ftypes);

	parameters = is_parametric ? parameter_list<T>()() : jl_emptysvec;
	fnames = AddBits ? field_list.field_names : jl_svec1(jl_symbol("cpp_object"));
	ftypes = AddBits ? parameter_list<FieldListT>()() : jl_svec1(jl_voidpointer_type);
	int mutabl = !AddBits;
	int ninitialized = jl_svec_len(ftypes);

	assert(jl_svec_len(ftypes) == jl_svec_len(fnames));

	// Create the datatype
	jl_datatype_t* dt = jl_new_datatype(jl_symbol(name.c_str()), super, parameters, fnames, ftypes, abstract, mutabl, ninitialized);
	protect_from_gc(dt);

	// Register the type
	if(!is_parametric)
	{
		static_type_mapping<T>::set_julia_type(dt);
		if(!AddBits)
		{
			static_type_mapping<T*>::set_julia_type(dt);
		}
		if(!abstract)
		{
			add_default_constructor<T>(std::is_default_constructible<T>());
			if(!AddBits)
			{
				add_copy_constructor<T>(std::is_copy_constructible<T>());
				detail::add_smart_pointer_types<T>(dt, *this);
			}
		}
	}

	m_jl_datatypes[name] = dt;
	JL_GC_POP();
	return TypeWrapper<T>(*this, dt);
}

/// Add a composite type
template<typename T>
TypeWrapper<T> Module::add_type(const std::string& name, jl_datatype_t* super)
{
	return add_type_internal<T, false>(name, super, 0);
}

/// Add an abstract type
template<typename T, typename... ArgsT>
TypeWrapper<T> Module::add_abstract(const std::string& name, jl_datatype_t* super)
{
	return add_type_internal<T, false>(name, super, 1);
}

/// Add type T as a struct that can be captured as bits type, using an immutable in Julia
template<typename T, typename FieldListT>
TypeWrapper<T> Module::add_immutable(const std::string& name, FieldListT&& field_list, jl_datatype_t* super)
{
	return add_type_internal<T, true>(name, super, 0, std::forward<FieldListT>(field_list));
}

/// Add a bits type
template<typename T>
TypeWrapper<T> Module::add_bits(const std::string& name, jl_datatype_t* super)
{
	static_assert(IsBits<T>::value, "Bits types must be marked as such by specializing the IsBits template");
	static_assert(std::is_standard_layout<T>::value, "Bits types must be standard layout");
	jl_datatype_t* dt = jl_new_bitstype((jl_value_t*)jl_symbol(name.c_str()), super, jl_emptysvec, 8*sizeof(T));
	protect_from_gc(dt);
	static_type_mapping<T>::set_julia_type(dt);
	m_jl_datatypes[name] = dt;
	return TypeWrapper<T>(*this, dt);
}

/// Registry containing different modules
class CXX_WRAP_EXPORT ModuleRegistry
{
public:
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
};

// Smart pointers

// Shared pointer
template<typename T>
struct ConvertToJulia<std::shared_ptr<T>, false, false, false>
{
  jl_value_t* operator()(const std::shared_ptr<T>& cpp_obj) const
  {
    return create<std::shared_ptr<T>>(cpp_obj);
  }
};

// Unique Ptr
template<typename T>
inline jl_value_t* convert_to_julia(std::unique_ptr<T> cpp_val)
{
	return create<std::unique_ptr<T>>(std::move(cpp_val));
}

/// Get the type from a global symbol
jl_datatype_t* julia_type(const std::string& name);

} // namespace cxx_wrap

/// Register a new module
#define JULIA_CPP_MODULE_BEGIN(registry) \
extern "C" CXX_WRAP_EXPORT void register_julia_modules(void* void_reg) { \
	cxx_wrap::ModuleRegistry& registry = *reinterpret_cast<cxx_wrap::ModuleRegistry*>(void_reg);

#define JULIA_CPP_MODULE_END }

#endif
