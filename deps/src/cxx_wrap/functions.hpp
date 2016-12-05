#ifndef FUNCTIONS_HPP
#define FUNCTIONS_HPP

#include <sstream>
#include <vector>

#include "array.hpp"
#include "type_conversion.hpp"

// This header provides helper functions to call Julia functions from C++

namespace cxx_wrap
{

/// Get a Julia function pointer from the given function name. Searches the current module by default, otherwise the module with the provided name
/// Throws if the module or the function does not exist
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
      m_arg_array[m_i++] = box(a);
    }

    void push() {}

    jl_value_t** m_arg_array;
    int m_i = 0;
  };
}

/// Call a julia function, converting the arguments to the corresponding Julia types
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
    jlbacktrace();
    JL_GC_POP();
    JL_GC_POP();
    return nullptr;
  }

  JL_GC_POP();
  JL_GC_POP();
  return result;
}

/// Data corresponds to immutable with the same name on the Julia side
struct SafeCFunctionData
{
  void* fptr;
  jl_datatype_t* return_type;
  jl_array_t* argtypes;
};

namespace detail
{
  template<typename SignatureT>
  struct SplitSignature;

  template<typename R, typename... ArgsT>
  struct SplitSignature<R(ArgsT...)>
  {
    typedef R return_type;
    typedef R(*fptr_t)(ArgsT...);

    std::vector<jl_datatype_t*> operator()()
    {
      return std::vector<jl_datatype_t*>({julia_type<ArgsT>()...});
    }

    fptr_t cast_ptr(void* ptr)
    {
      return reinterpret_cast<fptr_t>(ptr);
    }
  };
}

/// Type-checking on return type and arguments of a cfunction (void* pointer)
template<typename SignatureT>
class SafeCFunction
{
  typedef detail::SplitSignature<SignatureT> SplitterT;
public:
  SafeCFunction(SafeCFunctionData data)
  {
    JL_GC_PUSH3(&data.fptr, &data.return_type, &data.argtypes);
    // protect_from_gc(data.fptr); // not needed?
    m_fptr = SplitterT().cast_ptr(data.fptr);

    jl_datatype_t* expected_rt = julia_type<typename SplitterT::return_type>();
    if(expected_rt != data.return_type)
    {
      JL_GC_POP();
      throw std::runtime_error("Incorrect datatype for cfunction return type, expected " + julia_type_name(expected_rt) + " but got " + julia_type_name(data.return_type));
    }
    const std::vector<jl_datatype_t*> expected_argstypes = SplitterT()();
    ArrayRef<jl_value_t*> argtypes(data.argtypes);
    const int nb_args = expected_argstypes.size();
    if(nb_args != argtypes.size())
    {
      std::stringstream err_sstr;
      err_sstr << "Incorrect number of arguments for cfunction, expected: " << nb_args << ", obtained: " << argtypes.size();
      JL_GC_POP();
      throw std::runtime_error(err_sstr.str());
    }
    for(int i = 0; i != nb_args; ++i)
    {
      jl_datatype_t* argt = (jl_datatype_t*)argtypes[i];
      if(argt != expected_argstypes[i])
      {
        std::stringstream err_sstr;
        err_sstr << "Incorrect argument type for cfunction at position " << i+1 << ", expected: " << julia_type_name(expected_argstypes[i]) << ", obtained: " << julia_type_name(argt);
        JL_GC_POP();
        throw std::runtime_error(err_sstr.str());
      }
    }
    JL_GC_POP();
  }

  ~SafeCFunction()
  {
    //unprotect_from_gc(m_fptr); // not needed?
  }

  /// Call the function
  template<typename... Args>
  typename SplitterT::return_type operator()(Args&&... args) const
  {
    return m_fptr(std::forward<Args>(args)...);
  }

  /// Access to the pointer
  typename SplitterT::fptr_t pointer() const
  {
    return m_fptr;
  }

private:
  typename SplitterT::fptr_t m_fptr;
};

template<typename SignatureT> struct IsImmutable<SafeCFunction<SignatureT>> : std::true_type {};

/// Implicit conversion from SafeCFunctionData to a SafeCFunction
template<typename SignatureT> struct static_type_mapping<SafeCFunction<SignatureT>>
{
  typedef SafeCFunctionData type;
  static jl_datatype_t* julia_type() { return cxx_wrap::julia_type("SafeCFunctionData"); }
  template<typename T> using remove_const_ref = cxx_wrap::remove_const_ref<T>;
};

template<typename SignatureT>
struct ConvertToCpp<SafeCFunction<SignatureT>, false, true, false>
{
  SafeCFunction<SignatureT> operator()(const SafeCFunctionData& julia_value) const
  {
    return SafeCFunction<SignatureT>(julia_value);
  }
};

}

#endif
