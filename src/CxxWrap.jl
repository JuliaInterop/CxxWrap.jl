module CxxWrap

module CxxWrapCore

import Libdl
import MacroTools

export @wrapmodule, @readmodule, @wraptypes, @wrapfunctions, @safe_cfunction, @initcxx,
ConstCxxPtr, ConstCxxRef, CxxRef, CxxPtr,
CppEnum, ConstArray, CxxBool, CxxLong, CxxULong, CxxChar, CxxWchar, CxxUChar, CxxSignedChar, CxxLongLong, CxxULongLong,
ptrunion, gcprotect, gcunprotect, isnull, libcxxwrapversion

const libcxxwrap_version_range = (v"0.8.0",  v"0.9")

using libcxxwrap_julia_jll # for libcxxwrap_julia and libcxxwrap_julia_stl

if !isdefined(libcxxwrap_julia_jll, :libcxxwrap_julia_path)
    error("libcxxwrap_julia_jll not available on this platform")
end

# These can't be products, since we want to control how and when they are dlopened
for libname in ["jlcxx_containers", "except", "extended", "functions", "hello", "basic_types", "inheritance", "parametric", "pointer_modification", "types"]
  libcxxwrap_julia_name = basename(libcxxwrap_julia_jll.libcxxwrap_julia_path)
  libprefix = startswith(libcxxwrap_julia_name, "lib") ? "lib" : ""
  libext = libcxxwrap_julia_name[findlast('.', libcxxwrap_julia_name):end]
  full_libname = libprefix * libname * libext
  symname = "lib"*libname
  @eval $(Symbol(symname))() = joinpath(dirname(libcxxwrap_julia_jll.libcxxwrap_julia_path), $(full_libname))
end

prefix_path() = dirname(dirname(libcxxwrap_julia_jll.libcxxwrap_julia_path))

libcxxwrapversion() = VersionNumber(unsafe_string(ccall((:cxxwrap_version_string,libcxxwrap_julia), Cstring, ())))

function checkversion()
  jlcxxversion = libcxxwrapversion()
  if !(libcxxwrap_version_range[1] <= jlcxxversion < libcxxwrap_version_range[2])
    error("This version of CxxWrap requires a libcxxwrap-julia in the range $(libcxxwrap_version_range), but version $jlcxxversion was found")
  end
end

# Must also be called during precompile
checkversion()

# Welcome to the C/C++ integer type mess
# See https://en.cppreference.com/w/cpp/language/types and https://en.cppreference.com/w/cpp/types/integer

abstract type CxxSigned <: Signed end
abstract type CxxUnsigned <: Unsigned end


primitive type CxxBool <: CxxUnsigned 8*sizeof(Cuchar) end
const CharSigning = supertype(Cchar) == Signed ? CxxSigned : CxxUnsigned
primitive type CxxChar <: CharSigning 8*sizeof(Cchar) end
const WCharSigning = supertype(Cwchar_t) == Signed ? CxxSigned : CxxUnsigned
primitive type CxxWchar <: WCharSigning 8*sizeof(Cwchar_t) end

function _transform_fundamental_type(fundamental_type_name)
  julianame = "Cxx"
  for part in split(fundamental_type_name)
    if part == "unsigned"
      julianame *= "U"
      continue
    end
    julianame *= titlecase(part)
  end
  return Symbol(julianame)
end

_transform_fixed_type(fixed_type_name) = Symbol(replace(titlecase(fixed_type_name), "int" => "Int")[1:end-2])

# This macro adds the fundamental integer types such as long, which becomes CxxLong
# Names are e.g. CxxInt32 or CxxUInt64
macro add_int_types()
  all_fundamental_types = String[]
  type_sizes = Any[]
  fundamental_types_matched = String[]
  equivalent_types = String[]
  ccall((:get_integer_types,libcxxwrap_julia), Cvoid, (Any,Any,Any,Any), all_fundamental_types, type_sizes, fundamental_types_matched, equivalent_types)
  @assert all(all_fundamental_types .!= "undefined")
  sizedict = Dict(all_fundamental_types .=> type_sizes)
  result = quote end
  for (fundamentaltype, fixedtype) in zip(fundamental_types_matched, equivalent_types)
    push!(result.args, esc(:(const $(_transform_fundamental_type(fundamentaltype)) = $(_transform_fixed_type(fixedtype)))))
  end
  missing_types = setdiff(all_fundamental_types, fundamental_types_matched)
  for missingtype in missing_types
    super = startswith(missingtype, "unsigned") ? CxxUnsigned : CxxSigned
    nbits = sizedict[missingtype]*8
    push!(result.args, esc(:(primitive type $(_transform_fundamental_type(missingtype)) <: $super $nbits end)))
  end
  return result
