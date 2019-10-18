module CxxWrap

import Libdl

export @wrapmodule, @readmodule, @wraptypes, @wrapfunctions, @safe_cfunction, @initcxx,
ConstCxxPtr, ConstCxxRef, CxxRef, CxxPtr,
CppEnum, ConstArray, CxxBool, CxxLong, CxxULong,
ptrunion, gcprotect, gcunprotect, isnull

# Convert path if it contains lib prefix on windows
function lib_path(so_path::AbstractString)
  path_copy = so_path
  @static if Sys.iswindows()
    basedir, libname = splitdir(so_path)
    libdir_suffix = Sys.WORD_SIZE == 32 ? "32" : ""
    if startswith(libname, "lib") && !isfile(so_path)
      path_copy = joinpath(basedir*libdir_suffix, libname[4:end])
    end
  end
  return path_copy
end

const depsfile = joinpath(dirname(dirname(@__FILE__)), "deps", "deps.jl")
if !isfile(depsfile)
  error("$depsfile not found, CxxWrap did not build properly")
end
include(depsfile)
const jlcxx_path = libcxxwrap_julia

# Welcome to the C/C++ integer type mess

abstract type CxxSigned <: Signed end
abstract type CxxUnsigned <: Unsigned end

# long is a special case, because depending on the platform it overlaps with int or long long. See https://en.cppreference.com/w/cpp/language/types
primitive type CxxLong <: CxxSigned 8*sizeof(Clong) end
primitive type CxxULong <: CxxUnsigned 8*sizeof(Culong) end
primitive type CxxBool <: CxxUnsigned 8*sizeof(Cuchar) end
const CharSigning = supertype(Cchar) == Signed ? CxxSigned : CxxUnsigned
primitive type CxxChar <: CharSigning 8*sizeof(Cchar) end
primitive type CxxUChar <: CxxUnsigned 8*sizeof(Cuchar) end
const WCharSigning = supertype(Cwchar_t) == Signed ? CxxSigned : CxxUnsigned
primitive type CxxWchar <: WCharSigning 8*sizeof(Cwchar_t) end

# This macro adds the fixed integer types described on https://en.cppreference.com/w/cpp/types/integer
# Names are e.g. CxxInt32 or CxxUInt64
macro add_int_types()
  result = quote end
  for signed in (Symbol(), :U)
    super = signed == :U ? CxxUnsigned : CxxSigned
    for nbits in (8,16,32,64)
      push!(result.args, :(primitive type $(Symbol(:Cxx, signed, :Int, nbits)) <: $super $nbits end))
    end
  end
  return result
end
@add_int_types

# Get the equivalen Julia type for a Cxx integer type
@generated julia_int_type(::Type{T}) where {T<:CxxSigned} = Symbol(:Int, 8*sizeof(T))
@generated julia_int_type(::Type{T}) where {T<:CxxUnsigned} = Symbol(:UInt, 8*sizeof(T))

to_julia_int(x::Union{CxxSigned,CxxUnsigned}) = reinterpret(julia_int_type(typeof(x)),x)

# Conversion to and from the equivalent Julia type
Base.convert(::Type{T}, x::Number) where {T<:Union{CxxSigned,CxxUnsigned}} = reinterpret(T, convert(julia_int_type(T), x))
Base.convert(::Type{JT}, x::CT) where {JT<:Number,CT<:Union{CxxSigned,CxxUnsigned}} = convert(JT,reinterpret(julia_int_type(CT), x))
Base.convert(::Type{T}, x::CT) where {T <: Union{CxxWrap.CxxSigned, CxxWrap.CxxUnsigned}, CT <: Union{CxxWrap.CxxSigned, CxxWrap.CxxUnsigned}}  = convert(T,reinterpret(julia_int_type(CT), x))

# Convenience constructors
(::Type{T})(x) where {T<:Union{CxxWrap.CxxSigned,CxxWrap.CxxUnsigned}} = convert(T,x)

Base.flipsign(x::CxxLong, y::CxxLong) = reinterpret(CxxLong, flipsign(to_julia_int(x), to_julia_int(y)))

# Trait type to indicate a type is a C++-wrapped type
struct IsCxxType end
struct IsNormalType end

