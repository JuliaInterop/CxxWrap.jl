#ifndef CXXWRAP_SMART_POINTER_HPP
#define CXXWRAP_SMART_POINTER_HPP

#include "type_conversion.hpp"

namespace cxx_wrap
{

template<typename T> struct IsSmartPointerType<std::shared_ptr<T>> : std::true_type { };
template<typename T> struct IsSmartPointerType<std::unique_ptr<T>> : std::true_type { };

inline jl_value_t* julia_smartpointer_type()
{
  static jl_value_t* m_ptr_type = (jl_value_t*)julia_type("SmartPointerWithDeref", "CxxWrap");
  return m_ptr_type;
}

template<typename T>
struct DereferenceSmartPointer
{
  static WrappedCppPtr dereference_smart_pointer(void* smart_void_ptr)
  {
    auto smart_ptr = reinterpret_cast<T*>(smart_void_ptr);
    return {static_cast<void*>(&(**smart_ptr))};
  }
};

template<template<typename...> class PtrT, typename T> struct static_type_mapping<PtrT<T>, typename std::enable_if<IsSmartPointerType<PtrT<T>>::value>::type>
{
  typedef jl_value_t* type;
  static jl_datatype_t* julia_type()
  {
    static jl_datatype_t* result = nullptr;
    if(result == nullptr)
    {
      jl_value_t* deref_ptr = nullptr;
      JL_GC_PUSH1(&deref_ptr);
      deref_ptr = jl_box_voidpointer(reinterpret_cast<void*>(DereferenceSmartPointer<PtrT<T>>::dereference_smart_pointer));
      result = (jl_datatype_t*)apply_type(julia_smartpointer_type(), jl_svec2(static_type_mapping<T>::julia_type(), deref_ptr));
      protect_from_gc(result);
      JL_GC_POP();
    }
    return result;
  }
};

template<typename T>
struct ConvertToJulia<T, false, false, false, typename std::enable_if<IsSmartPointerType<T>::value>::type>
{
  jl_value_t* operator()(T cpp_val) const
  {
    return boxed_cpp_pointer(new T(std::move(cpp_val)), static_type_mapping<T>::julia_type(), true);
  }
};

template<typename T>
struct ConvertToCpp<T, false, false, false, typename std::enable_if<IsSmartPointerType<T>::value>::type>
{
  T operator()(jl_value_t* julia_val) const
  {
    return *julia_cast<T>(julia_val);
  }
};

}

#endif
