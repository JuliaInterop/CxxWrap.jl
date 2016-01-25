#ifndef CPP_WRAPPER_HPP
#define CPP_WRAPPER_HPP

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

namespace cpp_wrapper
{

/// Some helper functions
namespace detail
{

// Need to treat void specially
template<typename R, typename... Args>
struct ReturnTypeAdapter
{
	inline mapped_type<remove_const_ref<R>> operator()(const void* functor, mapped_type<mapped_reference_type<Args>>... args)
	{
		auto std_func = reinterpret_cast<const std::function<R(Args...)>*>(functor);
		assert(std_func != nullptr);
		return convert_to_julia((*std_func)(convert_to_cpp<mapped_reference_type<Args>>(args)...));
	}
};

template<typename... Args>
struct ReturnTypeAdapter<void, Args...>
{
	inline void operator()(const void* functor, mapped_type<mapped_reference_type<Args>>... args)
	{
		auto std_func = reinterpret_cast<const std::function<void(Args...)>*>(functor);
		assert(std_func != nullptr);
		(*std_func)(convert_to_cpp<mapped_reference_type<Args>>(args)...);
	}
};

/// Call a C++ std::function, passed as a void pointer since it comes from Julia
template<typename R, typename... Args>
mapped_type<remove_const_ref<R>> call_functor(const void* functor, mapped_type<remove_const_ref<Args>>... args)
{
	try
	{
		return ReturnTypeAdapter<R, Args...>()(functor, args...);
	}
	catch(const std::runtime_error& err)
	{
		jl_error(err.what());
		return mapped_type<remove_const_ref<R>>();
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
		for(const bool b : {std::is_same<mapped_type<remove_const_ref<Args>>,remove_const_ref<Args>>::value...})
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

// The CppWrapper Julia module
extern jl_module_t* g_cpp_wrapper_module;
extern jl_datatype_t* g_cppclassinfo_type;
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
		return reinterpret_cast<void*>(&detail::call_functor<R, Args...>);
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

/// Base class for building a type
class TypeBase
{
public:
	virtual void bind_julia_type(jl_module_t* julia_module) const = 0;
	virtual ~TypeBase() {}
	/// Returns a Julia object of type CppClassInfo, providing all needed info to Julia to wrap the type
	virtual jl_value_t* type_descriptor() const = 0;

	/// Set the name of the base class to be assiciated with the Julia type. It defaults to CppAny if this is never called
	void set_base(const std::string& name)
	{
		m_base_name = name;
	}

protected:
	std::string m_base_name = "CppAny";
};

template<typename T, typename IsAbstract>
class Type;

/// Store all exposed C++ functions associated with a module
class Module
{
public:

	Module(const std::string& name);

	/// Define a new function
	template<typename R, typename... Args>
	void def(const std::string& name,  std::function<R(Args...)> f)
	{
		auto* new_wrapper = new FunctionWrapper<R, Args...>(f);
		new_wrapper->set_name(name);
		m_functions.resize(m_functions.size()+1);
		m_functions.back().reset(new_wrapper);
	}

	/// Define a new function. Overload for pointers
	template<typename R, typename... Args>
	void def(const std::string& name,  R(*f)(Args...))
	{
		bool need_convert = !std::is_same<mapped_type<remove_const_ref<R>>,remove_const_ref<R>>::value || detail::NeedConvertHelper<Args...>()();

		// Conversion is automatic when using the std::function calling method, so if we need conversion we use that
		if(need_convert)
		{
			def(name, std::function<R(Args...)>(f));
			return;
		}

		// No conversion needed -> call can be through a naked function pointer
		auto* new_wrapper = new FunctionPtrWrapper<R, Args...>(f);
		new_wrapper->set_name(name);
		m_functions.resize(m_functions.size()+1);
		m_functions.back().reset(new_wrapper);
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

	template<typename T, typename WrapperT>
	Type<T, std::false_type>& add_type(const std::string& name, WrapperT&& wrapper);

	template<typename T, typename WrapperT>
	Type<T, std::true_type>& add_abstract(const std::string& name, WrapperT&& wrapper);

	template<typename T, typename WrapperT>
	void add_parametric(const std::string& name, WrapperT&& wrapper);

	/// Loop over the types
	template<typename F>
	void for_each_type(const F f) const
	{
		for(const auto& item : m_types)
		{
			f(*item);
		}
	}

	unsigned int nb_types() const
	{
		return m_types.size();
	}

	const std::string& name() const
	{
		return m_name;
	}

private:

	std::string m_name;
	std::vector<std::unique_ptr<FunctionWrapperBase>> m_functions;
	std::vector<std::unique_ptr<TypeBase>> m_types;
};

template<typename... ParamsT>
struct TypeParameters
{
};

/// Define a new type
template<typename T, typename IsAbstract>
class Type : public TypeBase
{
public:
	Type(const std::string& name, Module& mod) : m_name(name), m_module(mod)
	{
		// Add default constructor if applicable
		static_dispatch_default_constructor(std::integral_constant<bool, std::is_default_constructible<T>::value && !IsAbstract::value>());
		// Add copy constructor if applicable
		static_dispatch_copy_constructor(std::integral_constant<bool, std::is_copy_constructible<T>::value && !IsAbstract::value>());

		// Pointer field to the C++ type
		static_dispatch_cpp_pointer_field(IsAbstract());
	}

	template<typename FieldT>
	void add_field(const std::string& name)
	{
		static_assert(!IsAbstract::value, "Can't add fields to an abstract type");
		if(!m_fields.insert(std::make_pair(name, static_type_mapping<FieldT>::julia_type)).second)
			throw std::runtime_error("Field with name " + name + " already existed");
	}

	// Static dispatch for default constructible classes
	void static_dispatch_default_constructor(std::true_type)
	{
		constructor<>();
	}
	void static_dispatch_default_constructor(std::false_type)
	{
	}

	// Static dispatch to add copy constructor as a deep_copy specialization
	void static_dispatch_copy_constructor(std::true_type)
	{
		m_module.def("deepcopy_internal", std::function<jl_value_t*(const T&, ObjectIdDict)>( [this](const T& other, ObjectIdDict)
		{
			return create(other);
		}));
	}
	void static_dispatch_copy_constructor(std::false_type)
	{
		m_module.def("deepcopy_internal", std::function<jl_value_t*(const T&, ObjectIdDict)>( [this](const T& other, ObjectIdDict)
		{
			throw std::runtime_error("Copy construction not supported for C++ type ");
			return nullptr;
		}));
	}

	// Static dispatch to add the cpp pointer field
	void static_dispatch_cpp_pointer_field(std::true_type)
	{
		// Do nothing if the type is abstract
	}

	void static_dispatch_cpp_pointer_field(std::false_type)
	{
		add_field<jl_value_t*>("cpp_object"); // Can be a pointer or an integer index
	}

	virtual void bind_julia_type(jl_module_t* julia_module) const
	{
		jl_set_const(julia_module, jl_symbol(m_name.c_str()), (jl_value_t*)static_type_mapping<T>::julia_type());
	}

	template<typename... ArgsT>
	Type<T, IsAbstract>& constructor()
	{
		m_module.def("call", std::function<jl_value_t*(SingletonType<T>, ArgsT...)>( [this](SingletonType<T>, ArgsT... args) { return create(args...); }));
		return *this;
	}

	template<typename R, typename... ArgsT>
	Type<T, IsAbstract>& def(const std::string& name, R(T::*f)(ArgsT...))
	{
		m_module.def(name, std::function<R(T&, ArgsT...)>([f](T& obj, ArgsT... args) { return (obj.*f)(args...); }) );
		return *this;
	}

	/// Create a new julia object wrapping the C++ type
	template<typename... ArgsT>
	jl_value_t* create(ArgsT... args)
	{
		static jl_function_t* finalizer_func = jl_new_closure(finalizer, (jl_value_t*)jl_emptysvec, NULL);

		T* cpp_obj = new T(args...);
		jl_value_t* result = jl_new_struct(static_type_mapping<T>::julia_type(), jl_box_voidpointer(static_cast<void*>(cpp_obj)));
		jl_gc_add_finalizer(result, finalizer_func);

		return result;
	}

	virtual jl_value_t* type_descriptor() const
	{
		Array<void*> field_types;
		Array<std::string> field_names;
		JL_GC_PUSH2(field_types.gc_pointer(), field_names.gc_pointer());
		for(const auto& field : m_fields)
		{
			field_names.push_back(field.first);
			field_types.push_back(reinterpret_cast<void*>(field.second));
		}

		jl_value_t* result =  jl_new_struct(g_cppclassinfo_type,
			convert_to_julia(m_name),
			jl_box_bool(IsAbstract::value),
			convert_to_julia(m_base_name),
			jl_box_voidpointer(reinterpret_cast<void*>(register_datatype)),
			field_types.wrapped(),
			field_names.wrapped()
		);

		JL_GC_POP();
		return result;
	}

	static jl_value_t* finalizer(jl_value_t *F, jl_value_t **args, uint32_t nargs)
	{
		jl_value_t* to_delete = args[0];
		delete_cpp(convert_to_cpp<T*>(to_delete));
		jl_set_nth_field(to_delete, 0, jl_box_voidpointer(nullptr));
	}

	static void delete_cpp(T* stored_obj)
	{
		if(stored_obj == nullptr)
		{
			return;
		}

		delete stored_obj;
	}

	static void register_datatype(jl_datatype_t* dt)
	{
		static_type_mapping<T>::set_julia_type(dt);
		static_type_mapping<T*>::set_julia_type(dt);
	}

private:
	const std::string m_name;
	Module& m_module;
	std::map<std::string, jl_datatype_t*(*)()> m_fields;
};

template<typename T, typename WrapperT>
Type<T, std::false_type>& Module::add_type(const std::string& name, WrapperT&& wrapper)
{
	m_types.resize(m_types.size()+1);
	auto* result = new Type<T,std::false_type>(name, *this);
	m_types.back().reset(result);
	wrapper(*result);
	return(*result);
}

template<typename T, typename WrapperT>
Type<T, std::true_type>& Module::add_abstract(const std::string& name, WrapperT&& wrapper)
{
	m_types.resize(m_types.size()+1);
	auto* result = new Type<T,std::true_type>(name, *this);
	m_types.back().reset(result);
	wrapper(*result);
	return *result;
}

namespace detail
{

struct ParametersEnd
{
};

template<typename T, typename... OtherTs>
struct AtParametersEnd
{
	static constexpr bool value = AtParametersEnd<OtherTs...>::value;
};

template<typename... OtherTs>
struct AtParametersEnd<ParametersEnd, OtherTs...>
{
	static constexpr bool value = true;
};

template<typename T>
struct AtParametersEnd<T>
{
	static constexpr bool value = false;
};

template<>
struct AtParametersEnd<ParametersEnd>
{
	static constexpr bool value = true;
};

template<typename T>
struct NextParameter
{
};

template<typename NextT, typename... OtherTypesT>
struct NextParameter<TypeParameters<NextT, OtherTypesT...>>
{
	typedef NextT type;
	typedef TypeParameters<OtherTypesT...> remaining_types;
};

template<typename NextT>
struct NextParameter<TypeParameters<NextT>>
{
	typedef NextT type;
	typedef ParametersEnd remaining_types;
};

template<typename T>
struct UnpackParameters
{
};

template<typename T1, typename... T2>
struct AssertEnd
{
	static constexpr bool value = std::is_same<T1, ParametersEnd>::value;
	static_assert(value, "Type parameter lists don't all have the same length");
	static_assert(AssertEnd<T2...>::value, "Type parameter lists don't all have the same length");
};

template<typename T>
struct AssertEnd<T>
{
	static constexpr bool value = std::is_same<T, ParametersEnd>::value;
	static_assert(value, "Type parameter lists don't all have the same length");
};

template<template<typename...> class WrappedT, typename... ParameterPacksT>
struct UnpackParameters<WrappedT<ParameterPacksT...>>
{
	typedef WrappedT<typename NextParameter<ParameterPacksT>::type...> type;
	typedef WrappedT<typename NextParameter<ParameterPacksT>::remaining_types...> remaining_types;

	// Wrap the actual type to create in a default-constructible wrapper, to pass more easily to the callback
	template<typename T>
	struct StoredType
	{
		typedef T type;
	};

	template<typename CallBackT>
	void operator()(CallBackT&& wrap_type)
	{
		wrap_type(StoredType<type>());
		dispatch(std::integral_constant<bool, AtParametersEnd<typename NextParameter<ParameterPacksT>::remaining_types...>::value>(), wrap_type);
	}

	template<typename CallBackT>
	void dispatch(std::true_type, CallBackT&& wrap_type)
	{
		detail::AssertEnd<typename NextParameter<ParameterPacksT>::remaining_types...>();
	}

	template<typename CallBackT>
	void dispatch(std::false_type, CallBackT&& wrap_type)
	{
		UnpackParameters<remaining_types>()(wrap_type);
	}
};

} // namespace detail

template<typename T, typename WrapperT>
void Module::add_parametric(const std::string& name, WrapperT&& wrapper)
{
	std::cout << "adding parametric type " << name << std::endl;
	detail::UnpackParameters<T>()([](auto stored_type)
	{
		typedef typename decltype(stored_type)::type concrete_type;
		std::cout << "got type " << typeid(concrete_type).name() << std::endl;
	});
	//m_types.resize(m_types.size()+1);
	//auto* result = new Type<T,std::true_type>(name, *this);
	//m_types.back().reset(result);
	//wrapper(*result);
}

template<typename T>
struct GetWrappedType
{
};

template<typename WrappedT, typename... OtherTs>
struct GetWrappedType<Type<WrappedT, OtherTs...>>
{
	typedef WrappedT type;
};

template<typename T> using get_wrappped_type = typename GetWrappedType<remove_const_ref<T>>::type;

/// Registry containing different modules
class ModuleRegistry
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

private:
	std::map<std::string, std::unique_ptr<Module>> m_modules;
};


} // namespace cpp_wrapper

/// Register a new module
#define JULIA_CPP_MODULE_BEGIN(registry) \
extern "C" void register_julia_modules(void* void_reg) { \
	cpp_wrapper::ModuleRegistry& registry = *reinterpret_cast<cpp_wrapper::ModuleRegistry*>(void_reg);

#define JULIA_CPP_MODULE_END }

#endif
