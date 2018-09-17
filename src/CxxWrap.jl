module CxxWrap

import BinaryProvider
import Libdl

export @wrapmodule, @readmodule, @wraptypes, @wrapfunctions, @safe_cfunction, @initcxx, load_module, ptrunion, CppEnum, ConstPtr, ConstArray, gcprotect, gcunprotect, isnull

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

prefix() =  BinaryProvider.Prefix(dirname(dirname(jlcxx_path)))

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

cxxdowncast(x) = error("No downcast for type $(supertype(typeof(x))). Did you specialize SuperType to enable automatic downcasting?")

"""
Base class for smart pointers
"""
abstract type SmartPointer{T} end
@inline cpp_trait_type(::Type{SmartPointer{T}}) where {T} = IsCxxType

"""
Concrete smart pointer implementation. PT is a hash for the pointer type.
"""
mutable struct SmartPointerWithDeref{T,PT} <: SmartPointer{T}
  ptr::Ptr{Cvoid}
end

reference_type(t::Type) = Any

function __cxxwrap_smartptr_dereference(p::SmartPointerWithDeref{T,PT}) where {T,PT}
  error("Unimplemented smartptr_dereference function for $(typeof(p))")
end

function __cxxwrap_smartptr_construct_from_other(p::SmartPointerWithDeref{T,PT}) where {T,PT}
  error("Unimplemented smartptr_construct_from_other for type $(typeof(p))")
end

function __cxxwrap_smartptr_cast_to_base(p::SmartPointerWithDeref{T,PT}) where {T,PT}
  error("Unimplemented smartptr_cast_to_base for type $(typeof(p))")
end

function Base.getindex(p::SmartPointerWithDeref{T,PT})::reference_type(T) where {T,PT}
  return __cxxwrap_smartptr_dereference(p)
end

# No conversion if source and target type are identical
Base.convert(::Type{SmartPointerWithDeref{T,PT}}, p::SmartPointerWithDeref{T,PT}) where {T,PT} = p

# Construct from a related pointer, e.g. a std::weak_ptr from std::shared_ptr
function Base.convert(::Type{SmartPointerWithDeref{T,PT1}}, p::SmartPointerWithDeref{T,PT2}) where {T,PT1,PT2}
  __cxxwrap_smartptr_construct_from_other(p)
end

# Construct from a related pointer, downcasting the type to base class
function Base.convert(t::Type{SmartPointerWithDeref{BaseT,PT1}}, p::SmartPointerWithDeref{DerivedT,PT2}) where {BaseT,DerivedT,PT1,PT2}
  if !(DerivedT <: BaseT)
    error("$DerivedT does not inherit from $BaseT in smart pointer convert")
  end
  # First convert to base type
  base_p = __cxxwrap_smartptr_cast_to_base(p)
  return convert(t, base_p)
end

# Cast to base type enclosed in same pointer type
function Base.convert(::Type{SmartPointerWithDeref{BaseT,PT}}, p::SmartPointerWithDeref{DerivedT,PT}) where {BaseT,DerivedT,PT}
  if !(DerivedT <: BaseT)
    error("$DerivedT does not inherit from $BaseT in smart pointer convert")
  end
  return convert(SmartPointerWithDeref{BaseT,PT}, __cxxwrap_smartptr_cast_to_base(p))
end

struct StrictlyTypedNumber{NumberT}
  value::NumberT
end
Base.convert(::Type{StrictlyTypedNumber{NumberT}}, n::NumberT) where {NumberT} = StrictlyTypedNumber{NumberT}(n)

struct ConstPtr{T}
  ptr::Ptr{T}
end

struct ConstArray{T,N} <: AbstractArray{T,N}
  ptr::ConstPtr{T}
  size::NTuple{N,Int}
end

ConstArray(ptr::ConstPtr{T}, args::Vararg{Int,N}) where {T,N} = ConstArray{T,N}(ptr, (args...,))

Base.IndexStyle(::ConstArray) = IndexLinear()
Base.size(arr::ConstArray) = arr.size
Base.getindex(arr::ConstArray, i::Integer) = unsafe_load(arr.ptr.ptr, i)

# Encapsulate information about a function
mutable struct CppFunctionInfo
  name::Any
  argument_types::Array{Type,1}
  reference_argument_types::Array{Type,1}
  return_type::Type
  function_pointer::Int
  thunk_pointer::Int
end

function __init__()
  @static if Sys.iswindows()
    Libdl.dlopen(jlcxx_path, Libdl.RTLD_GLOBAL)
  end

  jlcxxversion = VersionNumber(unsafe_string(ccall((:version_string, jlcxx_path), Cstring, ())))
  if jlcxxversion < v"0.5.0"
    error("This version of CxxWrap requires at least libcxxwrap-julia v0.4.0, but version $jlcxxversion was found")
  end

  ccall((:initialize, jlcxx_path), Cvoid, (Any, Any), CxxWrap, CppFunctionInfo)
end

function has_cxx_module(mod::Module)
  r = ccall((:has_cxx_module, jlcxx_path), Cuchar, (Any,), mod)
  return r != 0
end

function register_julia_module(mod::Module, fptr::Ptr{Cvoid})
  ccall((:register_julia_module, jlcxx_path), Cvoid, (Any,Ptr{Cvoid}), mod, fptr)
