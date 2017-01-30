#ifndef TYPE_CONVERSION_HPP
#define TYPE_CONVERSION_HPP

#include <julia.h>
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR > 4
#include <julia_threads.h>
#endif

#include <map>
#include <memory>
#include <stack>
#include <stdexcept>
#include <string>
#include <typeinfo>
#include <typeindex>
#include <type_traits>
#include <iostream>

#ifdef _WIN32
  #define  CXX_WRAP_EXPORT __declspec(dllexport)
#else
   #define  CXX_WRAP_EXPORT
#endif

namespace cxx_wrap
{

namespace detail
{
  template<bool, typename T1, typename T2>
  struct StaticIf;

  // non-bits
  template<typename T1, typename T2>
  struct StaticIf<false, T1, T2>
  {
    typedef T2 type;
  };

  // bits type
  template<typename T1, typename T2>
  struct StaticIf<true, T1, T2>
  {
    typedef T1 type;
  };
}

CXX_WRAP_EXPORT jl_array_t* gc_protected();
CXX_WRAP_EXPORT std::stack<std::size_t>& gc_free_stack();
CXX_WRAP_EXPORT std::map<jl_value_t*, std::size_t>& gc_index_map();


template<typename T>
inline void protect_from_gc(T* val)
{
  JL_GC_PUSH1(&val);
  std::size_t pos = 0;
  if(gc_free_stack().empty())
  {
    pos = jl_array_len(gc_protected());
    jl_array_grow_end(gc_protected(), 1);
  }
  else
  {
    pos = gc_free_stack().top();
    gc_free_stack().pop();
  }
  jl_arrayset(gc_protected(), (jl_value_t*)(val), pos);
  gc_index_map()[(jl_value_t*)val] = pos;
  JL_GC_POP();
}

template<typename T>
inline void unprotect_from_gc(T* val)
{
  const auto found = gc_index_map().find((jl_value_t*)val);
  if(found == gc_index_map().end())
  {
    std::cout << "WARNING: attempt to unprotect a jl_value_t* that was never protected" << std::endl;
    return;
  }
  gc_free_stack().push(found->second);
  jl_arrayset(gc_protected(), jl_nothing, found->second);
  gc_index_map().erase(found);
}

/// Get the symbol name correctly depending on Julia version
inline std::string symbol_name(jl_sym_t* symbol)
{
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 5
  return std::string(symbol->name);
#else
  return std::string(jl_symbol_name(symbol));
#endif
}

/// Backwards-compatible apply_type
CXX_WRAP_EXPORT jl_value_t* apply_type(jl_value_t* tc, jl_svec_t* params);

/// Backwards-compatible apply_array_type
template<typename T>
inline jl_value_t* apply_array_type(T* type, std::size_t dim)
{
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 6
  return jl_apply_array_type((jl_datatype_t*)type, dim);
#else
  return jl_apply_array_type((jl_value_t*)type, dim);
#endif
}

/// Check if we have a string
inline bool is_julia_string(jl_value_t* v)
{
#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 5
  return jl_is_byte_string(v);
#else
  return jl_is_string(v);
#endif
}

inline const char* julia_string(jl_value_t* v)
{
  #if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 5
    return jl_bytestring_ptr(v);
  #else
    return jl_string_ptr(v);
  #endif
}

inline std::string julia_type_name(jl_datatype_t* dt)
{
  return jl_typename_str((jl_value_t*)dt);
}

/// Base type for all wrapped classes
struct CppAny
{
};

/// Trait to determine if a type is to be treated as a Julia immutable type that has isbits == true
template<typename T> struct IsImmutable : std::false_type {};

/// Trait to determine if the given type is to be treated as a bits type
template<typename T> struct IsBits : std::false_type {};

/// Remove reference and const from a type
template<typename T> using remove_const_ref = typename std::remove_const<typename std::remove_reference<T>::type>::type;

template<typename T>
struct IsFundamental
{
  static constexpr bool value = std::is_fundamental<remove_const_ref<T>>::value;
};

template<>
struct IsFundamental<void*>
{
  static constexpr bool value = true;
};

/// Trait to determine if the given type is to be treated as a value type, i.e. if the reference should be stripped when passed as argument
template<typename T> struct IsValueType
{
  static constexpr bool value = IsImmutable<T>::value || IsBits<T>::value || IsFundamental<T>::value;
};

namespace detail
{
  template<typename T>
  struct MappedReferenceType
  {
    typedef typename std::remove_const<T>::type type;
  };

