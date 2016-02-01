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

/// Finalizer function for type T
template<typename T>
jl_value_t* finalizer(jl_value_t *F, jl_value_t **args, uint32_t nargs)
{
	jl_value_t* to_delete = args[0];

	T* stored_obj = convert_to_cpp<T*>(to_delete);
	if(stored_obj != nullptr)
	{
		delete stored_obj;
	}

	jl_set_nth_field(to_delete, 0, jl_box_voidpointer(nullptr));
}

/// Create a new julia object wrapping the C++ type
template<typename T, typename... ArgsT>
jl_value_t* create(ArgsT... args)
{
	static jl_function_t* finalizer_func = jl_new_closure(finalizer<T>, (jl_value_t*)jl_emptysvec, NULL);

	T* cpp_obj = new T(args...);
	jl_value_t* result = jl_new_struct(static_type_mapping<T>::julia_type(), jl_box_voidpointer(static_cast<void*>(cpp_obj)));
	jl_gc_add_finalizer(result, finalizer_func);

	return result;
}

} // end namespace detail

// The CppWrapper Julia module
extern jl_module_t* g_cpp_wrapper_module;
extern jl_datatype_t* g_cppclassinfo_type;
extern jl_datatype_t* g_cpptemplateclassinfo_type;
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

	template<typename T, typename... ArgsT>
	void add_parametric(const std::string& name, ArgsT... args);

	template<typename T, typename... ArgsT>
	void add_constructor()
	{
		def("call", std::function<jl_value_t*(SingletonType<T>, ArgsT...)>( [](SingletonType<T>, ArgsT... args) { return detail::create<T>(args...); }));
	}

	template<typename T>
	void apply();

	template<typename T, typename FunctorT>
	void apply(FunctorT&& f);

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

	void bind_types(jl_module_t* mod)
	{
		for(auto& dt_pair : m_jl_datatypes)
		{
			jl_set_const(mod, jl_symbol(dt_pair.first.c_str()), (jl_value_t*)dt_pair.second);
		}
	}

private:

	template<typename T>
	void add_default_constructor(std::true_type)
	{
		std::cout << "adding default constructor for type " << typeid(T).name() << std::endl;
		add_constructor<T>();
	}

	template<typename T>
	void add_default_constructor(std::false_type)
	{
	}

	template<typename T>
	void add_copy_constructor(std::true_type)
	{
		def("deepcopy_internal", std::function<jl_value_t*(const T&, ObjectIdDict)>( [this](const T& other, ObjectIdDict)
		{
			return detail::create<T>(other);
		}));
	}

	template<typename T>
	void add_copy_constructor(std::false_type)
	{
		def("deepcopy_internal", std::function<jl_value_t*(const T&, ObjectIdDict)>( [this](const T& other, ObjectIdDict)
		{
			throw std::runtime_error("Copy construction not supported for C++ type ");
			return nullptr;
		}));
	}

	std::string m_name;
	std::vector<std::unique_ptr<FunctionWrapperBase>> m_functions;
	std::vector<std::unique_ptr<TypeBase>> m_types;
	std::map<std::string, jl_datatype_t*> m_jl_datatypes;
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

/// Encapsulate a list of types, for the field list of a Julia composite type
template<typename... TypesT>
struct TypeList
{
	template<typename... StringT>
	TypeList(StringT... names)
	{
		static_assert(sizeof...(TypesT) == sizeof...(StringT), "Number of types must be equal to number of field names");
		field_names = {names...};
	}

	std::vector<std::string> field_names;
};

/// Wrap the base type
template<typename SuperT>
struct Super
{
	typedef SuperT type;
};

/// Represent a Julia TypeVar in the template parameter list
template<int I>
struct TypeVar
{
	static constexpr int value = I;

	static jl_tvar_t* tvar()
	{
		static jl_tvar_t* this_tvar = jl_new_typevar(jl_symbol((std::string("T") + std::to_string(I)).c_str()), (jl_value_t*)jl_bottom_type, (jl_value_t*)jl_any_type);
		return this_tvar;
	}

};

