__precompile__()

module CxxWrap

using Compat

export wrap_modules, wrap_module, wrap_module_types, wrap_module_functions, safe_cfunction, load_modules, ptrunion, CppEnum

# Convert path if it contains lib prefix on windows
function lib_path(so_path::AbstractString)
  path_copy = so_path
  @static if is_windows()
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
const jlcxx_path = _l_jlcxx

# Base type for wrapped C++ types
@compat abstract type CppAny end
@compat abstract type CppBits <: CppAny end
@compat abstract type CppDisplay <: Display end
@compat abstract type CppArray{T,N} <: AbstractArray{T,N} end
@compat abstract type CppAssociative{K,V} <: Associative{K,V} end

# Enum type interface
@compat abstract type CppEnum end
Base.convert(::Type{Int32}, x::CppEnum) = reinterpret(Int32, x)
import Base: +, |
+{T <: CppEnum}(a::T, b::T) = reinterpret(T, Int32(a) + Int32(b))
|{T <: CppEnum}(a::T, b::T) = reinterpret(T, Int32(a) | Int32(b))

cxxdowncast(x) = error("No downcast for type $(supertype(typeof(x))). Did you specialize SuperType to enable automatic downcasting?")

"""
Base class for smart pointers
"""
@compat abstract type SmartPointer{T} <: CppAny end

"""
Concrete smart pointer implementation. PT is a hash for the pointer types, DerefPtr a pointer to the dereference function,
ConstructPtr a function pointer to construct from a compatible smart pointer type (e.g. weak_ptr from shared_ptr)
CastPtr is a function pointer to cast to the direct base class
"""
type SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr} <: SmartPointer{T}
  ptr::Ptr{Void}
end

reference_type(t::Type) = Any

@generated function dereference_smart_pointer{T,PT,DerefPtr,ConstructPtr,CastPtr,DereferencedT}(p::SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}, ::Type{DereferencedT})
  quote
    ccall(DerefPtr, $DereferencedT, (Ptr{Void},), p.ptr)
  end
end

function Base.getindex{T,PT,DerefPtr,ConstructPtr,CastPtr}(p::SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr})::reference_type(T)
  return dereference_smart_pointer(p, reference_type(T))
end

# No conversion if source and target type are identical
Base.convert{T,PT,DerefPtr,ConstructPtr,CastPtr}(::Type{SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}}, p::SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}) = p

# Construct from a related pointer, e.g. a std::weak_ptr from std::shared_ptr
function Base.convert{T,PT1,PT2,B1,B2,B3,D1,D2,D3}(::Type{SmartPointerWithDeref{T,PT1,B1,B2,B3}}, p::SmartPointerWithDeref{T,PT2,D1,D2,D3})
  ccall(B2, Any, (Any,), p)
end

# Construct from a related pointer, downcasting the type to base class
function Base.convert{BaseT,DerivedT,PT1,PT2,B1,B2,B3,D1,D2,D3}(t::Type{SmartPointerWithDeref{BaseT,PT1,B1,B2,B3}}, p::SmartPointerWithDeref{DerivedT,PT2,D1,D2,D3})
  if !(DerivedT <: BaseT)
    error("$DerivedT does not inherit from $BaseT in smart pointer convert")
  end
  # First convert to base type
  base_p = ccall(D3, Any, (Ptr{Void},), p.ptr)
  return convert(t, base_p)
end

# Cast to base type enclosed in same pointer type
function Base.convert{BaseT,DerivedT,PT,B1,B2,B3,D1,D2,D3}(::Type{SmartPointerWithDeref{BaseT,PT,B1,B2,B3}}, p::SmartPointerWithDeref{DerivedT,PT,D1,D2,D3})
  if !(DerivedT <: BaseT)
    error("$DerivedT does not inherit from $BaseT in smart pointer convert")
  end
  return convert(SmartPointerWithDeref{BaseT,PT,B1,B2,B3}, ccall(D3, Any, (Ptr{Void},), p.ptr))
end

immutable StrictlyTypedNumber{NumberT}
  value::NumberT
end
Base.convert{NumberT}(::Type{StrictlyTypedNumber{NumberT}}, n::NumberT) = StrictlyTypedNumber{NumberT}(n)

immutable ConstPtr{T} <: CppBits
  ptr::Ptr{T}
end