  template<typename T>
  struct MappedReferenceType<T&>
  {
    typedef T& type;
  };

  template<typename T>
  struct MappedReferenceType<const T&>
  {
    typedef typename detail::StaticIf<IsValueType<T>::value, T, const T&>::type type;
  };
}

/// Remove reference and const from value types only, pass-through otherwise
template<typename T> using mapped_reference_type = typename detail::MappedReferenceType<T>::type;

/// Base class to specialize for conversion to C++
template<typename CppT, bool Fundamental=false, bool Immutable=false, bool Bits=false>
struct ConvertToCpp
{
  template<typename JuliaT>
  CppT* operator()(JuliaT&& julia_val) const
  {
    static_assert(sizeof(CppT)==0, "No appropriate specialization for ConvertToCpp");
    return nullptr; // not reached
  }
};

template<typename T> using cpp_converter_type = ConvertToCpp<T, IsFundamental<remove_const_ref<T>>::value, IsImmutable<remove_const_ref<T>>::value, IsBits<remove_const_ref<T>>::value>;

/// Conversion to C++
template<typename CppT, typename JuliaT>
inline CppT convert_to_cpp(const JuliaT& julia_val)
{
  return cpp_converter_type<CppT>()(julia_val);
}

namespace detail
{
  /// Equivalent of the basic C++ type layout in Julia
  struct WrappedCppPtr {
    JL_DATA_TYPE
    jl_value_t* voidptr;
  };

  /// Finalizer function for type T
  template<typename T>
  void finalizer(jl_value_t* to_delete)
  {
    T* stored_obj = convert_to_cpp<T*>(to_delete);
    if(stored_obj != nullptr)
    {
      delete stored_obj;
    }

    reinterpret_cast<WrappedCppPtr*>(to_delete)->voidptr = nullptr;
  }

  // Julia 0.4 version
  template<typename T>
  jl_value_t* finalizer_closure(jl_value_t *F, jl_value_t **args, uint32_t nargs)
  {
    finalizer<T>(args[0]);
    return nullptr;
  }

  template<typename T>
  struct unused_type
  {
  };

  template<typename T1, typename T2>
  struct DefineIfDifferent
  {
    typedef T1 type;
  };

