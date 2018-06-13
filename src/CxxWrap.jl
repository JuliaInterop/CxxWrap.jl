__precompile__()

module CxxWrap

using Compat
import Compat.Libdl

export wrap_modules, wrap_module, wrap_module_types, wrap_module_functions, @safe_cfunction, load_module, ptrunion, CppEnum, ConstPtr, ConstArray, gcprotect, gcunprotect

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

# Base type for wrapped C++ types
abstract type CppAny end
abstract type CppBits <: CppAny end
abstract type CppDisplay <: AbstractDisplay end
abstract type CppArray{T,N} <: AbstractArray{T,N} end
abstract type CppAssociative{K,V} <: AbstractDict{K,V} end

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
abstract type SmartPointer{T} <: CppAny end

"""
Concrete smart pointer implementation. PT is a hash for the pointer types, DerefPtr a pointer to the dereference function,
ConstructPtr a function pointer to construct from a compatible smart pointer type (e.g. weak_ptr from shared_ptr)
CastPtr is a function pointer to cast to the direct base class
"""
mutable struct SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr} <: SmartPointer{T}
  ptr::Ptr{Nothing}
end

reference_type(t::Type) = Any

@generated function dereference_smart_pointer(p::SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}, ::Type{DereferencedT}) where {T,PT,DerefPtr,ConstructPtr,CastPtr,DereferencedT}
  quote
    ccall(DerefPtr, $DereferencedT, (Ptr{Nothing},), p.ptr)
  end
end

function Base.getindex(p::SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr})::reference_type(T) where {T,PT,DerefPtr,ConstructPtr,CastPtr}
  return dereference_smart_pointer(p, reference_type(T))
end

# No conversion if source and target type are identical
Base.convert(::Type{SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}}, p::SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}) where {T,PT,DerefPtr,ConstructPtr,CastPtr} = p

# Construct from a related pointer, e.g. a std::weak_ptr from std::shared_ptr
function Base.convert(::Type{SmartPointerWithDeref{T,PT1,B1,B2,B3}}, p::SmartPointerWithDeref{T,PT2,D1,D2,D3}) where {T,PT1,PT2,B1,B2,B3,D1,D2,D3}
  ccall(B2, Any, (Any,), p)
end

# Construct from a related pointer, downcasting the type to base class
function Base.convert(t::Type{SmartPointerWithDeref{BaseT,PT1,B1,B2,B3}}, p::SmartPointerWithDeref{DerivedT,PT2,D1,D2,D3}) where {BaseT,DerivedT,PT1,PT2,B1,B2,B3,D1,D2,D3}
  if !(DerivedT <: BaseT)
    error("$DerivedT does not inherit from $BaseT in smart pointer convert")
  end
  # First convert to base type
  base_p = ccall(D3, Any, (Ptr{Nothing},), p.ptr)
  return convert(t, base_p)
end

# Cast to base type enclosed in same pointer type
function Base.convert(::Type{SmartPointerWithDeref{BaseT,PT,B1,B2,B3}}, p::SmartPointerWithDeref{DerivedT,PT,D1,D2,D3}) where {BaseT,DerivedT,PT,B1,B2,B3,D1,D2,D3}
  if !(DerivedT <: BaseT)
    error("$DerivedT does not inherit from $BaseT in smart pointer convert")
  end
  return convert(SmartPointerWithDeref{BaseT,PT,B1,B2,B3}, ccall(D3, Any, (Ptr{Nothing},), p.ptr))
end

struct StrictlyTypedNumber{NumberT}
  value::NumberT
end
Base.convert(::Type{StrictlyTypedNumber{NumberT}}, n::NumberT) where {NumberT} = StrictlyTypedNumber{NumberT}(n)

struct ConstPtr{T} <: CppBits
  ptr::Ptr{T}
end

struct ConstArray{T,N} <: CppArray{T,N}
  ptr::ConstPtr{T}
  size::NTuple{N,Int}
end

ConstArray(ptr::ConstPtr{T}, args::Vararg{Int,N}) where {T,N} = ConstArray{T,N}(ptr, (args...,))

@compat Base.IndexStyle(::ConstArray) = IndexLinear()
Base.size(arr::ConstArray) = arr.size
Base.getindex(arr::ConstArray, i::Integer) = unsafe_load(arr.ptr.ptr, i)