end
@add_int_types

# Get the equivalent Julia type for a Cxx integer type
@generated julia_int_type(::Type{T}) where {T<:CxxSigned} = Symbol(:Int, 8*sizeof(T))
@generated julia_int_type(::Type{T}) where {T<:CxxUnsigned} = Symbol(:UInt, 8*sizeof(T))

to_julia_int(x::Union{CxxSigned,CxxUnsigned}) = reinterpret(julia_int_type(typeof(x)),x)

const CxxNumber = Union{CxxSigned,CxxUnsigned}
Base.show(io::IO, n::CxxNumber) = show(io, to_julia_int(n))
Base.show(io::IO, b::CxxBool) = show(io, Bool(b))
function Base.promote_rule(::Type{CT}, ::Type{JT}) where {CT <: CxxNumber, JT <: Number}
  if julia_int_type(CT) == JT
    return JT
  end
  return Base.promote_rule(julia_int_type(CT), JT)
end
Base.promote_type(::Type{T}, ::Type{T}) where {T<:CxxNumber} = julia_int_type(T)
Base.promote_rule(::Type{T}, ::Type{T}) where {T<:CxxNumber} = Base.promote_type(T,T)
Base.promote_rule(::Type{T1}, ::Type{T2}) where {T1<:CxxNumber, T2<:CxxNumber} = Base.promote_rule(julia_int_type(T1), julia_int_type(T2))
Base.AbstractFloat(x::CxxNumber) = Base.AbstractFloat(to_julia_int(x))

# Conversion to and from the equivalent Julia type
Base.convert(::Type{T}, x::Number) where {T<:Union{CxxSigned,CxxUnsigned}} = reinterpret(T, convert(julia_int_type(T), x))
Base.convert(::Type{JT}, x::CT) where {JT<:Number,CT<:Union{CxxSigned,CxxUnsigned}} = convert(JT,reinterpret(julia_int_type(CT), x))
Base.convert(::Type{T}, x::CT) where {T <: Union{CxxWrapCore.CxxSigned, CxxWrapCore.CxxUnsigned}, CT <: Union{CxxWrapCore.CxxSigned, CxxWrapCore.CxxUnsigned}}  = convert(T,reinterpret(julia_int_type(CT), x))

# Convenience constructors
(::Type{T})(x) where {T<:Union{CxxWrapCore.CxxSigned,CxxWrapCore.CxxUnsigned}} = convert(T,x)

Base.flipsign(x::T, y::T) where {T <: CxxSigned} = reinterpret(T, flipsign(to_julia_int(x), to_julia_int(y)))

# Trait type to indicate a type is a C++-wrapped type
struct IsCxxType end
struct IsNormalType end

@inline cpp_trait_type(::Type) = IsNormalType

# Enum type interface
abstract type CppEnum <: Integer end
Base.convert(::Type{T}, x::CppEnum) where {T <: Integer} = T(reinterpret(Int32, x))
Base.convert(::Type{T}, x::Integer) where {T <: CppEnum} = reinterpret(T, Int32(x))
Base.convert(::Type{T}, x::T) where {T <: CppEnum} = x
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
Base.convert(::Type{T}, p::T) where {PT,T <: SmartPointer{PT}} = p

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
  @static if Sys.iswindows()
    StrictlyTypedNumber{T}(x) where {T} = new(x)
    function StrictlyTypedNumber{Float64}(x)
      @warn "Using StrictlyTypedNumber{Float64} on Windows may give unpredictable results, see https://github.com/JuliaPackaging/BinaryBuilder.jl/issues/315. Run test CxxWrap in pkg mode to see if you are affected."
      return new(x)
    end
  end
end
function Base.convert(t::Type{<:StrictlyTypedNumber}, n::Number)
  @assert t == StrictlyTypedNumber{typeof(n)}
  return StrictlyTypedNumber{typeof(n)}(n)
end
Base.convert(t::Type{StrictlyTypedNumber{CxxBool}}, b::Bool) = StrictlyTypedNumber{CxxBool}(b)

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
_julia_pointer(p::CxxBaseRef{T}) where {T} = reinterpret(Ptr{julia_int_type(T)}, p.cpp_object)
Base.unsafe_string(p::CxxBaseRef) = unsafe_string(_julia_pointer(p))
Base.unsafe_string(p::CxxBaseRef, len::Integer) = unsafe_string(_julia_pointer(p), len)
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
function Base.convert(to_type::Type{<:Ref{T1}}, p::T2) where {BaseT,DerivedT, T1 <: BaseT, T2 <: SmartPointer{DerivedT}}
  return to_type(convert(T1,p))