@inline cpp_trait_type(::Type) = IsNormalType

# Enum type interface
abstract type CppEnum end
Base.convert(::Type{Int32}, x::CppEnum) = reinterpret(Int32, x)
import Base: +, |
+(a::T, b::T) where {T <: CppEnum} = reinterpret(T, convert(Int32,a) + convert(Int32,b))
|(a::T, b::T) where {T <: CppEnum} = reinterpret(T, convert(Int32,a) | convert(Int32,b))

"""
Base class for smart pointers
"""
abstract type SmartPointer{T} end
@inline cpp_trait_type(::Type{SmartPointer{T}}) where {T} = IsCxxType

Base.show(io::IO, x::SmartPointer) = print(io, "C++ smart pointer of type ", typeof(x))

allocated_type(t::Type) = Any
dereferenced_type(t::Type) = Any

__cxxwrap_smartptr_dereference(p::SmartPointer{T}) where {T} = __cxxwrap_smartptr_dereference(CxxRef(p))
__cxxwrap_smartptr_construct_from_other(t::Type{<:SmartPointer{T}}, p::SmartPointer{T}) where {T} = __cxxwrap_smartptr_construct_from_other(t,CxxRef(p))
__cxxwrap_smartptr_cast_to_base(p::SmartPointer{T}) where {T} = __cxxwrap_smartptr_cast_to_base(CxxRef(p))

function Base.getindex(p::SmartPointer{T}) where {T}
  return __cxxwrap_smartptr_dereference(p)
end

# No conversion if source and target type are identical
Base.convert(::Type{T}, p::T) where {T <: SmartPointer} = p

# Construct from a related pointer, e.g. a std::weak_ptr from std::shared_ptr
function Base.convert(::Type{T1}, p::T2) where {T, T1 <: SmartPointer{T}, T2 <: SmartPointer{T}}
  return __cxxwrap_smartptr_construct_from_other(T1, p)
end

# upcast to base class
function Base.convert(::Type{T1}, p::T2) where {BaseT,DerivedT, T1 <: SmartPointer{BaseT}, T2 <: SmartPointer{DerivedT}}
  if !(DerivedT <: BaseT)
    error("$DerivedT does not inherit from $BaseT in smart pointer convert")
  end
  # First convert to base type
  base_p = __cxxwrap_smartptr_cast_to_base(p)
  return convert(T1, base_p)
end

struct StrictlyTypedNumber{NumberT}
  value::NumberT
end
function Base.convert(t::Type{<:StrictlyTypedNumber}, n::Number)
  @assert t == StrictlyTypedNumber{typeof(n)}
  return StrictlyTypedNumber{typeof(n)}(n)
end

abstract type CxxBaseRef{T} <: Ref{T} end

struct CxxPtr{T} <: CxxBaseRef{T}
  cpp_object::Ptr{T}
  CxxPtr{T}(x::Ptr) where {T} = new{T}(x)
  CxxPtr{T}(x::CxxBaseRef) where {T} = new{T}(x.cpp_object)
end

struct ConstCxxPtr{T} <: CxxBaseRef{T}
  cpp_object::Ptr{T}
  ConstCxxPtr{T}(x::Ptr) where {T} = new{T}(x)
  ConstCxxPtr{T}(x::CxxBaseRef) where {T} = new{T}(x.cpp_object)
end

struct CxxRef{T} <: CxxBaseRef{T}
  cpp_object::Ptr{T}
  CxxRef{T}(x::Ptr) where {T} = new{T}(x)
  CxxRef{T}(x::CxxBaseRef) where {T} = new{T}(x.cpp_object)
end

struct ConstCxxRef{T} <: CxxBaseRef{T}
  cpp_object::Ptr{T}
  ConstCxxRef{T}(x::Ptr) where {T} = new{T}(x)
  ConstCxxRef{T}(x::CxxBaseRef) where {T} = new{T}(x.cpp_object)
end

