#ifndef FUNCTIONS_HPP
#define FUNCTIONS_HPP

#include <sstream>

#include "type_conversion.hpp"

// This header provides helper functions to call Julia functions from C++

namespace cxx_wrap
{

/// Get a Julia function pointer from the given function name. Searches the current module by default, otherwise the module with the provided name
/// Returns null if the function does not exist, throws if the module does not exist
CXX_WRAP_EXPORT jl_function_t* julia_function(const std::string& name, const std::string& module_name = "");

namespace detail
{
  struct StoreArgs
  {
    StoreArgs(jl_value_t** arg_array) : m_arg_array(arg_array)
    {
    }

    template<typename ArgT, typename... ArgsT>
    void push(ArgT&& a, ArgsT... args)
    {
      push(a);
      push(args...);
    }

    template<typename ArgT>
    void push(ArgT&& a)
    {
      m_arg_array[m_i++] = convert_to_julia(a);
    }

    void push() {}

    jl_value_t** m_arg_array;
    int m_i = 0;
  };
}

/// Call a julia function, converting the arguments to the corresponding Julia types
/// ArgumentsT is a standard container filled with the arguments
template<typename... ArgumentsT>
jl_value_t* julia_call(jl_function_t* f, ArgumentsT&&... args)
{
  const int nb_args = sizeof...(args);

  jl_value_t* result = nullptr;
  jl_value_t** julia_args;
  JL_GC_PUSH1(&result);
  JL_GC_PUSHARGS(julia_args, nb_args);

  // Process arguments
  detail::StoreArgs store_args(julia_args);
  store_args.push(args...);
  for(int i = 0; i != nb_args; ++i)
  {
    if(julia_args[i] == nullptr)
    {
      JL_GC_POP();
      JL_GC_POP();
      std::stringstream sstr;
      sstr << "Unsupported Julia function argument type at position " << i;
      throw std::runtime_error(sstr.str());
    }
  }

  // Do the call
  result = jl_call(f, julia_args, nb_args);
  if (jl_exception_occurred())
  {
    jl_show(jl_stderr_obj(), jl_exception_occurred());
    jl_printf(jl_stderr_stream(), "\n");
    JL_GC_POP();
    JL_GC_POP();
    return nullptr;
  }

  JL_GC_POP();
  JL_GC_POP();
  return result;
}

}

#endif