end

Base.unsafe_convert(to_type::Type{<:CxxBaseRef}, x) = to_type(x.cpp_object)

# This is defined on the C++ side for each wrapped type
cxxupcast(x) = cxxupcast(CxxRef(x))
cxxupcast(x::CxxRef) = error("No upcast for type $(supertype(typeof(x))). Did you specialize SuperType to enable automatic upcasting?")
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
  julia_return_type::Type
  function_pointer::Ptr{Cvoid}
  thunk_pointer::Ptr{Cvoid}
  override_module::Module
end

# Interpreted as a constructor for Julia  > 0.5
mutable struct ConstructorFname
  _type::DataType
end

# Interpreted as an operator call overload
mutable struct CallOpOverload
  _type::DataType
end

# Type of the key used in the global function list, used to uniquely identify methods
const MethodKey = Tuple{Symbol,Symbol,Symbol,UInt}

function _module_name_hash(mod::Module, previous_hash=UInt(0))
  parent = parentmodule(mod)
  if parent == mod || parent == Main
    return hash(nameof(mod), previous_hash)
  end
  return _module_name_hash(parent, hash(nameof(mod), previous_hash))
end

_method_name_symbol(funcname::ConstructorFname) = (:constructor, nameof(funcname._type))
_method_name_symbol(funcname::CallOpOverload) = (:calloperator, nameof(funcname._type))
_method_name_symbol(funcname::Symbol) = (:function, funcname)

# Return a unique key for the given function, not taking into account the pointer values. This key has to be stable between Julia runs.
function methodkey(f::CppFunctionInfo)
  mhash = UInt(0)
  for arg in f.argument_types
    mhash = hash(arg, mhash)
  end
  mhash = hash(f.julia_return_type, mhash)
  mhash = hash(_module_name_hash(f.override_module), mhash)
  return (_method_name_symbol(f.name)..., nameof(f.override_module), mhash)
end

# Pointers to function and thunk
const FunctionPointers = Tuple{Ptr{Cvoid},Ptr{Cvoid},Bool}

# Store a unique map between methods and their pointer, filled whenever a method is created in a module
# This solves a problem with e.g. vectors of vectors of vectors of... where it is impossible to predict
# how many times and in which module a method will be defined
# This map is used to update a per-module vector of pointers upon module initialization, so it doesn't slow
# down each function call
const __global_method_map = Dict{MethodKey, FunctionPointers}()

function _register_function_pointers(func, precompiling)
  mkey = methodkey(func)
  fptrs = (func.function_pointer, func.thunk_pointer, precompiling)
  if haskey(__global_method_map, mkey)
    existing = __global_method_map[mkey]
    if existing[3] == precompiling
      error("Double registration for method $mkey")
    end
  end
  __global_method_map[mkey] = fptrs
  return (mkey, fptrs)
end

function _get_function_pointer(mkey)
  if !haskey(__global_method_map, mkey)
    error("Unregistered method with key $mkey requested, maybe you need to precompile the Julia module?")
  end
  return __global_method_map[mkey]
end

function initialize_cxx_lib()
  ccall((:initialize_cxxwrap,libcxxwrap_julia), Cvoid, (Any, Any), @__MODULE__, CppFunctionInfo)
end

# Must also be called during precompile
initialize_cxx_lib()

function __init__()
  checkversion()
  initialize_cxx_lib()
end

function has_cxx_module(mod::Module)
  r = ccall((:has_cxx_module,libcxxwrap_julia), Cuchar, (Any,), mod)
  return r != 0
end

function register_julia_module(mod::Module, fptr::Ptr{Cvoid})
  ccall((:register_julia_module,libcxxwrap_julia), Cvoid, (Any,Ptr{Cvoid}), mod, fptr)
end

function initialize_julia_module(mod::Module)
  if has_cxx_module(mod) # Happens when not precompiling
    return
  end
  fptr = Libdl.dlsym(Libdl.dlopen(mod.__cxxwrap_sopath, mod.__cxxwrap_flags), mod.__cxxwrap_wrapfunc)
  register_julia_module(mod, fptr)
  funcs = get_module_functions(mod)
  precompiling = false
  for func in funcs
    _register_function_pointers(func, precompiling)
  end
  for (fidx,mkey) in enumerate(mod.__cxxwrap_methodkeys)    
    mod.__cxxwrap_pointers[fidx] = _get_function_pointer(mkey)
  end
