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

#include <iostream>

#include "type_conversion.hpp"

namespace cpp_wrapper
{

/// Some helper functions
namespace detail
{

/// Call a C++ std::function, passed as a void pointer since it comes from Julia
template<typename R, typename... Args>
mapped_type<remove_const_ref<R>> call_functor(const void* functor, Args... args)
{
	auto std_func = reinterpret_cast<const std::function<R(Args...)>*>(functor);
	assert(std_func != nullptr);
	return convert_to_julia((*std_func)(args...));
}

/// Make a vector with the types in the variadic template parameter pack
template<typename... Args>
std::vector<std::type_index> typeid_vector()
{
	return {typeid(Args)...};
}

} // end namespace detail

/// Abstract base class for storing any function
class FunctionWrapperBase
{
public:
	/// Function pointer as void*, since that's what Julia expects
	virtual void* pointer() = 0;

	/// The thunk (i.e. std::function) to pass as first argument to the function pointed to by function_pointer
	virtual void* thunk() = 0;

	/// Types of the arguments
	virtual std::vector<std::type_index> argument_types() const = 0;

	/// Return type
	virtual std::type_index return_type() const = 0;

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

	virtual std::vector<std::type_index> argument_types() const
	{
		return detail::typeid_vector<Args...>();
	}

	virtual std::type_index return_type() const
	{
		return typeid(R);
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

	virtual std::vector<std::type_index> argument_types() const
	{
		return detail::typeid_vector<Args...>();
	}

	virtual std::type_index return_type() const
	{
		return typeid(R);
	}

private:
	R(*m_function)(Args...);
};

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
		m_functions[name].reset(new_wrapper);
	}

	/// Define a new function. Overload for pointers
	template<typename R, typename... Args>
	void def(const std::string& name,  R(*f)(Args...))
	{
		bool need_convert = !std::is_same<mapped_type<R>,R>::value;
		for(const bool b : {std::is_same<mapped_type<Args>,Args>::value...})
		{
			if(need_convert)
				break;
			need_convert = !b;
		}

		// Conversion is automatic when using the std::function calling method, so if we need conversion we use that
		if(need_convert)
		{
			def(name, std::function<R(Args...)>(f));
			return;
		}

		// No conversion needed -> call can be through a naked function pointer
		auto* new_wrapper = new FunctionPtrWrapper<R, Args...>(f);
		new_wrapper->set_name(name);
		m_functions[name].reset(new_wrapper);
	}

	/// Loop over the functions
	template<typename F>
	void for_each_function(const F f) const
	{
		for(const auto& item : m_functions)
		{
			f(*item.second);
		}
	}

	const std::string& name() const
	{
		return m_name;
	}

private:

	std::string m_name;
	std::map<std::string, std::unique_ptr<FunctionWrapperBase>> m_functions;
};

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