  template<typename T>
  struct DefineIfDifferent<T,T>
  {
    typedef unused_type<T> type;
  };

template<typename T1, typename T2> using define_if_different = typename DefineIfDifferent<T1,T2>::type;
}

/// Static mapping base template
template<typename SourceT, typename Enable=void> struct CXX_WRAP_EXPORT static_type_mapping
{
  typedef typename detail::StaticIf<IsBits<remove_const_ref<SourceT>>::value, remove_const_ref<SourceT>, jl_value_t*>::type type;

  static jl_datatype_t* julia_type()
  {
    if(type_pointer() == nullptr)
    {
      throw std::runtime_error("Type " + std::string(typeid(SourceT).name()) + " has no Julia wrapper");
    }
    return type_pointer();
  }

  static jl_datatype_t* julia_instantiable_type()
  {
    if(type_pointer() == nullptr)
    {
      throw std::runtime_error("Type " + std::string(typeid(SourceT).name()) + " has no Julia wrapper");
    }
    if(jl_is_abstracttype(type_pointer()))
    {
      // A default instantiable type should be auto-created for each abstract type
      assert(instantiable_type_pointer());
      return instantiable_type_pointer();
    }
    return type_pointer();
  }

  static void set_julia_type(jl_datatype_t* dt)
  {
    if(type_pointer() != nullptr)
    {
      throw std::runtime_error("Type " + std::string(typeid(SourceT).name()) + " was already registered");
    }
    type_pointer() = dt;
    SetFinalizer<SourceT>()();
  }

  static void set_instantiable_julia_type(jl_datatype_t* dt)
  {
    instantiable_type_pointer() = dt;
  }

  template<typename BareT>
  struct SetFinalizer
  {
    void operator()()
    {
      #if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 5
            finalizer_pointer() = jl_new_closure(detail::finalizer_closure<BareT>, (jl_value_t*)jl_emptysvec, NULL);
      #else
            finalizer_pointer() = jl_box_voidpointer((void*)detail::finalizer<BareT>);
      #endif
            protect_from_gc(finalizer_pointer());
    }
  };

  template<typename BareT>
  struct SetFinalizer<BareT*>
  {
    void operator()()
    {
    }
  };

  static jl_function_t* finalizer()
  {
    if(type_pointer() == nullptr)
    {
      throw std::runtime_error("Type " + std::string(typeid(SourceT).name()) + " has no finalizer");
    }
    return finalizer_pointer();
  }

  static bool has_julia_type()
  {
    return type_pointer() != nullptr;
  }

private:
  static jl_datatype_t*& type_pointer()
  {
    static jl_datatype_t* m_type_pointer = nullptr;
    return m_type_pointer;
  }

  static jl_datatype_t*& instantiable_type_pointer()
  {
    static jl_datatype_t* m_instantiable_type_pointer = nullptr;
    return m_instantiable_type_pointer;
  }

  static jl_function_t*& finalizer_pointer()
  {
    static jl_function_t* m_finalizer = nullptr;
    return m_finalizer;
  }
};

/// Automatically register pointer types
template<typename T>
void set_julia_type(jl_datatype_t* dt)
{
  static_type_mapping<T>::set_julia_type(dt);
  if(!IsImmutable<T>::value && !IsBits<T>::value)
  {
    static_type_mapping<T*>::set_julia_type(dt);
    static_type_mapping<const T*>::set_julia_type(dt);
  }
}

/// Helper for Singleton types (Type{T} in Julia)
template<typename T>
struct SingletonType
{
};

template<typename T> struct IsValueType<SingletonType<T>> : std::true_type {};

template<typename T>
struct static_type_mapping<SingletonType<T>>
{
  typedef jl_datatype_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_type((jl_value_t*)jl_type_type, jl_svec1(static_type_mapping<T>::julia_type())); }
};


namespace detail
{
  // Helper to deal with references
  template<typename T>
  struct JuliaReferenceMapping
  {
    typedef static_type_mapping<T> type;
  };

  template<typename T>
  struct JuliaReferenceMapping<T&>
  {
    typedef typename StaticIf<IsFundamental<T>::value, static_type_mapping<T&>, static_type_mapping<T>>::type type;
  };

  template<typename T>
  struct JuliaReferenceMapping<const T&>
  {
    typedef static_type_mapping<T> type;
  };

  template<typename T>
  struct JuliaReferenceMapping<const T>
  {
    typedef static_type_mapping<T> type;
  };
}

template<typename SourceT> using dereferenced_type_mapping = typename detail::JuliaReferenceMapping<SourceT>::type;
template<typename SourceT> using mapped_julia_type = typename dereferenced_type_mapping<SourceT>::type;

/// Specializations

// Needed for Visual C++, static members are different in each DLL
extern "C" CXX_WRAP_EXPORT jl_datatype_t* get_any_type(); // Implemented in c_interface.cpp
extern "C" CXX_WRAP_EXPORT jl_module_t* get_cxxwrap_module();
template<> struct CXX_WRAP_EXPORT static_type_mapping<CppAny>
{
  typedef jl_value_t* type;
  static jl_datatype_t* julia_type() { return get_any_type(); }
};

template<> struct static_type_mapping<void>
{
  typedef void type;
  static jl_datatype_t* julia_type() { return jl_void_type; }
};

template<> struct static_type_mapping<bool>
{
  typedef bool type;
  static jl_datatype_t* julia_type() { return jl_bool_type; }
};

template<> struct static_type_mapping<double>
{
  typedef double type;
  static jl_datatype_t* julia_type() { return jl_float64_type; }
};

template<> struct static_type_mapping<float>
{
  typedef float type;
  static jl_datatype_t* julia_type() { return jl_float32_type; }
};