# Encapsulate information about a function
mutable struct CppFunctionInfo
  name::Any
  argument_types::Array{Type,1}
  reference_argument_types::Array{Type,1}
  return_type::Type
  function_pointer::Ptr{Nothing}
  thunk_pointer::Ptr{Nothing}
end

function __init__()
  @static if Sys.iswindows()
    Libdl.dlopen(jlcxx_path, Libdl.RTLD_GLOBAL)
  end
  ccall((:initialize, jlcxx_path), Nothing, (Any, Any, Any), CxxWrap, CppAny, CppFunctionInfo)
end

# Load the modules in the shared library located at the given path
function load_modules(path::AbstractString, parent_module)
  fptr = Libdl.dlsym(Libdl.dlopen(path, Libdl.RTLD_GLOBAL), "register_julia_modules")
  registry = ccall((:create_registry, jlcxx_path), Ptr{Nothing}, (Any,Any), parent_module, nothing)
  ccall(fptr, Nothing, (Ptr{Nothing},), registry)
  return registry
end

"""
Load a single module, to be wrapped in wrapped_module
"""
function load_module(path::AbstractString, wrapped_module)
  fptr = Libdl.dlsym(Libdl.dlopen(path, Libdl.RTLD_GLOBAL), "register_julia_modules")
  registry = ccall((:create_registry, jlcxx_path), Ptr{Nothing}, (Any,Any), parentmodule(wrapped_module), wrapped_module)
  ccall(fptr, Nothing, (Ptr{Nothing},), registry)
  return registry
end

function get_modules(registry::Ptr{Nothing})
  ccall((:get_modules, jlcxx_path), Any, (Ptr{Nothing},), registry)
end

function get_wrapped_module(registry::Ptr{Nothing})
  ccall((:get_wrapped_module, jlcxx_path), Any, (Ptr{Nothing},), registry)
end

function get_module_functions(registry::Ptr{Nothing})
  ccall((:get_module_functions, jlcxx_path), Any, (Ptr{Nothing},), registry)
end

function bind_constants(registry::Ptr{Nothing}, m::Module)
  ccall((:bind_module_constants, jlcxx_path), Nothing, (Ptr{Nothing},Any), registry, m)
end

function exported_symbols(registry::Ptr{Nothing}, modname::AbstractString)
  ccall((:get_exported_symbols, jlcxx_path), Any, (Ptr{Nothing},AbstractString), registry, modname)
end

function reference_types(registry::Ptr{Nothing}, modname::AbstractString)
  ccall((:get_reference_types, jlcxx_path), Any, (Ptr{Nothing},AbstractString), registry, modname)
end

function allocated_types(registry::Ptr{Nothing}, modname::AbstractString)
  ccall((:get_allocated_types, jlcxx_path), Any, (Ptr{Nothing},AbstractString), registry, modname)
end

"""
Protect a variable from garbage collection by adding it to the global array kept by CxxWrap
"""
function gcprotect(x)
  ccall((:gcprotect, jlcxx_path), Nothing, (Any,), x)
end

"""
Unprotect a variable from garbage collection by removing it from the global array kept by CxxWrap
"""
function gcunprotect(x)
  ccall((:gcunprotect, jlcxx_path), Nothing, (Any,), x)
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

smart_pointer_type(t::Type) = t
smart_pointer_type(x::Type{T}) where {T <: CppAny} = ptrunion(x)
smart_pointer_type(x::Type{T}) where {T <: CppArray} = ptrunion(x)
smart_pointer_type(x::Type{T}) where {T <: CppAssociative} = ptrunion(x)

function smart_pointer_type(::Type{SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}}) where {T,PT,DerefPtr,ConstructPtr,CastPtr}
  result{T2 <: T} = SmartPointer{T2}
  return result
end

map_julia_arg_type(t::Type) = Union{smart_pointer_type(t),argument_overloads(t)...}
map_julia_arg_type(a::Type{StrictlyTypedNumber{T}}) where {T} = T

