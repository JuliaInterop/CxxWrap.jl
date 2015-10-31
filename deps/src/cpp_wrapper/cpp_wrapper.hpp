#include <cassert>
#include <functional>
#include <map>
#include <memory>
#include <string>

extern "C"
{

void* get_function(const char* module_name, const char* function_name);
void* get_data(const char* module_name, const char* function_name);

}

namespace cpp_wrapper
{

/// Call a C++ std::function, passed as a void pointer since it comes from Julia
template<typename R, typename... Args>
R call_functor(const void* functor, Args... args)
{
	auto std_func = reinterpret_cast<const std::function<R(Args...)>*>(functor);
	assert(std_func != nullptr);
	return (*std_func)(args...);
}

/// Store all exposed C++ functions associated with a module
class module
{
private:

	/// Abstract base class for storing any function
	class function_wrapper_base
	{
	public:
		/// Function pointer as void*, since that's what Julia expects
		virtual void* function_pointer() = 0;

		/// The data (i.e. std::function) to pass as first argument to the function pointed to by function_pointer
		virtual void* data_pointer() = 0;
		virtual ~function_wrapper_base() {}
	};

	/// Implementation of function storage
	template<typename R, typename... Args>
	struct function_wrapper : public function_wrapper_base
	{
		typedef std::function<R(Args...)> functor_t;

		function_wrapper(const functor_t& function) : m_function(function)
		{
		}

		virtual void* function_pointer()
		{
			return reinterpret_cast<void*>(&call_functor<R, Args...>);
		}

		virtual void* data_pointer()
		{
			return reinterpret_cast<void*>(&m_function);
		}

		functor_t m_function;
	};

public:

	module(const std::string& name);

	/// Define a new function
	template<typename R, typename... Args>
	void def(const std::string& name,  std::function<R(Args...)> f)
	{
		m_functions[name].reset(new function_wrapper<R, Args...>(f));
	}

	/// Define a new function. Overload for pointers
	template<typename R, typename... Args>
	void def(const std::string& name,  R(*f)(Args...))
	{
		m_functions[name].reset(new function_wrapper<R, Args...>(std::function<R(Args...)>(f)));
	}

	void* get_function(const std::string& name);
	void* get_data(const std::string& name);

private:

	std::string m_name;
	std::map<std::string, std::unique_ptr<function_wrapper_base>> m_functions;
};

module& register_module(const std::string& name);

} // namespace cpp_wrapper