_ref_type(::Type{RefT}, ::Type{<:CxxBaseRef{T}}) where {RefT,T} = _ref_type(RefT,T)
_ref_type(::Type{RefT}, ::Type{T}) where {RefT,T} = _ref_type(RefT, T, cpp_trait_type(T))
_ref_type(::Type{RefT}, ::Type{T}, ::Type) where {RefT,T} = error("Manual Cxx Reference creation is only for C++ types")
function _ref_type(::Type{RefT}, ::Type{T}, ::Type{IsCxxType}) where {RefT,T}
  if isconcretetype(T)
    return RefT{supertype(T)}
  end
  return RefT{T}
end
_make_ref(::Type{RefT}, x::T) where {RefT,T} = _ref_type(RefT,T)(x.cpp_object)

CxxPtr(x) = _make_ref(CxxPtr,x)
ConstCxxPtr(x) = _make_ref(ConstCxxPtr,x)
CxxRef(x) = _make_ref(CxxRef,x)
ConstCxxRef(x) = _make_ref(ConstCxxRef,x)

Base.convert(t::Type{<:CxxBaseRef{T}}, x::Ptr{NT}) where {T <: Union{CxxUnsigned, CxxSigned}, NT <: Integer} = t(reinterpret(Ptr{T}, x))

Base.:(==)(a::Union{CxxPtr,ConstCxxPtr}, b::Union{CxxPtr,ConstCxxPtr}) = (a.cpp_object == b.cpp_object)
Base.:(==)(a::CxxBaseRef, b::Ptr) = (a.cpp_object == b)
Base.:(==)(a::Ptr, b::CxxBaseRef) = (b == a)
Base.:(==)(a::Union{CxxRef,ConstCxxRef}, b) = (a[] == b)
Base.:(==)(a, b::Union{CxxRef,ConstCxxRef}) = (b == a)
Base.:(==)(a::Union{CxxRef,ConstCxxRef}, b::Union{CxxRef,ConstCxxRef}) = (a[] == b[])

_deref(p::CxxBaseRef, ::Type) = unsafe_load(p.cpp_object)
_deref(p::CxxBaseRef{T}, ::Type{IsCxxType}) where {T} = dereferenced_type(T)(p.cpp_object)

_store_to_cxxptr(::Any,::Any,::Type) = error("Resetting the value to a C++ pointer or reference is only supported for non-wrapped types")
_store_to_cxxptr(r::Union{ConstCxxPtr{T},ConstCxxRef{T}}, x::T, ::Type{IsNormalType}) where {T} = error("Setting the value of a const reference or pointer is not allowed")
_store_to_cxxptr(r::Union{CxxPtr{T},CxxRef{T}}, x::T, ::Type{IsNormalType}) where {T} = unsafe_store!(r.cpp_object, x)

Base.unsafe_load(p::CxxBaseRef{T}) where {T} = _deref(p, cpp_trait_type(T))
Base.unsafe_string(p::CxxBaseRef) = unsafe_string(p.cpp_object)
Base.getindex(r::CxxBaseRef) = unsafe_load(r)
Base.setindex!(r::CxxBaseRef{T}, x::T) where {T}  = _store_to_cxxptr(r, x, cpp_trait_type(T))

# Delegate iteration to the contained type
Base.iterate(x::CxxBaseRef) = Base.iterate(x[])
Base.iterate(x::CxxBaseRef, state) = Base.iterate(x[], state)
Base.length(x::CxxBaseRef) = Base.length(x[])
Base.size(x::CxxBaseRef, d) = Base.size(x[], d)

# Delegate broadcast operations to the contained type
Base.BroadcastStyle(::Type{<:CxxBaseRef{T}}) where {T} = Base.BroadcastStyle(T)
Base.axes(x::CxxBaseRef) = Base.axes(x[])
Base.broadcastable(x::CxxBaseRef) = Base.broadcastable(x[])

# Delegate indexing to the wrapped type
Base.getindex(x::CxxBaseRef, i::Int) = Base.getindex(x[], i)
Base.setindex!(x::CxxBaseRef, val, i::Int) = Base.setindex!(x[], val, i)

Base.convert(::Type{RT}, p::SmartPointer{T}) where {T, RT <: CxxBaseRef{T}} = p[]
Base.cconvert(::Type{RT}, p::SmartPointer{T}) where {T, RT <: CxxBaseRef{T}} = p[]
function Base.convert(::Type{T1}, p::SmartPointer{DerivedT}) where {BaseT,T1 <: BaseT, DerivedT <: BaseT}
  return cxxupcast(T1, p[])[]