# Build the expression to wrap the given function
function build_function_expression(func::CppFunctionInfo)
  # Arguments and types
  argtypes = func.argument_types
  argsymbols = map((i) -> Symbol(:arg,i[1]), enumerate(argtypes))

  # Function pointer
  fpointer = func.function_pointer
  @assert fpointer != C_NULL

  # Thunk
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
  if thunk == C_NULL
    call_exp = :(ccall($fpointer, $return_type, ($(c_arg_types...),), $(converted_args...))) # Direct pointer call
  else
    call_exp = :(ccall($fpointer, $return_type, (Ptr{Nothing}, $(c_arg_types...)), $thunk, $(converted_args...))) # use thunk (= std::function)
  end
  @assert call_exp != nothing

  # Build an array of arg1::Type1... expressions
  function argmap(signature)
    result = Expr[]
    for (t, s) in zip(signature, argsymbols)
      push!(result, :($s::$(map_julia_arg_type(t))))
    end
    return result
  end

  function_expression = :($(make_func_declaration(func.name, argmap(argtypes)))::$(func.return_type) = $call_exp)
  return function_expression
end

function wrap_reference_converters(registry, julia_mod)
  mod_name = string(nameof(julia_mod))
  reftypes = reference_types(registry, mod_name)
  alloctypes = allocated_types(registry, mod_name)
  for (rt, at) in zip(reftypes, alloctypes)
    st = supertype(at)
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$rt) = x))
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$at) = unsafe_load(reinterpret(Ptr{$rt}, pointer_from_objref(x)))))
    Core.eval(Base, :(cconvert(t::Type{$rt}, x::T) where {T <: $st} = Base.cconvert(t, $(cxxdowncast)(x))))
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$(SmartPointer{st})) = x[]))
    Core.eval(Base, :(cconvert(t::Type{$rt}, x::$(SmartPointer){T}) where {T <: $st} = Base.cconvert(t, $(cxxdowncast)(x[]))))
    Core.eval(CxxWrap, :(reference_type(::Type{$st}) = $rt))
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
    :cxxdowncast
  ])

  for func in functions
    if func.name ∈ basenames
      Core.eval(Base, build_function_expression(func))
    elseif func.name ∈ cxxnames
      Core.eval(CxxWrap, build_function_expression(func))
    else
      Core.eval(julia_mod, build_function_expression(func))
    end
  end
end

# Create modules defined in the given library, wrapping all their functions and types
function wrap_modules(registry::Ptr{Nothing})
  jl_modules = get_modules(registry)
  for jl_mod in jl_modules
    bind_constants(registry, jl_mod)
  end

  module_functions = get_module_functions(registry)
  for (jl_mod, mod_functions) in zip(jl_modules, module_functions)
    wrap_reference_converters(registry, jl_mod)
    wrap_functions(mod_functions, jl_mod)
  end

  for jl_mod in jl_modules
    exps = [Symbol(s) for s in exported_symbols(registry, string(nameof(jl_mod)))]
    Core.eval(jl_mod, :(export $(exps...)))
  end
end

# Wrap modules in the given path
function wrap_modules(so_path::AbstractString, parent_mod=Main)#(VERSION > v"0.7-" ? Base.__toplevel__ : Main))
  registry = CxxWrap.load_modules(lib_path(so_path), parent_mod)
  wrap_modules(registry)
end

# Place the types for the module with the name corresponding to the current module name in the current module
function wrap_module_types(registry)
  jlmod = get_wrapped_module(registry)
  wanted_name = string(nameof(jlmod))
  bind_constants(registry, jlmod)
  
  exps = [Symbol(s) for s in exported_symbols(registry, wanted_name)]
  Core.eval(jlmod, :(export $(exps...)))
end

function wrap_module_functions(registry)
  modules = get_modules(registry)
  @assert length(modules) == 1
  mod_idx = 1

  if mod_idx == 0
    error("Module $wanted_name not found in C++")
  end

  jlmod = get_wrapped_module(registry)
  module_functions = get_module_functions(registry)
  wrap_reference_converters(registry, jlmod)
  wrap_functions(module_functions[mod_idx], jlmod)
end

# Place the functions and types into the current module
function wrap_module(registry::Ptr{Nothing})
  wrap_module_types(registry)
  wrap_module_functions(registry)
end

"""
Wrap C++ types into module m. Assumes the library adds only a single module with the same name as m.
"""
function wrap_module(so_path::AbstractString, m::Module)
  registry = CxxWrap.load_module(lib_path(so_path), m)
  wrap_module(registry)
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

Base.isnull(x::CppAny) = (x.cpp_object == C_NULL)

end # module