template<> struct static_type_mapping<int32_t*>
{
  typedef jl_array_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_array_type(jl_int32_type, 1); }
};

template<> struct static_type_mapping<int64_t*>
{
  typedef jl_array_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_array_type(jl_int64_type, 1); }
};

template<> struct static_type_mapping<char*>
{
  typedef jl_array_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_array_type(jl_uint8_type, 1); }
};

template<> struct static_type_mapping<unsigned char*>
{
  typedef jl_array_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_array_type(jl_uint8_type, 1); }
};

template<> struct static_type_mapping<float*>
{
  typedef jl_array_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_array_type(jl_float32_type, 1); }
};

template<> struct static_type_mapping<double*>
{
  typedef jl_array_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_array_type(jl_float64_type, 1); }
};

template<> struct static_type_mapping<short>
{
  static_assert(sizeof(short) == 2, "short is expected to be 16 bits");
  typedef short type;
  static jl_datatype_t* julia_type() { return jl_int16_type; }
};

template<> struct static_type_mapping<int>
{
  static_assert(sizeof(int) == 4, "int is expected to be 32 bits");
  typedef int type;
  static jl_datatype_t* julia_type() { return jl_int32_type; }
};

template<> struct static_type_mapping<unsigned int>
{
  static_assert(sizeof(unsigned int) == 4, "unsigned int is expected to be 32 bits");
  typedef unsigned int type;
  static jl_datatype_t* julia_type() { return jl_uint32_type; }
};

template<> struct static_type_mapping<unsigned char>
{
  typedef unsigned char type;
  static jl_datatype_t* julia_type() { return jl_uint8_type; }
};

template<> struct static_type_mapping<int64_t>
{
  typedef int64_t type;
  static jl_datatype_t* julia_type() { return jl_int64_type; }
};

template<> struct static_type_mapping<uint64_t>
{
  typedef uint64_t type;
  static jl_datatype_t* julia_type() { return jl_uint64_type; }
};

template<> struct static_type_mapping<detail::define_if_different<long, int64_t>>
{
  static_assert(sizeof(long) == 8 || sizeof(long) == 4, "long is expected to be 64 bits or 32 bits");
  typedef long type;
  static jl_datatype_t* julia_type() { return sizeof(long) == 8 ? jl_int64_type : jl_int32_type; }
};

template<> struct static_type_mapping<detail::define_if_different<long long, int64_t>>
{
  static_assert(sizeof(long long) == 8, " long long is expected to be 64 bits or 32 bits");
  typedef long long type;
  static jl_datatype_t* julia_type() { return jl_int64_type; }
};

template<> struct static_type_mapping<detail::define_if_different<unsigned long, uint64_t>>
{
  static_assert(sizeof(unsigned long) == 8 || sizeof(unsigned long) == 4, "unsigned long is expected to be 64 bits or 32 bits");
  typedef unsigned long type;
  static jl_datatype_t* julia_type() { return sizeof(unsigned long) == 8 ? jl_uint64_type : jl_uint32_type; }
};

template<> struct IsValueType<std::string> : std::true_type {};
template<> struct static_type_mapping<std::string>
{
  typedef jl_value_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)jl_get_global(jl_base_module, jl_symbol("AbstractString")); }
};

template<> struct static_type_mapping<const char*>
{
  typedef jl_value_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)jl_get_global(jl_base_module, jl_symbol("AbstractString")); }
};

template<> struct static_type_mapping<void*>
{
  typedef void* type;
  static jl_datatype_t* julia_type() { return jl_voidpointer_type; }
};

template<> struct static_type_mapping<jl_datatype_t*>
{
  typedef jl_datatype_t* type; // Debatable if this should be jl_value_t*
  static jl_datatype_t* julia_type() { return jl_datatype_type; }
};

template<> struct static_type_mapping<jl_value_t*>
{
  typedef jl_value_t* type;
  static jl_datatype_t* julia_type() { return jl_any_type; }
};

#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 5
template<> struct static_type_mapping<jl_function_t*>
{
  typedef jl_function_t* type;
  static jl_datatype_t* julia_type() { return jl_any_type; }
};
#endif

