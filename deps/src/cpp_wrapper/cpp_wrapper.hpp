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
};

template<typename T, typename IsAbstract=std::false_type>
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

	template<typename T>
	Type<T>& add_type(const std::string& name);

	template<typename T>
	Type<T, std::true_type>& add_abstract(const std::string& name);

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

/// Define a new type
template<typename T, typename IsAbstract>
class Type : public TypeBase
{
public:
	Type(const std::string& name, Module& mod) : m_name(name), m_module(mod)
	{
		// Add default constructor if applicable
		static_dispatch_default_constructor(std::integral_constant<bool, std::is_default_constructible<T>::value && !IsAbstract::value>());

		// Add a manual destructor
		m_module.def("delete", delete_cpp);

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
		jl_value_t* result = jl_new_struct(static_type_mapping<T>::julia_type(), jl_box_uint64(detail::PointerMapping<T>::store(cpp_obj)), jl_box_uint64(typeid(T).hash_code()));
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
			jl_box_voidpointer(reinterpret_cast<void*>(get_super)),
			jl_box_voidpointer(reinterpret_cast<void*>(register_datatype)),
			field_types.wrapped(),
			field_names.wrapped()
		);

		JL_GC_POP();
		return result;
	}

	static jl_value_t* finalizer(jl_value_t *F, jl_value_t **args, uint32_t nargs)
	{
		delete_cpp(convert_to_cpp<T*>(args[0]));
	}

	static void delete_cpp(T* stored_obj)
	{
		if(stored_obj == nullptr)
		{
			return;
		}

		if(detail::PointerMapping<T>::erase(stored_obj))
		{
			delete stored_obj;
		}
	}

	static void register_datatype(jl_datatype_t* dt)
	{
		static_type_mapping<T>::set_julia_type(dt);
		static_type_mapping<T*>::set_julia_type(dt);
	}

	// TODO: Make this return the actual superclass
	static jl_datatype_t* get_super()
	{
		return static_type_mapping<CppAny>::julia_type();
	}

private:
	const std::string m_name;
	Module& m_module;
	std::map<std::string, jl_datatype_t*(*)()> m_fields;
};

template<typename T>
Type<T>& Module::add_type(const std::string& name)
{
	m_types.resize(m_types.size()+1);
	Type<T>* result = new Type<T>(name, *this);
	m_types.back().reset(result);
	return *result;
}

template<typename T>
Type<T, std::true_type>& Module::add_abstract(const std::string& name)
{
	m_types.resize(m_types.size()+1);
	Type<T, std::true_type>* result = new Type<T, std::true_type>(name, *this);
	m_types.back().reset(result);
	return *result;
}

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