end
Base.convert(to_type::Type{Any}, x::CxxWrap.SmartPointer{DerivedT}) where {DerivedT} = x
function Base.convert(to_type::Type{<:Ref{T1}}, p::T2) where {BaseT,DerivedT, T1 <: BaseT, T2 <: SmartPointer{DerivedT}}
  return to_type(convert(T1,p))
end

Base.unsafe_convert(to_type::Type{<:CxxBaseRef}, x) = to_type(x.cpp_object)

# This is defined on the C++ side for each wrapped type
cxxupcast(x) = cxxupcast(CxxRef(x))
cxxupcast(x::CxxBaseRef) = error("No upcast for type $(supertype(typeof(x))). Did you specialize SuperType to enable automatic upcasting?")
function cxxupcast(::Type{T}, x) where {T}
  cxxupcast(T, cxxupcast(x))
end
cxxupcast(::Type{T}, x::CxxBaseRef{T}) where {T} = x

struct ConstArray{T,N} <: AbstractArray{T,N}
  ptr::ConstCxxPtr{T}
  size::NTuple{N,Int}
end

ConstArray(ptr::ConstCxxPtr{T}, args::Vararg{Int,N}) where {T,N} = ConstArray{T,N}(ptr, (args...,))

Base.IndexStyle(::ConstArray) = IndexLinear()
Base.size(arr::ConstArray) = arr.size
Base.getindex(arr::ConstArray, i::Integer) = unsafe_load(arr.ptr.cpp_object, i)

function __delete end
function delete(x)
  __delete(CxxPtr(x))
  x.cpp_object = C_NULL
end

# Encapsulate information about a function
mutable struct CppFunctionInfo
  name::Any
  argument_types::Array{Type,1}
  return_type::Type
  function_pointer::Int
  thunk_pointer::Int
  override_module::Union{Nothing,Module}
end

function __init__()
  @static if Sys.iswindows()
    Libdl.dlopen(jlcxx_path, Libdl.RTLD_GLOBAL)
  end

  jlcxxversion = VersionNumber(unsafe_string(ccall((:version_string, jlcxx_path), Cstring, ())))
  if jlcxxversion < v"0.6.2"
    error("This version of CxxWrap requires at least libcxxwrap-julia v0.6.2, but version $jlcxxversion was found")
  end
end

function has_cxx_module(mod::Module)
  r = ccall((:has_cxx_module, jlcxx_path), Cuchar, (Any,), mod)
  return r != 0
end

const _gc_protected = Dict{UInt64,Tuple{Any, Int}}()

function protect_from_gc(x)
  id = objectid(x)
  (_,n) = get(_gc_protected, id, (x,0))
  _gc_protected[id] = (x,n+1)
  return
end

function unprotect_from_gc(x)
  id = objectid(x)
  (_,n) = get(_gc_protected, id, (x,0))
  if n == 0
    println("warning: attempt to unprotect non-protected object $x")
  end
  if n == 1
    delete!(_gc_protected, id)
  else
    _gc_protected[id] = (x,n-1)
  end
  return
end

function initialize_cxx_lib()
  _c_protect_from_gc = @cfunction protect_from_gc Nothing (Any,)
  _c_unprotect_from_gc = @cfunction unprotect_from_gc Nothing (Any,)
  ccall((:initialize, jlcxx_path), Cvoid, (Any, Any, Ptr{Cvoid}, Ptr{Cvoid}), @__MODULE__, CppFunctionInfo, _c_protect_from_gc, _c_unprotect_from_gc)
end

function register_julia_module(mod::Module, fptr::Ptr{Cvoid})
  initialize_cxx_lib()
  ccall((:register_julia_module, jlcxx_path), Cvoid, (Any,Ptr{Cvoid}), mod, fptr)
end

