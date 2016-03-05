#ifndef TYPE_CONVERSION_HPP
#define TYPE_CONVERSION_HPP

#include <julia.h>

#include <map>
#include <stdexcept>
#include <string>
#include <typeinfo>
#include <typeindex>
#include <type_traits>

#include <iostream>

namespace cpp_wrapper
{

extern jl_array_t* g_gc_protected;

template<typename T>
void protect_from_gc(T* val)
{
	jl_cell_1d_push(g_gc_protected, (jl_value_t*)val);
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

inline std::string julia_type_name(jl_datatype_t* dt)
{
	return symbol_name(dt->name->name);
}

/// Helper to easily remove a ref to a const
template<typename T> using remove_const_ref = typename std::remove_const<typename std::remove_reference<T>::type>::type;

/// Base type for all wrapped classes
struct CppAny
{
};

/// Trait to determine if a type is to be treated as a Julia immutable type that has isbits == true
template<typename T> struct IsImmutable : std::false_type {};

/// Trait to determine if the given type is to be treated as a bits type
template<typename T> struct IsBits : std::false_type {};

template<typename CppT>
inline CppT convert_to_cpp(jl_value_t* const& julia_value);

namespace detail
{
	template<bool, typename T1, typename T2>
	struct DispatchBits;

	// non-bits
	template<typename T1, typename T2>
	struct DispatchBits<false, T1, T2>
	{
		typedef T2 type;
	};

	// bits type
	template<typename T1, typename T2>
	struct DispatchBits<true, T1, T2>
	{
		typedef T1 type;
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
		return nullptr;
	}
}

/// Static mapping base template
template<typename SourceT> struct static_type_mapping
{
	typedef typename detail::DispatchBits<IsImmutable<SourceT>::value, SourceT, jl_value_t*>::type type;

	template<typename T> using remove_const_ref = typename detail::DispatchBits<IsImmutable<cpp_wrapper::remove_const_ref<T>>::value || IsBits<cpp_wrapper::remove_const_ref<T>>::value, cpp_wrapper::remove_const_ref<T>, T>::type;
	static jl_datatype_t* julia_type()
	{
		if(m_type_pointer == nullptr)
		{
			throw std::runtime_error("Type " + std::string(typeid(SourceT).name()) + " has no Julia wrapper");
		}
		return m_type_pointer;
	}

	static void set_julia_type(jl_datatype_t* dt)
	{
		if(m_type_pointer != nullptr)
		{
			throw std::runtime_error("Type " + std::string(typeid(SourceT).name()) + " was already registered");
		}
		m_type_pointer = dt;
		if(!std::is_pointer<SourceT>())
		{
			m_finalizer = jl_new_closure(detail::finalizer<SourceT>, (jl_value_t*)jl_emptysvec, NULL);
			protect_from_gc(m_finalizer);
		}
	}

	static jl_function_t* finalizer()
	{
		if(m_type_pointer == nullptr)
		{
			throw std::runtime_error("Type " + std::string(typeid(SourceT).name()) + " has no finalizer");
		}
		return m_finalizer;
	}

	static bool has_julia_type()
	{
		return m_type_pointer != nullptr;
	}

private:
	static jl_datatype_t* m_type_pointer;
	static jl_function_t* m_finalizer;
};

template<typename SourceT> jl_datatype_t* static_type_mapping<SourceT>::m_type_pointer = nullptr;
template<typename SourceT> jl_function_t* static_type_mapping<SourceT>::m_finalizer = nullptr;

/// Helper for Singleton types (Type{T} in Julia)
template<typename T>
struct SingletonType
{
};

template<typename T>
struct static_type_mapping<SingletonType<T>>
{
	typedef jl_datatype_t* type;
	static jl_datatype_t* julia_type() { return (jl_datatype_t*)jl_apply_type((jl_value_t*)jl_type_type, jl_svec1(static_type_mapping<T>::julia_type())); }
	template<typename T2> using remove_const_ref = cpp_wrapper::remove_const_ref<T2>;
};

/// Using declarations to avoid having to write typename all the time
template<typename SourceT> using mapped_julia_type = typename static_type_mapping<SourceT>::type;
template<typename T> using mapped_reference_type = typename static_type_mapping<remove_const_ref<T>>::template remove_const_ref<T>;

/// Specializations
template<> struct static_type_mapping<void>
{
	typedef void type;
	static jl_datatype_t* julia_type() { return jl_void_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<bool>
{
	typedef bool type;
	static jl_datatype_t* julia_type() { return jl_bool_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<double>
{
	typedef double type;
	static jl_datatype_t* julia_type() { return jl_float64_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<float>
{
	typedef float type;
	static jl_datatype_t* julia_type() { return jl_float64_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<int>
{
	typedef int type;
	static jl_datatype_t* julia_type() { return jl_int32_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<unsigned int>
{
	typedef unsigned int type;
	static jl_datatype_t* julia_type() { return jl_uint32_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<int64_t>
{
	typedef int64_t type;
	static jl_datatype_t* julia_type() { return jl_int64_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<uint64_t>
{
	typedef uint64_t type;
	static jl_datatype_t* julia_type() { return jl_uint64_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<std::string>
{
	typedef jl_value_t* type;
	static jl_datatype_t* julia_type() { return jl_any_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<void*>
{
	typedef jl_value_t* type;
	static jl_datatype_t* julia_type() { return jl_voidpointer_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<jl_datatype_t*>
{
	typedef jl_datatype_t* type; // Debatable if this should be jl_value_t*
	static jl_datatype_t* julia_type() { return jl_datatype_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

template<> struct static_type_mapping<jl_value_t*>
{
	typedef jl_value_t* type;
	static jl_datatype_t* julia_type() { return jl_any_type; }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

// Helper for ObjectIdDict
struct ObjectIdDict {};

template<> struct static_type_mapping<ObjectIdDict>
{
	typedef jl_value_t* type;
	static jl_datatype_t* julia_type() { return (jl_datatype_t*)jl_get_global(jl_base_module, jl_symbol("ObjectIdDict")); }
	template<typename T> using remove_const_ref = cpp_wrapper::remove_const_ref<T>;
};

/// Conversion to the statically mapped target type.
template<typename T>
inline typename std::enable_if<std::is_fundamental<T>::value, T>::type convert_to_julia(T&& cpp_val)
{
	return cpp_val;
}

template<typename T>
inline typename std::enable_if<IsImmutable<T>::value, T>::type convert_to_julia(T&& cpp_val)
{
	return cpp_val;
}

template<typename T>
inline typename std::enable_if<IsBits<T>::value, jl_value_t*>::type convert_to_julia(T&& cpp_val)
{
	return jl_new_bits((jl_value_t*)static_type_mapping<T>::julia_type(), &cpp_val);
}

inline jl_value_t* convert_to_julia(const std::string& str)
{
	return jl_cstr_to_string(str.c_str());
}

inline jl_value_t* convert_to_julia(std::string&& str)
{
	return jl_cstr_to_string(str.c_str());
}

inline jl_value_t* convert_to_julia(void* const& p)
{
	return jl_box_voidpointer(p);
}

inline jl_value_t* convert_to_julia(jl_value_t* const& p)
{
	return p;
}

inline jl_datatype_t* convert_to_julia(jl_datatype_t* const& dt)
{
	return dt;
}

template<typename CppT, typename JuliaT>
inline typename std::enable_if<std::is_fundamental<CppT>::value, CppT>::type convert_to_cpp(const JuliaT& julia_val)
{
	return julia_val;
}

template<typename CppT, typename JuliaT>
inline typename std::enable_if<IsImmutable<CppT>::value, CppT>::type convert_to_cpp(const JuliaT& julia_val)
{
	return julia_val;
}

namespace detail {

// Unpack based on reference or pointer target type
template<typename IsReference, typename IsPointer>
struct DoUnpack;

// Unpack for a reference
template<>
struct DoUnpack<std::true_type, std::false_type>
{
	template<typename CppT>
	CppT& operator()(CppT* ptr)
	{
		if(ptr == nullptr)
			throw std::runtime_error("C++ object was deleted");

		return *ptr;
	}
};

// Unpack for a pointer
template<>
struct DoUnpack<std::false_type, std::true_type>
{
	template<typename CppT>
	CppT* operator()(CppT* ptr)
	{
		return ptr;
	}
};

// Unpack for a value
template<>
struct DoUnpack<std::false_type, std::false_type>
{
	template<typename CppT>
	CppT operator()(CppT* ptr)
	{
		if(ptr == nullptr)
			throw std::runtime_error("C++ object was deleted");

		return *ptr;
	}
};

inline jl_value_t* box(const int i)
{
	return jl_box_int32(i);
}

inline jl_value_t* box(const unsigned int i)
{
	return jl_box_uint32(i);
}

inline jl_value_t* box(const int64_t i)
{
	return jl_box_int64(i);
}

/// Equivalent of the basic C++ type layout in Julia
struct WrappedCppPtr {
    JL_DATA_TYPE
    jl_value_t* voidptr;
};

/// Helper class to unpack a julia type
template<typename CppT, bool>
struct JuliaUnpacker
{
	// The C++ type stripped of all pointer, reference, const
	typedef typename std::remove_const<typename std::remove_pointer<remove_const_ref<CppT>>::type>::type stripped_cpp_t;

	CppT operator()(jl_value_t* julia_value)
	{
		return DoUnpack<typename std::is_reference<CppT>::type, typename std::is_pointer<CppT>::type>()(extract_cpp_pointer(julia_value));
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

// Unpack for bits type
template<typename CppT>
struct JuliaUnpacker<CppT, true>
{
	CppT operator()(jl_value_t* julia_value)
	{
		return *reinterpret_cast<CppT*>(jl_data_ptr(julia_value));
	}
};

} // namespace detail

template<typename CppT>
inline CppT convert_to_cpp(jl_value_t* const& julia_value)
{
	return detail::JuliaUnpacker<CppT, IsBits<CppT>::value>()(julia_value);
}

template<>
inline std::string convert_to_cpp(jl_value_t* const& julia_string)
{
	if(julia_string == nullptr || !jl_is_byte_string(julia_string))
	{
		throw std::runtime_error("Any type to convert to string is not a string");
	}
	std::string result(jl_bytestring_ptr(julia_string));
	return result;
}

inline jl_datatype_t* convert_to_cpp(jl_datatype_t* const& julia_value)
{
	return julia_value;
}

template<typename SingletonT>
inline SingletonT convert_to_cpp(jl_datatype_t* const& julia_value)
{
	return SingletonT();
}

template<>
inline jl_value_t* convert_to_cpp(jl_value_t* const& julia_value)
{
	return julia_value;
}

template<>
inline ObjectIdDict convert_to_cpp(jl_value_t* const&)
{
	return ObjectIdDict();
}

/// Convenience function to get the julia data type associated with T
template<typename T>
inline jl_datatype_t* julia_type()
{
	return static_type_mapping<T>::julia_type();
}

}

#endif
