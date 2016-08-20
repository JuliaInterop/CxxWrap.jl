using Base.Test

# This is a stand-alone test, showing how to call a function when setting obj.field = something.
# It would be useful for calling getters and setters on a wrapped C++ class
# The example here uses CppClass to stand-in for a real C++ class and allow a pure Julia demo

# type to wrap any field of a wrapped class, taking pointers in the type parameters for methods and data
immutable Property{ObjectT,ValueT,SetPtr,GetPtr,ObjPtr}
    set::Ptr{Void}
    get::Ptr{Void}
    obj::Ptr{Void}
    Property() = new(SetPtr,GetPtr,ObjPtr)
end

# Conversion from a field value type to a property uses the pointers in the parameters to call the setter
function Base.convert{ObjectT,ValueT,SetPtr,GetPtr,ObjPtr}(::Type{Property{ObjectT,ValueT,SetPtr,GetPtr,ObjPtr}}, v::ValueT)
    set_func = unsafe_pointer_to_objref(SetPtr)::Function
    cpp_obj = unsafe_pointer_to_objref(ObjPtr)::ObjectT
    set_func(cpp_obj, v)
    Property{ObjectT,ValueT,SetPtr,GetPtr,ObjPtr}()
end

# This is a place-holder for an actual C++ class
type CppClass
    a::Int
end

# getter and setter methods, which would normally call wrapped C++ methods
set_a(obj::CppClass, val::Int) = @show obj.a = val
get_a(obj::CppClass) = obj.a

# A wrapper for e.g. a C++ class, stored as a pointer. The pointer itself is a parameter
type WrappedCpp{CppPtr}
    cpp::Ptr{Void}
    a::Property{CppClass, Int, pointer_from_objref(set_a), pointer_from_objref(get_a), CppPtr}
    WrappedCpp() = new(CppPtr, Property{CppClass, Int, pointer_from_objref(set_a), pointer_from_objref(get_a), CppPtr}())
end

# Create a "C++" object
cppobj = CppClass(1);
# Wrap it
wrapped = WrappedCpp{pointer_from_objref(cppobj)}()

# Set a field on the wrapper
wrapped.a = 6

# Test that the value set on the wrapper propagated to the wrapped object
@test cppobj.a == 6