function register_julia_module(mod::Module)
  initialize_cxx_lib()
  fptr = Libdl.dlsym(Libdl.dlopen(mod.__cxxwrap_sopath), mod.__cxxwrap_wrapfunc)
  if !has_cxx_module(mod)
    empty!(mod.__cxxwrap_pointers)
    register_julia_module(mod, fptr)
  end
  if length(mod.__cxxwrap_pointers) != mod.__cxxwrap_nbpointers
    error("Binary part of module was changed since last precompilation, please rebuild.")
  end
end

function get_module_functions(mod::Module)
  ccall((:get_module_functions, jlcxx_path), Any, (Any,), mod)
end

function bind_constants(m::Module)
  ccall((:bind_module_constants, jlcxx_path), Cvoid, (Any,), m)
end

function box_types(mod::Module)
  ccall((:get_box_types, jlcxx_path), Any, (Any,), mod)
end

"""
Protect a variable from garbage collection by adding it to the global array kept by CxxWrap
"""
function gcprotect(x)
  protect_from_gc(x)
end

"""
Unprotect a variable from garbage collection by removing it from the global array kept by CxxWrap
"""
function gcunprotect(x)
  unprotect_from_gc(x)
end

# Interpreted as a constructor for Julia  > 0.5
mutable struct ConstructorFname
  _type::DataType
end

# Interpreted as an operator call overload
mutable struct CallOpOverload
  _type::DataType
end

process_fname(fn::Symbol) = fn
process_fname(fn::Tuple{Symbol,Module}) = :($(fn[2]).$(fn[1]))
process_fname(fn::ConstructorFname) = :(::$(Type{fn._type}))
function process_fname(fn::CallOpOverload)
  return :(arg1::$(fn._type))
end

make_func_declaration(fn, argmap) = :($(process_fname(fn))($(argmap...)))
function make_func_declaration(fn::CallOpOverload, argmap)
  return :($(process_fname(fn))($((argmap[2:end])...)))
end

# By default, no argument overloading happens
argument_overloads(t::Type) = Type[]
@static if Int != Cint
  argument_overloads(t::Type{Cint}) = [Int]
end
@static if UInt != Cuint
  argument_overloads(t::Type{Cuint}) = [UInt, Int]
else
  argument_overloads(t::Type{Cuint}) = [Int]
end
argument_overloads(t::Type{Float64}) = [Int, Irrational]
function argument_overloads(t::Type{Array{AbstractString,1}})
  return [Array{String,1}]
end
argument_overloads(t::Type{Ptr{T}}) where {T <: Number} = [Array{T,1}]

"""
Create a Union containing the type and a smart pointer to any type derived from it
"""
function ptrunion(::Type{T}) where {T}
  result{T2 <: T} = Union{T2, SmartPointer{T2}}
  return result
end

smart_pointer_type(t::Type) = smart_pointer_type(cpp_trait_type(t), t)
smart_pointer_type(::Type{IsNormalType}, t::Type) = t
smart_pointer_type(::Type{IsCxxType}, x::Type{T}) where {T} = ptrunion(x)

function smart_pointer_type(::Type{<:SmartPointer{T}}) where {T}
  result{T2 <: T} = SmartPointer{T2}
  return result
end

map_julia_arg_type(t::Type) = Union{Base.invokelatest(smart_pointer_type,t),argument_overloads(t)...}
map_julia_arg_type(a::Type{StrictlyTypedNumber{T}}) where {T} = T
map_julia_arg_type(x::Type{<:Integer}) = Integer

const PtrTypes{T} = Union{CxxPtr{T}, Array{T}, CxxRef{T}, Base.RefValue{T}, Ptr{T},T}
const ConstPtrTypes{T} = Union{Ref{T}, Array{T}}

map_julia_arg_type(t::Type{<:CxxBaseRef{T}}) where {T} = map_julia_arg_type(t, Base.invokelatest(cpp_trait_type, T))

map_julia_arg_type(t::Type{ConstCxxRef{T}}, ::Type{IsNormalType}) where {T} = Union{ConstPtrTypes{T},map_julia_arg_type(T)}
map_julia_arg_type(t::Type{ConstCxxPtr{T}}, ::Type{IsNormalType}) where {T} = Union{ConstPtrTypes{T},Ptr{Cvoid}}
map_julia_arg_type(t::Type{CxxRef{T}}, ::Type{IsNormalType}) where {T} = PtrTypes{T}
map_julia_arg_type(t::Type{CxxPtr{T}}, ::Type{IsNormalType}) where {T} = Union{PtrTypes{T},Ptr{Cvoid}}