end

function get_module_functions(mod::Module)
  ccall((:get_module_functions,libcxxwrap_julia), Any, (Any,), mod)
end

function bind_constants(m::Module, symbols::Array, values::Array)
  ccall((:bind_module_constants,libcxxwrap_julia), Cvoid, (Any,Any,Any), m, symbols, values)
end

function box_types(mod::Module)
  ccall((:get_box_types,libcxxwrap_julia), Any, (Any,), mod)
end

"""
Protect a variable from garbage collection by adding it to the global array kept by CxxWrap
"""
function gcprotect(x)
  ccall((:gcprotect,libcxxwrap_julia), Cvoid, (Any,), x)
end

"""
Unprotect a variable from garbage collection by removing it from the global array kept by CxxWrap
"""
function gcunprotect(x)
  ccall((:gcunprotect,libcxxwrap_julia), Cvoid, (Any,), x)
end

# This struct is mirrored in C++, with always a pointer in the first field
struct _SafeCFunction
  fptr::Ptr{Cvoid}
  return_type::Type
  argtypes::Array{Type,1}
end

# Helper struct that can store a Base.CFunction
struct SafeCFunction
  fptr::Union{Ptr{Cvoid},Base.CFunction}
  return_type::Type
  argtypes::Array{Type,1}
end

Base.cconvert(::Type{_SafeCFunction}, f::SafeCFunction) = f
Base.unsafe_convert(::Type{_SafeCFunction}, f::SafeCFunction) = _SafeCFunction(Base.unsafe_convert(Ptr{Cvoid}, f.fptr), f.return_type, f.argtypes)

macro safe_cfunction(f, rt, args)
  return esc(:($(@__MODULE__).SafeCFunction(@cfunction($f, $rt, $args), $rt, [$(args.args...)])))
end

process_fname(fn::Tuple{<:Any,Module}, julia_mod) = process_fname(fn[1])
function process_fname(fn::Tuple{Symbol,Module}, julia_mod)
  (fname, mod) = fn
  if mod != julia_mod # Adding a method to a function from another module
    return :($mod.$fname)
  end
  return fname # defining a new function in the wrapped module, or adding a method to it
end
process_fname(fn::ConstructorFname) = :(::$(Type{fn._type}))
function process_fname(fn::CallOpOverload)
  return :(arg1::$(fn._type))
end

make_func_declaration(fn, argmap, julia_mod) = :($(process_fname(fn, julia_mod))($(argmap...)))
function make_func_declaration(fn::Tuple{CallOpOverload,Module}, argmap, julia_mod)
  return :($(process_fname(fn, julia_mod))($((argmap[2:end])...)))
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
map_julia_arg_type(a::Type{StrictlyTypedNumber{CxxBool}}) = Union{Bool,CxxBool}
map_julia_arg_type(x::Type{CxxBool}) = Union{Bool,CxxBool}
map_julia_arg_type(x::Type{T}) where {T<:Integer} = map_julia_arg_type(x, Base.invokelatest(cpp_trait_type, T))
map_julia_arg_type(x::Type{<:Integer}, ::Type{IsNormalType}) = Integer
map_julia_arg_type(x::Type{<:Integer}, ::Type{IsCxxType}) = x

const PtrTypes{T} = Union{CxxPtr{T}, Array{T}, CxxRef{T}, Base.RefValue{T}, Ptr{T},T}
const ConstPtrTypes{T} = Union{Ref{T}, Array{T}}

map_julia_arg_type(t::Type{<:CxxBaseRef{T}}) where {T} = map_julia_arg_type(t, Base.invokelatest(cpp_trait_type, T))