// Helper for ObjectIdDict
struct ObjectIdDict {};

template<> struct IsValueType<ObjectIdDict> : std::true_type {};

template<> struct static_type_mapping<ObjectIdDict>
{
  typedef jl_value_t* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)jl_get_global(jl_base_module, jl_symbol("ObjectIdDict")); }
};

/// Base class to specialize for conversion to Julia
template<typename T, bool Fundamental=false, bool Immutable=false, bool Bits=false>
struct ConvertToJulia
{
  template<typename CppT>
  jl_value_t* operator()(CppT&& cpp_val) const
  {
    static_assert(sizeof(T)==0, "No appropriate specialization for ConvertToJulia");
    return nullptr; // not reached
  }
};

// Fundamental type
template<typename T>
struct ConvertToJulia<T, true, false, false>
{
  T operator()(const T& cpp_val) const
  {
    return cpp_val;
  }
};

// Non-const reference to fundamental type
template<typename T>
struct ConvertToJulia<T&, true, false, false>
{
  T* operator()(T& cpp_val) const
  {
    return &cpp_val;
  }
};

// Boxed immutable type
template<typename T>
struct ConvertToJulia<T, false, true, false>
{
  template<typename T2>
  jl_value_t* operator()(T2&& cpp_val) const
  {
    return jl_new_bits((jl_value_t*)static_type_mapping<T>::julia_type(), &cpp_val);
  }
};

// isbits immutable
template<typename T>
struct ConvertToJulia<T, false, true, true>
{
  T operator()(const T& cpp_val) const
  {
    return cpp_val;
  }
};

// Bits type
template<typename T>
struct ConvertToJulia<T, false, false, true>
{
  T operator()(const T& cpp_val) const
  {
    return cpp_val;
  }
};

// Pointer to wrapped type
template<typename T>
struct ConvertToJulia<T*, false, false, false>
{
  jl_value_t* operator()(T* cpp_obj) const
  {
    jl_datatype_t* dt = static_type_mapping<typename std::remove_const<T>::type>::julia_instantiable_type();
    assert(!jl_isbits(dt));

    jl_value_t* result = nullptr;
    jl_value_t* void_ptr = nullptr;
    JL_GC_PUSH2(&result, &void_ptr);
    void_ptr = jl_box_voidpointer(static_cast<void*>(const_cast<typename std::remove_const<T>::type*>(cpp_obj)));
    result = jl_new_struct(dt, void_ptr);
    assert(convert_to_cpp<T*>(result) == cpp_obj);
    JL_GC_POP();
    return result;
  }
};

// Reference to wrapped type
template<typename T>
struct ConvertToJulia<T&, false, false, false>
{
  jl_value_t* operator()(T& cpp_obj) const
  {
    return ConvertToJulia<T*, false, false, false>()(&cpp_obj);
  }
};

template<>
struct ConvertToJulia<std::string, false, false, false>
{
  jl_value_t* operator()(const std::string& str) const
  {
    return jl_cstr_to_string(str.c_str());
  }
};

template<>
struct ConvertToJulia<std::string*, false, false, false>
{
  jl_value_t* operator()(const std::string* str) const
  {
    return ConvertToJulia<std::string, false, false, false>()(*str);
  }
};

template<>
struct ConvertToJulia<const std::string*, false, false, false>
{
  jl_value_t* operator()(const std::string* str) const
  {
    return ConvertToJulia<std::string, false, false, false>()(*str);
  }
};

template<>
struct ConvertToJulia<const char*, false, false, false>
{
  jl_value_t* operator()(const char* str) const
  {
    return jl_cstr_to_string(str);
  }
};

template<>
struct ConvertToJulia<void*, false, false, false>
{
  jl_value_t* operator()(void* p) const
  {
    return jl_box_voidpointer(p);
  }
};

template<>
struct ConvertToJulia<jl_value_t*, false, false, false>
{
  jl_value_t* operator()(jl_value_t* p) const
  {
    return p;
  }
};

template<>
struct ConvertToJulia<jl_datatype_t*, false, false, false>
{
  jl_datatype_t* operator()(jl_datatype_t* p) const
  {
    return p;
  }
};