map_julia_arg_type(t::Type{ConstCxxRef{T}}, ::Type{IsNormalType}) where {T<:Union{CxxSigned,CxxUnsigned}} = Union{ConstPtrTypes{julia_int_type(T)},map_julia_arg_type(T)}
map_julia_arg_type(t::Type{ConstCxxPtr{T}}, ::Type{IsNormalType}) where {T<:Union{CxxSigned,CxxUnsigned}} = Union{ConstPtrTypes{julia_int_type(T)},Ptr{Cvoid}}
map_julia_arg_type(t::Type{CxxRef{T}}, ::Type{IsNormalType}) where {T<:Union{CxxSigned,CxxUnsigned}} = PtrTypes{julia_int_type(T)}
map_julia_arg_type(t::Type{CxxPtr{T}}, ::Type{IsNormalType}) where {T<:Union{CxxSigned,CxxUnsigned}} = Union{PtrTypes{julia_int_type(T)},Ptr{Cvoid}}

map_julia_arg_type(t::Type{ConstCxxRef{T}}, ::Type{IsCxxType}) where {T} = Union{map_julia_arg_type(T),ConstCxxRef{<:T},CxxRef{<:T}}
map_julia_arg_type(t::Type{ConstCxxPtr{T}}, ::Type{IsCxxType}) where {T} = Union{CxxPtr{<:T},ConstCxxPtr{<:T}, Ptr{Cvoid}}
map_julia_arg_type(t::Type{CxxRef{T}}, ::Type{IsCxxType}) where {T} = Union{map_julia_arg_type(T),CxxRef{<:T}}
map_julia_arg_type(t::Type{CxxPtr{T}}, ::Type{IsCxxType}) where {T} = Union{CxxPtr{<:T},Ptr{Cvoid}}

map_julia_arg_type(t::Type{CxxPtr{CxxChar}}) = Union{PtrTypes{Cchar}, String}
map_julia_arg_type(t::Type{<:Array{Ptr{T}}}) where {T <: Union{CxxSigned,CxxUnsigned}} = Union{t, Array{Ptr{julia_int_type(T)}}}
map_julia_arg_type(t::Type{ConstCxxPtr{CxxChar}}) = Union{ConstPtrTypes{Cchar}, String}

# names excluded from julia type mapping
const __excluded_names = Set([
      :cxxupcast,
      :__cxxwrap_smartptr_dereference,
      :__cxxwrap_smartptr_construct_from_other,
      :__cxxwrap_smartptr_cast_to_base
])

function Base.cconvert(to_type::Type{<:CxxBaseRef{T}}, x) where {T}
  return cxxconvert(to_type, x, cpp_trait_type(T))
end
function Base.cconvert(to_type::Type{<:CxxBaseRef{T}}, x::Ptr{PT}) where {T<:Integer,PT<:Integer}
  @assert T == PT || julia_int_type(T) == PT
  return to_type(x)
end
@inline Base.cconvert(::Type{T}, v::T) where {T2,T <: CxxBaseRef{T2}} = v
Base.cconvert(to_type::Type{<:CxxBaseRef{T}}, v::CxxBaseRef{T}) where {T} = to_type(v.cpp_object)
Base.unsafe_convert(to_type::Type{<:CxxBaseRef{T}}, v::CxxBaseRef) where {T} = to_type(v.cpp_object)
Base.unsafe_convert(to_type::Type{<:CxxBaseRef}, v::Base.RefValue) = to_type(pointer_from_objref(v))

cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x, ::Type{IsNormalType}) where {T} = Ref{T}(convert(T,x))
cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x::Base.RefValue{T}, ::Type{IsNormalType}) where {T} = x
cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x::Ptr{T}, ::Type{IsNormalType}) where {T} = to_type(x)
cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x::Ptr{Cvoid}, ::Type{IsNormalType}) where {T} = to_type(x)
cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x::Union{Array,String}, ::Type{IsNormalType}) where {T} = to_type(pointer(x))
function cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x, ::Type{IsCxxType}) where {T}
  return convert(T,x)