map_julia_arg_type(t::Type{ConstCxxRef{T}}, ::Type{IsNormalType}) where {T} = Union{Ref{T},map_julia_arg_type(T)}
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
map_julia_arg_type(t::Type{<:Array{T}}) where {T <: Union{CxxSigned,CxxUnsigned}} = Union{t, Array{julia_int_type(T)}}
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
cxxconvert(to_type::Type{<:CxxBaseRef{T}}, x::Base.RefValue, ::Type{IsNormalType}) where {T} = x
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
function build_function_expression(func::CppFunctionInfo, funcidx, julia_mod)
  # Arguments and types
  argtypes = func.argument_types
  argsymbols = map((i) -> Symbol(:arg,i[1]), enumerate(argtypes))

  map_c_arg_type(t::Type) = t
  map_c_arg_type(::Type{Array{T,1}}) where {T <: AbstractString} = Any
  map_c_arg_type(::Type{Type}) = Any
  map_c_arg_type(::Type{T}) where {T <: Tuple} = Any
  map_c_arg_type(::Type{ConstArray{T,N}}) where {T,N} = Any
  map_c_arg_type(::Type{T}) where {T<:Union{CxxSigned,CxxUnsigned}} = julia_int_type(T)
  map_c_arg_type(::Type{SafeCFunction}) = _SafeCFunction

  # Builds the return type passed to ccall
  map_c_return_type(t) = t
  map_c_return_type(::Type{T}) where {T <: Tuple} = Any
  map_c_return_type(::Type{ConstArray{T,N}}) where {T,N} = Any
  map_c_return_type(::Type{T}) where {T<:Union{CxxSigned,CxxUnsigned}} = map_c_arg_type(T)

  # Build the types for the ccall argument list
  c_arg_types = map_c_arg_type.(func.argument_types)
  c_return_type = map_c_return_type(func.return_type)

  # Builds the return-type annotation for the Julia function
  map_julia_return_type(t) = t
  map_julia_return_type(::Type{T}) where {T<:Union{CxxSigned,CxxUnsigned}} = map_c_arg_type(T)
  map_julia_return_type(::Type{CxxBool}) = Bool

  # Build the final call expression
  call_exp = quote end
  if func.thunk_pointer == C_NULL
    push!(call_exp.args, :(ccall(__cxxwrap_pointers[$funcidx][1], $c_return_type, ($(c_arg_types...),), $(argsymbols...)))) # Direct pointer call
  else
    push!(call_exp.args, :(ccall(__cxxwrap_pointers[$funcidx][1], $c_return_type, (Ptr{Cvoid}, $(c_arg_types...)), __cxxwrap_pointers[$funcidx][2], $(argsymbols...)))) # use thunk (= std::function)
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

  function_expression = :($(make_func_declaration((func.name,func.override_module), argmap(argtypes), julia_mod))::$(map_julia_return_type(func.julia_return_type)) = $call_exp)
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
    stunionall = st.name.wrapper
    if Base.invokelatest(cpp_trait_type, stunionall) != IsCxxType
      Core.eval(julia_mod, :(@inline $(@__MODULE__).cpp_trait_type(::Type{<:$stunionall}) = $(@__MODULE__).IsCxxType))
    end
    Core.eval(julia_mod, :(Base.convert(t::Type{$st}, x::T) where {T <: $st} = $(cxxupcast)($st,x)))
    Core.eval(julia_mod, :($(@__MODULE__).allocated_type(::Type{$st}) = $bt))
    reftype = makereftype(st, julia_mod)
    Core.eval(julia_mod, :($(@__MODULE__).dereferenced_type(::Type{$st}) = $reftype))
    Core.eval(julia_mod, :(Base.convert(::Type{$st}, x::$bt) = x))
    Core.eval(julia_mod, :(Base.convert(::Type{$st}, x::$reftype) = x))
    Core.eval(julia_mod, :(Base.:(==)(a::Union{CxxRef,ConstCxxRef,$bt}, b::$reftype) = (a.cpp_object == b.cpp_object)))
    Core.eval(julia_mod, :(Base.:(==)(a::$reftype, b::Union{CxxRef,ConstCxxRef,$bt}) = (b == a)))
  end
end

# Wrap functions from the cpp module to the passed julia module
function wrap_functions(functions, julia_mod)
  @assert isempty(julia_mod.__cxxwrap_pointers)
  precompiling = true

  for func in functions
    (mkey,fptrs) = _register_function_pointers(func, precompiling)
    push!(julia_mod.__cxxwrap_methodkeys, mkey)
    push!(julia_mod.__cxxwrap_pointers, fptrs)
    funcidx = length(julia_mod.__cxxwrap_pointers)

    Core.eval(julia_mod, build_function_expression(func, funcidx, julia_mod))
  end
end

# Place the types for the module with the name corresponding to the current module name in the current module
function wraptypes(jlmod)
  symbols = Any[]
  values = Any[]
  bind_constants(jlmod, symbols, values)
  for (sym,val) in zip(symbols, values)
    Core.eval(jlmod, :(const $sym = $val))
  end
end