namespace detail
{
  template<typename T>
  struct StrippedConversionType
  {
    typedef mapped_reference_type<T> type;
  };

  template<typename T>
  struct StrippedConversionType<T*&>
  {
    typedef T* type;
  };

  template<typename T>
  struct StrippedConversionType<T* const &>
  {
    typedef T* type;
  };
}

template<typename T> using julia_converter_type = ConvertToJulia<typename detail::StrippedConversionType<T>::type, IsFundamental<remove_const_ref<T>>::value, IsImmutable<remove_const_ref<T>>::value, IsBits<remove_const_ref<T>>::value>;

/// Conversion to the statically mapped target type.
template<typename T>
inline auto convert_to_julia(T&& cpp_val) -> decltype(julia_converter_type<T>()(cpp_val))
{
  return julia_converter_type<T>()(std::forward<T>(cpp_val));
}

template<typename T>
inline jl_value_t* convert_to_julia(std::unique_ptr<T> cpp_val);

// Pass-through for already boxed types
template<typename CppT>
inline typename std::enable_if<!IsBits<CppT>::value, jl_value_t*>::type box(const CppT& cpp_val)
{
  return (jl_value_t*)convert_to_julia(cpp_val);
}

// Generic bits type conversion
template<typename CppT>
inline typename std::enable_if<IsBits<remove_const_ref<CppT>>::value, jl_value_t*>::type box(CppT&& cpp_val)
{
  return jl_new_bits((jl_value_t*)static_type_mapping<remove_const_ref<CppT>>::julia_type(), &cpp_val);
}

template<>
inline jl_value_t* box(const bool& b)
{
  return jl_box_bool(b);
}

template<>
inline jl_value_t* box(const int32_t& i)
{
  return jl_box_int32(i);
}

template<>
inline jl_value_t* box(const int64_t& i)
{
  return jl_box_int64(i);
}

template<>
inline jl_value_t* box(const uint32_t& i)
{
  return jl_box_uint32(i);
}

template<>
inline jl_value_t* box(const uint64_t& i)
{
  return jl_box_uint64(i);
}

template<>
inline jl_value_t* box(const float& x)
{
  return jl_box_float32(x);
}

template<>
inline jl_value_t* box(const double& x)
{
  return jl_box_float64(x);
}

namespace detail
{
  inline jl_value_t* box_long(long x)
  {
    return jl_box_long(x);
  }

  inline jl_value_t* box_long(unused_type<long>)
  {
    // never called
    return nullptr;
  }
}

template<>
inline jl_value_t* box(const detail::define_if_different<long, int64_t>& x)
{
  return detail::box_long(x);
}



// Unbox boxed type
template<typename CppT>
inline CppT unbox(jl_value_t* v)
{
  static_assert(sizeof(CppT) == 0, "Unimplemented unbox in cxx_wrap");
}

template<>
inline bool unbox(jl_value_t* v)
{
  return jl_unbox_bool(v);
}

template<>
inline float unbox(jl_value_t* v)
{
  return jl_unbox_float32(v);
}

template<>
inline double unbox(jl_value_t* v)
{
  return jl_unbox_float64(v);
}

template<>
inline int32_t unbox(jl_value_t* v)
{
  return jl_unbox_int32(v);
}

template<>
inline int64_t unbox(jl_value_t* v)
{
  return jl_unbox_int64(v);
}

template<>
inline uint32_t unbox(jl_value_t* v)
{
  return jl_unbox_uint32(v);
}

template<>
inline uint64_t unbox(jl_value_t* v)
{
  return jl_unbox_uint64(v);
}

template<>
inline void* unbox(jl_value_t* v)
{
  return jl_unbox_voidpointer(v);
}

// Fundamental type conversion
template<typename CppT>
struct ConvertToCpp<CppT, true, false, false>
{
  template<typename JuliaT>
  CppT operator()(JuliaT&& julia_val) const
  {
    return julia_val;
  }

  CppT operator()(jl_value_t* julia_val) const
  {
    return unbox<CppT>(julia_val);
  }
};