end

function register_julia_module(mod::Module)
  fptr = Libdl.dlsym(Libdl.dlopen(mod.__cxxwrap_sopath), mod.__cxxwrap_wrapfunc)
  if !has_cxx_module(mod)
    empty!(mod.__cxxwrap_pointers)
    ccall((:register_julia_module, jlcxx_path), Cvoid, (Any,Ptr{Cvoid}), mod, fptr)
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

function reference_types(mod::Module)
  ccall((:get_reference_types, jlcxx_path), Any, (Any,), mod)
end

function allocated_types(mod::Module)
  ccall((:get_allocated_types, jlcxx_path), Any, (Any,), mod)
end

"""
Protect a variable from garbage collection by adding it to the global array kept by CxxWrap
"""
function gcprotect(x)
  ccall((:gcprotect, jlcxx_path), Cvoid, (Any,), x)
end

"""
Unprotect a variable from garbage collection by removing it from the global array kept by CxxWrap
"""
function gcunprotect(x)
  ccall((:gcunprotect, jlcxx_path), Cvoid, (Any,), x)
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
process_fname(fn::Tuple{Symbol,Module}) = :($(Symbol(fn[2])).$(fn[1]))
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

function smart_pointer_type(::Type{SmartPointerWithDeref{T,PT}}) where {T,PT}
  result{T2 <: T} = SmartPointer{T2}
  return result
end

map_julia_arg_type(t::Type) = Union{Base.invokelatest(smart_pointer_type,t),argument_overloads(t)...}
map_julia_arg_type(a::Type{StrictlyTypedNumber{T}}) where {T} = T

# names excluded from julia type mapping
const __excluded_names = Set([
      :cxxdowncast,
      :__cxxwrap_smartptr_dereference,
      :__cxxwrap_smartptr_construct_from_other,
      :__cxxwrap_smartptr_cast_to_base
])

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
  map_c_arg_type(::Type{T}) where {T <: SmartPointer} = Any

  map_return_type(t) = map_c_arg_type(t)
  map_return_type(t::Type{Ref{T}}) where {T} = Ptr{T}

  # Build the types for the ccall argument list
  c_arg_types = [map_c_arg_type(t) for t in func.reference_argument_types]
  return_type = map_return_type(func.return_type)

  converted_args = ([:(Base.cconvert($t,$a)) for (t,a) in zip(func.reference_argument_types,argsymbols)]...,)

  # Build the final call expression
  call_exp = nothing
  if thunk == 0
    call_exp = :(ccall(__cxxwrap_pointers[$fpointer], $return_type, ($(c_arg_types...),), $(converted_args...))) # Direct pointer call
  else
    call_exp = :(ccall(__cxxwrap_pointers[$fpointer], $return_type, (Ptr{Cvoid}, $(c_arg_types...)), __cxxwrap_pointers[$thunk], $(converted_args...))) # use thunk (= std::function)
  end
  @assert call_exp != nothing

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
  function_expression = :($(make_func_declaration(fname, argmap(argtypes)))::$(func.return_type) = $call_exp)
  return function_expression
end

function wrap_reference_converters(julia_mod)
  reftypes = reference_types(julia_mod)
  alloctypes = allocated_types(julia_mod)
  for (rt, at) in zip(reftypes, alloctypes)
    st = supertype(at)
    Core.eval(julia_mod, :(@inline CxxWrap.cpp_trait_type(::Type{<:$st}) = CxxWrap.IsCxxType))
    Core.eval(julia_mod, :(Base.cconvert(::Type{$rt}, x::$rt) = x))
    Core.eval(julia_mod, :(Base.cconvert(::Type{$rt}, x::$at) = unsafe_load(reinterpret(Ptr{$rt}, pointer_from_objref(x)))))
    Core.eval(julia_mod, :(Base.cconvert(t::Type{$rt}, x::T) where {T <: $st} = Base.cconvert(t, $(cxxdowncast)(x))))
    Core.eval(julia_mod, :(Base.cconvert(::Type{$rt}, x::$(SmartPointer{st})) = x[]))
    Core.eval(julia_mod, :(Base.cconvert(t::Type{$rt}, x::$(SmartPointer){T}) where {T <: $st} = Base.cconvert(t, $(cxxdowncast)(x[]))))
    Core.eval(julia_mod, :(CxxWrap.reference_type(::Type{$st}) = $rt))
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

  cxxnames = Set([
    :cxxdowncast,
    :__cxxwrap_smartptr_dereference,
    :__cxxwrap_smartptr_construct_from_other,
    :__cxxwrap_smartptr_cast_to_base
  ])

  for func in functions
    if func.name ∈ basenames
      Core.eval(julia_mod, build_function_expression(func, Base))
    elseif func.name ∈ cxxnames
      Core.eval(julia_mod, build_function_expression(func, CxxWrap))
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

wstring_to_julia(p::Ptr{Cwchar_t}, L::Int) = transcode(String, unsafe_wrap(Array, p, L))
wstring_to_cpp(s::String) = transcode(Cwchar_t, s)

isnull(x::T) where{T} = isnull(cpp_trait_type(T), x)
isnull(::Type{IsCxxType}, x) = (x.cpp_object == C_NULL)

end # module