namespace detail
{

template<typename T, typename FunctorT>
void process_argument(FunctorT&&, T)
{
}

template<template<typename...> class ParameterT, typename FunctorT, typename... ParameterArgsT>
void process_argument(FunctorT&& f, ParameterT<ParameterArgsT...> arg)
{
	f(arg);
}

template<template<typename...> class ParameterT, typename FunctorT>
void process_arguments(FunctorT&&)
{
}

/// Look for a template ParameterT in the argument list
template<template<typename...> class ParameterT, typename FunctorT, typename ArgT, typename... OtherArgsT>
void process_arguments(FunctorT&& f, ArgT arg, OtherArgsT... other_args)
{
	process_argument<ParameterT>(f, arg);
	process_arguments<ParameterT>(f, other_args...);
}

template<typename T>
struct GetJlTypes
{
	static jl_datatype_t* julia_type()
	{
		return jl_any_type;
	}
};

template<typename... TypesT>
void build_type_vectors(const TypeList<TypesT...>& typelist, jl_svec_t*& fnames, jl_svec_t*& ftypes, int& ninitialized)
{
	static constexpr int nb_types = sizeof...(TypesT);
	ftypes = jl_svec(nb_types+1, jl_voidpointer_type, GetJlTypes<TypesT>::julia_type()...);
	fnames = jl_alloc_svec_uninit(nb_types+1);
	jl_svecset(fnames, 0, jl_symbol("cpp_object"));
	for(int i = 0; i != nb_types; ++i)
	{
		jl_svecset(fnames, i+1, jl_symbol(typelist.field_names[i].c_str()));
	}
	ninitialized = nb_types+1;
}

template<typename T>
struct ParametricTypeMapping;

template<template<typename...> class TemplateT, typename... TypesT>
struct ParametricTypeMapping<TemplateT<TypesT...>>
{
	static jl_datatype_t* julia_type()
	{
		return parametric_type_mapping<TemplateT>::julia_type();
	}

	static void set_julia_type(jl_datatype_t* dt)
	{
		parametric_type_mapping<TemplateT>::set_julia_type(dt);
	}
};

template<typename T>
struct SetParameters;

template<template<typename...> class T, typename... ParametersT>
struct SetParameters<T<ParametersT...>>
{
	void operator()(jl_svec_t*& parameters) const
	{
		parameters = jl_svec(sizeof...(ParametersT), ParametersT::tvar()...);
	}
};

template<typename T>
struct GetParameters;

template<template<typename...> class T, typename... ParametersT>
struct GetParameters<T<ParametersT...>>
{
	jl_svec_t* operator()()
	{
		return jl_svec(sizeof...(ParametersT), static_type_mapping<ParametersT>::julia_type()...);
	}
};

} // namespace detail

template<typename T, typename... ArgsT>
void Module::add_parametric(const std::string& name, ArgsT... args)
{
	if(m_jl_datatypes.count(name) > 0)
	{
		throw std::runtime_error("Duplicate registration of type " + name);
	}

	jl_datatype_t* super = nullptr;
	jl_svec_t* parameters = nullptr;
	jl_svec_t* fnames = nullptr;
	jl_svec_t* ftypes = nullptr;
	int abstract = 0;
	int mutabl = 1;
	int ninitialized = 0;

	JL_GC_PUSH4(super, parameters, fnames, ftypes);

	// Set the parameters
	detail::SetParameters<T>()(parameters);

	// Fill fnames and ftypes
	detail::process_arguments<TypeList>([&](auto typelist)
	{
		detail::build_type_vectors(typelist, fnames, ftypes, ninitialized);
	}, args...);

	if(fnames == nullptr)
	{
		assert(ftypes == nullptr);
		detail::build_type_vectors(TypeList<>(), fnames, ftypes, ninitialized);
	}

	detail::process_arguments<Super>([&](auto super_t) { super = static_type_mapping<decltype(super_t)>::julia_type(); });
	if(super == nullptr)
	{
		super = jl_any_type;
	}

	// Create the datatype associated with the parametric type
	jl_datatype_t* dt = jl_new_datatype(jl_symbol(name.c_str()), super, parameters, fnames, ftypes, abstract, mutabl, ninitialized);
	detail::ParametricTypeMapping<T>::set_julia_type(dt);

	m_jl_datatypes[name] = dt;
}

template<typename T>
void Module::apply()
{
	add_default_constructor<T>(std::is_default_constructible<T>());
	add_copy_constructor<T>(std::is_copy_constructible<T>());
	jl_datatype_t* app_dt = (jl_datatype_t*)jl_apply_type((jl_value_t*)detail::ParametricTypeMapping<T>::julia_type(), detail::GetParameters<T>()());
	static_type_mapping<T>::set_julia_type(app_dt);
}

template<typename T, typename FunctorT>
void Module::apply(FunctorT&& f)
{
	this->apply<T>();
	f(*this);
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
	std::map<std::string, std::unique_ptr<Module>> m_modules;
};


} // namespace cpp_wrapper

/// Register a new module
#define JULIA_CPP_MODULE_BEGIN(registry) \
extern "C" void register_julia_modules(void* void_reg) { \
	cpp_wrapper::ModuleRegistry& registry = *reinterpret_cast<cpp_wrapper::ModuleRegistry*>(void_reg);

#define JULIA_CPP_MODULE_END }

#endif