immutable ConstArray{T,N} <: CppArray{T,N}
  ptr::ConstPtr{T}
  size::NTuple{N,Int}
end

# Encapsulate information about a function
type CppFunctionInfo
  name::Any
  argument_types::Array{Type,1}
  reference_argument_types::Array{Type,1}
  return_type::Type
  function_pointer::Ptr{Void}
  thunk_pointer::Ptr{Void}
end

function __init__()
  @static if is_windows()
    Libdl.dlopen(jlcxx_path, Libdl.RTLD_GLOBAL)
  end
  ccall((:initialize, jlcxx_path), Void, (Any, Any, Any), CxxWrap, CppAny, CppFunctionInfo)
  @compat Base.IndexStyle(::ConstArray) = IndexLinear()
  Base.size(arr::ConstArray) = arr.size
  Base.getindex(arr::ConstArray, i::Integer) = unsafe_load(arr.ptr.ptr, i)
end

# Load the modules in the shared library located at the given path
function load_modules(path::AbstractString, parent_module, wrapped_module)
  module_lib = Libdl.dlopen(path, Libdl.RTLD_GLOBAL)
  registry = ccall((:create_registry, jlcxx_path), Ptr{Void}, (Any,Any), parent_module, wrapped_module)
  ccall(Libdl.dlsym(module_lib, "register_julia_modules"), Void, (Ptr{Void},), registry)
  return registry
end

function get_modules(registry::Ptr{Void})
  ccall((:get_modules, jlcxx_path), Array{AbstractString}, (Ptr{Void},), registry)
end

function get_module_functions(registry::Ptr{Void})
  ccall((:get_module_functions, jlcxx_path), Array{CppFunctionInfo}, (Ptr{Void},), registry)
end

function bind_constants(registry::Ptr{Void}, m::Module)
  ccall((:bind_module_constants, jlcxx_path), Void, (Ptr{Void},Any), registry, m)
  return
end

function exported_symbols(registry::Ptr{Void}, modname::AbstractString)
  ccall((:get_exported_symbols, jlcxx_path), Array{AbstractString}, (Ptr{Void},AbstractString), registry, modname)
end

function reference_types(registry::Ptr{Void}, modname::AbstractString)
  ccall((:get_reference_types, jlcxx_path), Array{Type}, (Ptr{Void},AbstractString), registry, modname)
end

function allocated_types(registry::Ptr{Void}, modname::AbstractString)
  ccall((:get_allocated_types, jlcxx_path), Array{Type}, (Ptr{Void},AbstractString), registry, modname)
end

# Interpreted as a constructor for Julia  > 0.5
type ConstructorFname
  _type::DataType
end

# Interpreted as an operator call overload
type CallOpOverload
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
argument_overloads(t::Type{Float64}) = [Int]
function argument_overloads(t::Type{Array{AbstractString,1}})
  @static if VERSION < v"0.5-dev"
    return [Array{ASCIIString,1}]
  else
    return [Array{String,1}]
  end
end
argument_overloads{T <: Number}(t::Type{Ptr{T}}) = [Array{T,1}]

"""
Create a Union containing the type and a smart pointer to any type derived from it
"""
function ptrunion{T}(::Type{T})
  @compat result{T2 <: T} = Union{T2, SmartPointer{T2}}
  return result
end

smart_pointer_type(t::Type) = t
smart_pointer_type{T <: CppAny}(x::Type{T}) = ptrunion(x)
smart_pointer_type{T <: CppArray}(x::Type{T}) = ptrunion(x)
smart_pointer_type{T <: CppAssociative}(x::Type{T}) = ptrunion(x)

function smart_pointer_type{T,PT,DerefPtr,ConstructPtr,CastPtr}(::Type{SmartPointerWithDeref{T,PT,DerefPtr,ConstructPtr,CastPtr}})
  @compat result{T2 <: T} = SmartPointer{T2}
  return result
end

map_julia_arg_type(t::Type) = Union{smart_pointer_type(t),argument_overloads(t)...}
map_julia_arg_type{T}(a::Type{StrictlyTypedNumber{T}}) = T