end

function cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x::CxxBaseRef, ::Type{IsCxxType}) where {T}
  return to_type(convert(T,x[]))
end

# Build the expression to wrap the given function
function build_function_expression(func::CppFunctionInfo, mod=nothing)
  # Arguments and types
  argtypes = func.argument_types
  argsymbols = map((i) -> Symbol(:arg,i[1]), enumerate(argtypes))

  # These are actually indices into the module-global function pointer table
  fpointer = func.function_pointer
  thunk = func.thunk_pointer

  map_c_arg_type(t::Type) = t
  map_c_arg_type(::Type{Array{T,1}}) where {T <: AbstractString} = Any
  map_c_arg_type(::Type{Type}) = Any
  map_c_arg_type(::Type{T}) where {T <: Tuple} = Any
  map_c_arg_type(::Type{ConstArray{T,N}}) where {T,N} = Any
  map_c_arg_type(::Type{T}) where {T<:Union{CxxSigned,CxxUnsigned}} = julia_int_type(T)

  # Builds the return type passed to ccall
  map_c_return_type(t) = t
  map_c_return_type(::Type{T}) where {T <: Tuple} = Any
  map_c_return_type(::Type{ConstArray{T,N}}) where {T,N} = Any
  map_c_return_type(::Type{T}) where {T<:Union{CxxSigned,CxxUnsigned}} = map_c_arg_type(T)

  # Build the types for the ccall argument list
  c_arg_types = map_c_arg_type.(func.argument_types)
  c_return_type = map_c_return_type(func.return_type)

  # Builds the return-type annotation for the Julia function
  map_julia_return_type(t) = map_c_return_type(t)
  map_julia_return_type(::Type{CxxBool}) = Bool

  # Build the final call expression
  call_exp = quote end
  if thunk == 0
    push!(call_exp.args, :(ccall(__cxxwrap_pointers[$fpointer], $c_return_type, ($(c_arg_types...),), $(argsymbols...)))) # Direct pointer call
  else
    push!(call_exp.args, :(ccall(__cxxwrap_pointers[$fpointer], $c_return_type, (Ptr{Cvoid}, $(c_arg_types...)), __cxxwrap_pointers[$thunk], $(argsymbols...)))) # use thunk (= std::function)
  end

  function map_julia_arg_type_named(fname, t)
    if fname ∈ __excluded_names
      return t
    end
    return map_julia_arg_type(t)
  end

  # Build an array of arg1::Type1... expressions
  function argmap(signature)
    result = Expr[]
    for (t, s) in zip(signature, argsymbols)
      push!(result, :($s::$(map_julia_arg_type_named(func.name, t))))
    end
    return result
  end

  fname = mod === nothing ? func.name : (func.name,mod)
  function_expression = :($(make_func_declaration(fname, argmap(argtypes)))::$(map_julia_return_type(func.return_type)) = $call_exp)
  return function_expression
end

function makereftype(::Type{T}, mod) where {T}
  basename = T.name.name
  refname = Symbol(basename,"Dereferenced")
  tmod = T.name.module
  params = (T.parameters...,)
  if isempty(params)
    # If the type is non-parametric, this should be hit only once
    @assert !isdefined(mod, refname)
    @assert mod == tmod
    return Core.eval(mod, :(struct $refname <: $T cpp_object::Ptr{Cvoid} end; $refname))
  end
  if !isdefined(tmod, refname)
    #@assert mod == tmod
    parameternames = (Symbol(:T,i) for i in 1:length(params))
    expr = :(struct $refname{$(parameternames...)} <: $basename{$(parameternames...)} cpp_object::Ptr{Cvoid} end)
    Core.eval(mod, expr)
  end
  expr = :($tmod.$refname{$(params...)})
  return Core.eval(mod, expr)
end