// Non-const reference to fundamental type
template<typename CppT>
struct ConvertToCpp<CppT&, true, false, false>
{
  CppT& operator()(CppT* julia_val) const
  {
    return *julia_val;
  }
};

// Boxed immutable conversion
template<typename CppT>
struct ConvertToCpp<CppT, false, true, false>
{
  CppT operator()(jl_value_t* julia_value) const
  {
    return *reinterpret_cast<CppT*>(jl_data_ptr(julia_value));
  }
};

// Immutable-as-bits conversion
template<typename CppT>
struct ConvertToCpp<CppT, false, true, true>
{
  CppT operator()(const CppT julia_value) const
  {
    return julia_value;
  }
};

namespace detail
{

// Unpack based on reference or pointer target type
// Try to dereference by default
template<typename T>
struct DoUnpack
{
  template<typename CppT>
  T operator()(CppT* ptr)
  {
    if(ptr == nullptr)
    {
      throw std::runtime_error("C++ object was deleted");
    }

    return *ptr;
  }
};

// Return the pointer if a pointer was passed
template<typename T>
struct DoUnpack<T*>
{
  template<typename CppT>
  T* operator()(CppT* ptr)
  {
    return ptr;
  }
};

template<typename T>
struct DoUnpack<T*&&>
{
  template<typename CppT>
  T* operator()(CppT* ptr)
  {
    return ptr;
  }
};

/// Helper class to unpack a julia type
template<typename CppT>
struct JuliaUnpacker
{
  // The C++ type stripped of all pointer, reference, const
  typedef typename std::remove_const<typename std::remove_pointer<remove_const_ref<CppT>>::type>::type stripped_cpp_t;

  CppT operator()(jl_value_t* julia_value)
  {
    return DoUnpack<CppT>()(extract_cpp_pointer(julia_value));
  }

  /// Convert the void pointer in the julia structure to a C++ pointer, asserting that the type is correct
  static stripped_cpp_t* extract_cpp_pointer(jl_value_t* julia_value)
  {
    assert(julia_value != nullptr);
    jl_datatype_t* dt = static_type_mapping<stripped_cpp_t>::julia_type();
    assert(jl_type_morespecific(jl_typeof(julia_value), (jl_value_t*)dt));

    if(!jl_isbits(dt))
    {
      //Get the pointer to the C++ class
      return reinterpret_cast<stripped_cpp_t*>(jl_data_ptr(reinterpret_cast<WrappedCppPtr*>(julia_value)->voidptr));
    }
    else
    {
      throw std::runtime_error("Attempt to convert a bits type as a struct");
    }
  }
};

} // namespace detail

// Bits type conversion
template<typename CppT>
struct ConvertToCpp<CppT, false, false, true>
{
  // Boxed variant
  CppT operator()(jl_value_t* julia_value) const
  {
    return *reinterpret_cast<CppT*>(jl_data_ptr(julia_value));
  }

  // Direct variant
  CppT operator()(const CppT julia_value) const
  {
    return julia_value;
  }
};

// Generic conversion for C++ classes wrapped in a composite type
template<typename CppT>
struct ConvertToCpp<CppT, false, false, false>
{
  CppT operator()(jl_value_t* julia_value) const
  {
    return detail::JuliaUnpacker<CppT>()(julia_value);
  }

  // pass-through for Julia pointers
  template<typename JuliaPtrT>
  JuliaPtrT* operator()(JuliaPtrT* julia_value) const
  {
    return julia_value;
  }
};


// pass-through for jl_value_t*
template<>
struct ConvertToCpp<jl_value_t*, false, false, false>
{
  jl_value_t* operator()(jl_value_t* julia_value) const
  {
    return julia_value;
  }
};

#if JULIA_VERSION_MAJOR == 0 && JULIA_VERSION_MINOR < 5
// pass-through for jl_function_t*
template<>
struct ConvertToCpp<jl_function_t*, false, false, false>
{
  jl_function_t* operator()(jl_function_t* julia_value) const
  {
    return julia_value;
  }
};
#endif