# Build the expression to wrap the given function
function build_function_expression(func::CppFunctionInfo)
  # Arguments and types
  argtypes = func.argument_types
  argsymbols = map((i) -> Symbol(:arg,i[1]), enumerate(argtypes))

  # Function pointer
  fpointer = func.function_pointer
  assert(fpointer != C_NULL)

  # Thunk
  thunk = func.thunk_pointer

  map_c_arg_type(t::Type) = t
  map_c_arg_type{T <: AbstractString}(::Type{Array{T,1}}) = Any
  map_c_arg_type(::Type{Type}) = Any
  map_c_arg_type{T <: Tuple}(::Type{T}) = Any
  map_c_arg_type{T,N}(::Type{ConstArray{T,N}}) = Any
  map_c_arg_type{T <: SmartPointer}(::Type{T}) = Any

  map_return_type(t) = map_c_arg_type(t)
  map_return_type{T}(t::Type{Ref{T}}) = Ptr{T}

  # Build the types for the ccall argument list
  c_arg_types = [map_c_arg_type(t) for t in func.reference_argument_types]
  return_type = map_return_type(func.return_type)

  converted_args = ([:(Base.cconvert($t,$a)) for (t,a) in zip(func.reference_argument_types,argsymbols)]...)

  # Build the final call expression
  call_exp = nothing
  if thunk == C_NULL
    call_exp = :(ccall($fpointer, $return_type, ($(c_arg_types...),), $(converted_args...))) # Direct pointer call
  else
    call_exp = :(ccall($fpointer, $return_type, (Ptr{Void}, $(c_arg_types...)), $thunk, $(converted_args...))) # use thunk (= std::function)
  end
  assert(call_exp != nothing)

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
  mod_name = string(module_name(julia_mod))
  reftypes = reference_types(registry, mod_name)
  alloctypes = allocated_types(registry, mod_name)
  for (rt, at) in zip(reftypes, alloctypes)
    st = supertype(at)
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$rt) = x))
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$at) = unsafe_load(reinterpret(Ptr{$rt}, pointer_from_objref(x)))))
    Core.eval(Base, :(cconvert{T <: $st}(t::Type{$rt}, x::T) = Base.cconvert(t, $(cxxdowncast)(x))))
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$(SmartPointer{st})) = x[]))
    Core.eval(Base, :(cconvert{T <: $st}(t::Type{$rt}, x::$(SmartPointer){T}) = Base.cconvert(t, $(cxxdowncast)(x[]))))
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
    :size,
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
function wrap_modules(registry::Ptr{Void}, parent_mod=Main)
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
    exps = [Symbol(s) for s in exported_symbols(registry, string(jl_mod))]
    Core.eval(jl_mod, :(export $(exps...)))
  end
end

# Wrap modules in the given path
function wrap_modules(so_path::AbstractString, parent_mod=Main)
  registry = CxxWrap.load_modules(lib_path(so_path), parent_mod, nothing)
  wrap_modules(registry, parent_mod)
end

# Place the types for the module with the name corresponding to the current module name in the current module
function wrap_module_types(registry, parent_mod=Main)
  wanted_name = string(module_name(current_module()))
  bind_constants(registry, current_module())
  
  exps = [Symbol(s) for s in exported_symbols(registry, wanted_name)]
  Core.eval(current_module(), :(export $(exps...)))
end

function wrap_module_functions(registry, parent_mod=Main)
  modules = get_modules(registry)
  @assert length(modules) == 1
  mod_idx = 1

  if mod_idx == 0
    error("Module $wanted_name not found in C++")
  end

  module_functions = get_module_functions(registry)
  wrap_reference_converters(registry, current_module())
  wrap_functions(module_functions[mod_idx], current_module())
end

# Place the functions and types into the current module
function wrap_module(registry, parent_mod=Main)
  wrap_module_types(registry, parent_mod)
  wrap_module_functions(registry, parent_mod)
end

function wrap_module(so_path::AbstractString, parent_mod=Main)
  registry = CxxWrap.load_modules(lib_path(so_path), parent_mod, current_module())
  wrap_module(registry, parent_mod)
end

immutable SafeCFunction
  fptr::Ptr{Void}
  return_type::Type
  argtypes::Array{Type,1}
end

safe_cfunction(f::Function, rt::Type, args::Tuple) = SafeCFunction(cfunction(f, rt, args), rt, [t for t in args])

wstring_to_julia(p::Ptr{Cwchar_t}, L::Int) = transcode(String, unsafe_wrap(Array, p, L))
wstring_to_cpp(s::String) = transcode(Cwchar_t, s)

end # module
