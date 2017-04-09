#ifndef CXXWRAP_SMART_POINTER_HPP
#define CXXWRAP_SMART_POINTER_HPP

#include "type_conversion.hpp"

namespace cxx_wrap
{

template<typename T> struct IsSmartPointerType<std::shared_ptr<T>> : std::true_type { };
template<typename T> struct IsSmartPointerType<std::unique_ptr<T>> : std::true_type { };
template<typename T> struct IsSmartPointerType<std::weak_ptr<T>> : std::true_type { };

/// Override to indicate what smart pointer type is a valid constructor argument, e.g. shared_ptr can be used to construct a weak_ptr
template<typename T> struct ConstructorPointerType { typedef void type; };
template<typename T> struct ConstructorPointerType<std::weak_ptr<T>> { typedef std::shared_ptr<T> type; };

template<typename T>
struct DereferenceSmartPointer
{
  static WrappedCppPtr apply(void* smart_void_ptr)
  {
    auto smart_ptr = reinterpret_cast<T*>(smart_void_ptr);
    return {const_cast<void*>(static_cast<const void*>(&(**smart_ptr)))};
  }
};

// std::weak_ptr requires a call to lock()
template<typename T>
struct DereferenceSmartPointer<std::weak_ptr<T>>
{
  static WrappedCppPtr apply(void* smart_void_ptr)
  {
    auto smart_ptr = reinterpret_cast<std::weak_ptr<T>*>(smart_void_ptr);
    return {static_cast<void*>(smart_ptr->lock().get())};
  }
};

template<typename ToType, typename FromType> struct
ConstructFromOther
{
  static jl_value_t* apply(jl_value_t* smart_void_ptr)
  {
    if(jl_typeof(smart_void_ptr) != (jl_value_t*)julia_type<FromType>())
    {
      jl_error("Invalid smart pointer convert");
      return nullptr;
    }
    auto smart_ptr = unbox_wrapped_ptr<FromType>(smart_void_ptr);
    return boxed_cpp_pointer(new ToType(*smart_ptr), static_type_mapping<ToType>::julia_type(), true);
  }
};

template<typename ToType>
struct ConstructFromOther<ToType, void>
{
  static jl_value_t* apply(jl_value_t* smart_void_ptr)
  {
    jl_error("ConstructFromOther not available for this smart pointer type");
    return nullptr;
  }
};

// Conversion to base type
template<typename T>
struct ConvertToBase
{
  static jl_value_t* apply(void* smart_void_ptr)
  {
    static_assert(sizeof(T)==0, "No appropriate specialization for ConvertToBase");
  }
};

template<template<typename...> class PtrT, typename T>
struct ConvertToBase<PtrT<T>>
{
  static jl_value_t* apply(void* smart_void_ptr)
  {
    auto smart_ptr = reinterpret_cast<PtrT<T>*>(smart_void_ptr);
    if(std::is_same<T,supertype<T>>::value)
    {
      jl_error(("No compile-time type hierarchy specified. Specialize SuperType to get automatic pointer conversion from " + julia_type_name(julia_type<T>()) + " to its base.").c_str());
    }
    return boxed_cpp_pointer(new PtrT<supertype<T>>(*smart_ptr), static_type_mapping<PtrT<supertype<T>>>::julia_type(), true);
  }
};

template<typename T>
struct ConvertToBase<std::unique_ptr<T>>
{
  static jl_value_t* apply(void* smart_void_ptr)
  {
    jl_error("No convert to base for std::unique_ptr");
    return nullptr;
  }
};

inline jl_value_t* julia_smartpointer_type()
{
  static jl_value_t* m_ptr_type = (jl_value_t*)julia_type("SmartPointerWithDeref", "CxxWrap");
  return m_ptr_type;
}

namespace detail
{

template<typename PtrT, typename DefaultPtrT, typename T>
inline jl_datatype_t* smart_julia_type()
{
  static jl_datatype_t* result = nullptr;
  if(result == nullptr)
  {
    jl_value_t* type_hash = nullptr;
    jl_value_t* deref_ptr = nullptr;
    jl_value_t* construct_ptr = nullptr;
    jl_value_t* cast_ptr = nullptr;
    JL_GC_PUSH4(&type_hash, &deref_ptr, &construct_ptr, &cast_ptr);
    type_hash = box(typeid(DefaultPtrT).hash_code());
    deref_ptr = jl_box_voidpointer(reinterpret_cast<void*>(DereferenceSmartPointer<PtrT>::apply));
    construct_ptr = jl_box_voidpointer(reinterpret_cast<void*>(ConstructFromOther<PtrT, typename ConstructorPointerType<PtrT>::type>::apply));
    cast_ptr = jl_box_voidpointer(reinterpret_cast<void*>(ConvertToBase<PtrT>::apply));
    result = (jl_datatype_t*)apply_type(julia_smartpointer_type(), jl_svec(5, static_type_mapping<remove_const_ref<T>>::julia_type(), type_hash, deref_ptr, construct_ptr, cast_ptr));
    protect_from_gc(result);
    JL_GC_POP();
  }
  return result;
}

template<typename T>
struct SmartJuliaType;

template<template<typename...> class PtrT, typename T>
struct SmartJuliaType<PtrT<T>>
{
  static jl_datatype_t* apply()
  {
    return smart_julia_type<PtrT<T>,PtrT<int>,T>();
  }
};

template<template<typename...> class PtrT, typename T> struct SmartJuliaType<PtrT<const T>>
{
  static jl_datatype_t* apply() { return SmartJuliaType<PtrT<T>>::apply(); }
};

template<typename T>
struct SmartJuliaType<std::unique_ptr<T>>
{
  static jl_datatype_t* apply()
  {
    return smart_julia_type<std::unique_ptr<T>,std::unique_ptr<int>,T>();
  }
};

template<typename T>
struct SmartJuliaType<std::unique_ptr<const T>>
{
  static jl_datatype_t* apply() { return SmartJuliaType<std::unique_ptr<T>>::apply(); }
};

}

template<typename T> struct CXX_WRAP_EXPORT static_type_mapping<T, typename std::enable_if<IsSmartPointerType<T>::value>::type>
{
  typedef jl_value_t* type;
  static jl_datatype_t* julia_type()
  {
    return detail::SmartJuliaType<T>::apply();
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
    return *unbox_wrapped_ptr<T>(julia_val);
  }
};

}

#endif