function wrapfunctions(jlmod)
  module_functions = get_module_functions(jlmod)
  wrap_reference_converters(jlmod)
  wrap_functions(module_functions, jlmod)
end

function readmodule(so_path::AbstractString, funcname, m::Module, flags)
  if flags === nothing
    flags = Libdl.RTLD_LAZY | Libdl.RTLD_DEEPBIND
  end
  Core.eval(m, :(const __cxxwrap_methodkeys = $(MethodKey)[]))
  Core.eval(m, :(const __cxxwrap_pointers = $(FunctionPointers)[]))
  Core.eval(m, :(const __cxxwrap_sopath = $so_path))
  Core.eval(m, :(const __cxxwrap_wrapfunc = $(QuoteNode(funcname))))
  Core.eval(m, :(const __cxxwrap_flags = $flags))
  fptr = Libdl.dlsym(Libdl.dlopen(so_path, flags), funcname)
  register_julia_module(m, fptr)
end

function wrapmodule(so_path::AbstractString, funcname, m::Module, flags)
  readmodule(so_path, funcname, m, flags)
  wraptypes(m)
  wrapfunctions(m)
end

"""
  @wrapmodule libraryfile [functionname]

Place the functions and types from the C++ lib into the module enclosing this macro call
Calls an entry point named `define_julia_module`, unless another name is specified as
the second argument.
"""
macro wrapmodule(libraryfile, register_func=:(:define_julia_module), flags=:(nothing))
  return :(wrapmodule($(esc(libraryfile)), $(esc(register_func)), $__module__, $(esc(flags))))
end

"""
  @readmodule libraryfile [functionname]

Read a C++ module and associate it with the Julia module enclosing the macro call.
"""
macro readmodule(libraryfile, register_func=:(:define_julia_module), flags=:(nothing))
  return :(readmodule($(esc(libraryfile)), $(esc(register_func)), $__module__, $(esc(flags))))
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
  return :(initialize_julia_module($__module__))
end

isnull(x::CxxBaseRef) = (x.cpp_object == C_NULL)

reference_type_union(::Type{T}) where {T} = reference_type_union(T, Base.invokelatest(cpp_trait_type, T))
reference_type_union(::Type{T}, ::Type{IsNormalType}) where {T} = T
reference_type_union(::Type{T}, ::Type{IsCxxType}) where {T} = Union{T, CxxBaseRef{<:T}, SmartPointer{<:T}}
reference_type_union(t::TypeVar) = t

dereference_argument(x) = x
dereference_argument(x::CxxBaseRef) = x[]
dereference_argument(x::SmartPointer) = x[]

macro cxxdereference(f)
  fdict = MacroTools.splitdef(f)

  function maparg(a)
    (argname, argtype, slurp, default) = MacroTools.splitarg(a)
    return MacroTools.combinearg(argname, :($(@__MODULE__).reference_type_union($(argtype))), slurp, default)
  end

  # Adapt the signature
  fdict[:args] .= maparg.(fdict[:args])
  fdict[:kwargs] .= maparg.(fdict[:kwargs])

  # Dereference the arguments
  deref_expr = quote end
  for arg in vcat(fdict[:args], fdict[:kwargs])
    (argname, _, slurp, _) = MacroTools.splitarg(arg)
    if argname === nothing
      continue
    end
    if !slurp
      push!(deref_expr.args, :($argname = $(@__MODULE__).dereference_argument($argname)))
    else
      push!(deref_expr.args, :($argname = (($(@__MODULE__).dereference_argument.($argname))...,)))
    end
  end
  insert!(fdict[:body].args, 1, deref_expr)
  fdict[:body] = MacroTools.flatten(fdict[:body])

  # Reassemble the function
  return esc(MacroTools.combinedef(fdict))
end

export @cxxdereference

end

include("StdLib.jl")

using .CxxWrapCore
using .CxxWrapCore: CxxBaseRef, argument_overloads, SafeCFunction, reference_type_union, dereference_argument, prefix_path

export @wrapmodule, @readmodule, @wraptypes, @wrapfunctions, @safe_cfunction, @initcxx,
ConstCxxPtr, ConstCxxRef, CxxRef, CxxPtr,
CppEnum, ConstArray, CxxBool, CxxLong, CxxULong, CxxChar, CxxWchar, CxxUChar, CxxSignedChar, CxxLongLong, CxxULongLong,
ptrunion, gcprotect, gcunprotect, isnull

using .StdLib: StdVector, StdString, StdWString, StdValArray

export StdVector, StdString, StdWString, StdValArray, @cxxdereference

end # module