// strings
template<>
struct ConvertToCpp<const char*, false, false, false>
{
  const char* operator()(jl_value_t* jstr) const
  {
    if(jstr == nullptr || !is_julia_string(jstr))
    {
      throw std::runtime_error("Any type to convert to string is not a string but a " + julia_type_name((jl_datatype_t*)jl_typeof(jstr)));
    }
    return julia_string(jstr);
  }
};

template<>
struct ConvertToCpp<std::string, false, false, false>
{
  std::string operator()(jl_value_t* jstr) const
  {
    return std::string(ConvertToCpp<const char*, false, false, false>()(jstr));
  }
};


template<>
struct ConvertToCpp<char*, false, false, false>
{
  char* operator()(jl_array_t* julia_array) const
  {
    return (char*)jl_array_data(julia_array);
  }
};

template<>
struct ConvertToCpp<unsigned char*, false, false, false>
{
  unsigned char* operator()(jl_array_t* julia_array) const
  {
    return (unsigned char*)jl_array_data(julia_array);
  }
};

template<>
struct ConvertToCpp<int32_t*, false, false, false>
{
  int32_t* operator()(jl_array_t* julia_array) const
  {
    return (int32_t*)jl_array_data(julia_array);
  }
};

template<>
struct ConvertToCpp<int64_t*, false, false, false>
{
  int64_t* operator()(jl_array_t* julia_array) const
  {
    return (int64_t*)jl_array_data(julia_array);
  }
};

template<>
struct ConvertToCpp<float*, false, false, false>
{
  float* operator()(jl_array_t* julia_array) const
  {
    return (float*)jl_array_data(julia_array);
  }
};

template<>
struct ConvertToCpp<double*, false, false, false>
{
  double* operator()(jl_array_t* julia_array) const
  {
    return (double*)jl_array_data(julia_array);
  }
};

template<typename T>
struct ConvertToCpp<SingletonType<T>, false, false, false>
{
  SingletonType<T> operator()(jl_datatype_t* julia_value) const
  {
    return SingletonType<T>();
  }
};

// Used for deepcopy_internal overloading
template<>
struct ConvertToCpp<ObjectIdDict, false, false, false>
{
  ObjectIdDict operator()(jl_value_t*) const
  {
    return ObjectIdDict();
  }
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

template<int I> struct IsValueType<TypeVar<I>> : std::true_type {};

template<int I>
struct static_type_mapping<TypeVar<I>>
{
  typedef jl_tvar_t* type;
  static jl_tvar_t* julia_type() { return TypeVar<I>::tvar(); }
};

/// Convenience function to get the julia data type associated with T
template<typename T>
inline jl_datatype_t* julia_type()
{
  return static_type_mapping<T>::julia_type();
}

/// Get the type from a global symbol
CXX_WRAP_EXPORT jl_datatype_t* julia_type(const std::string& name, const std::string& module_name = "");

/// Helper to encapsulate a strictly typed number type. Numbers typed like this will not be involved in the convenience-overloads that allow passing e.g. an Int to a Float64 argument
template<typename NumberT>
struct StrictlyTypedNumber
{
  NumberT value;
};

template<typename NumberT> struct IsBits<StrictlyTypedNumber<NumberT>> : std::true_type {};

template<typename NumberT> struct static_type_mapping<StrictlyTypedNumber<NumberT>>
{
  typedef NumberT type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_type((jl_value_t*)::cxx_wrap::julia_type("StrictlyTypedNumber"), jl_svec1(static_type_mapping<NumberT>::julia_type())); }
};

template<typename NumberT>
struct ConvertToCpp<StrictlyTypedNumber<NumberT>, false, false, true>
{
  inline StrictlyTypedNumber<NumberT> operator()(NumberT julia_value) const
  {
    return {julia_value};
  }
};

// Match references to fundamental types (e.g. double&)
template<typename T> struct static_type_mapping<T&, typename std::enable_if<IsFundamental<T>::value>::type>
{
  typedef T* type;
  static jl_datatype_t* julia_type() { return (jl_datatype_t*)apply_type((jl_value_t*)::cxx_wrap::julia_type("Ref"), jl_svec1(static_type_mapping<T>::julia_type())); }
};

}

#endif