function wrap_reference_converters(julia_mod)
  boxtypes = box_types(julia_mod)
  for bt in boxtypes
    st = supertype(bt)
    Core.eval(julia_mod, :(@inline CxxWrap.cpp_trait_type(::Type{<:$st}) = CxxWrap.IsCxxType))
    Core.eval(julia_mod, :(Base.convert(t::Type{$st}, x::T) where {T <: $st} = $(cxxupcast)($st,x)))
    Core.eval(julia_mod, :(CxxWrap.allocated_type(::Type{$st}) = $bt))
    reftype = makereftype(st, julia_mod)
    Core.eval(julia_mod, :(CxxWrap.dereferenced_type(::Type{$st}) = $reftype))
    Core.eval(julia_mod, :(Base.convert(::Type{$st}, x::$bt) = x))
    Core.eval(julia_mod, :(Base.convert(::Type{$st}, x::$reftype) = x))
  end
end

# Wrap functions from the cpp module to the passed julia module
function wrap_functions(functions, julia_mod)
  basenames = Set([
    :getindex,
    :setindex!,
    :convert,
    :deepcopy_internal,
    :+,
    :*,
    :(==)
  ])

  for func in functions
    if func.override_module != nothing
      Core.eval(julia_mod, build_function_expression(func, func.override_module))
    elseif func.name ∈ basenames
      Core.eval(julia_mod, build_function_expression(func, Base))
    else
      Core.eval(julia_mod, build_function_expression(func))
    end
  end
end

# Place the types for the module with the name corresponding to the current module name in the current module
function wraptypes(jlmod)
  bind_constants(jlmod)
end

function wrapfunctions(jlmod)
  module_functions = get_module_functions(jlmod)
  wrap_reference_converters(jlmod)
  wrap_functions(module_functions, jlmod)
end

function readmodule(so_path::AbstractString, funcname, m::Module)
  Core.eval(m, :(const __cxxwrap_pointers = Ptr{Cvoid}[]))
  Core.eval(m, :(const __cxxwrap_sopath = $so_path))
  Core.eval(m, :(const __cxxwrap_wrapfunc = $(QuoteNode(funcname))))
  fptr = Libdl.dlsym(Libdl.dlopen(so_path), funcname)
  register_julia_module(m, fptr)
  nb_pointers = length(m.__cxxwrap_pointers)
  Core.eval(m, :(const __cxxwrap_nbpointers = $nb_pointers))
end

function wrapmodule(so_path::AbstractString, funcname, m::Module)
  readmodule(so_path, funcname, m)
  wraptypes(m)
  wrapfunctions(m)
end

"""
  @wrapmodule libraryfile [functionname]

Place the functions and types from the C++ lib into the module enclosing this macro call
Calls an entry point named `define_julia_module`, unless another name is specified as
the second argument.
"""
macro wrapmodule(libraryfile, register_func=:(:define_julia_module))
  return :(wrapmodule($(esc(libraryfile)), $(esc(register_func)), $__module__))
end

"""
  @readmodule libraryfile [functionname]

Read a C++ module and associate it with the Julia module enclosing the macro call.
"""
macro readmodule(libraryfile, register_func=:(:define_julia_module))
  return :(readmodule($(esc(libraryfile)), $(esc(register_func)), $__module__))
end

"""
  @wraptypes

Wrap the types defined in the C++ side of the enclosing module. Requires that
`@readmodule` was called first.
"""
macro wraptypes()
  return :(wraptypes($__module__))
end

"""
  @wrapfunctions

Wrap the functions defined in the C++ side of the enclosing module. Requires that
`@readmodule` and `@wraptypes` was called first.
"""
macro wrapfunctions()
  return :(wrapfunctions($__module__))
end

"""
  @initcxx

Initialize the C++ pointer tables in a precompiled module using CxxWrap. Must be called from within
`__init__` in the wrapped module
"""
macro initcxx()
  return :(register_julia_module($__module__))
end

struct SafeCFunction
  fptr::Ptr{Cvoid}
  return_type::Type
  argtypes::Array{Type,1}
end

macro safe_cfunction(f, rt, args)
  return esc(:(CxxWrap.SafeCFunction(@cfunction($f, $rt, $args), $rt, [$(args.args...)])))
end

isnull(x::CxxBaseRef) = (x.cpp_object == C_NULL)

include("StdLib.jl")

using .StdLib: StdVector, StdString, StdWString

export StdVector, StdString, StdWString

end # module
