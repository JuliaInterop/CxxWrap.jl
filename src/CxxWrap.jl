__precompile__()

module CxxWrap

using Compat

export wrap_modules, wrap_module, wrap_module_types, wrap_module_functions, safe_cfunction, load_modules

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
const cxx_wrap_path = _l_cxx_wrap

# Base type for wrapped C++ types
abstract CppAny
abstract CppBits <: CppAny
abstract CppDisplay <: Display
abstract CppArray{T,N} <: AbstractArray{T,N}
abstract CppAssociative{K,V} <: Associative{K,V}

abstract SmartPointer{T} <: CppAny

type SmartPointerWithDeref{T, DerefFunction} <: SmartPointer{T}
  ptr::Ptr{Void}
end

reference_type(t::DataType) = t

Base.getindex{T,DerefPtr}(p::SmartPointerWithDeref{T,DerefPtr})::reference_type(T) = ccall(DerefPtr, reference_type(T), (Ptr{Void},), p.ptr)

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
  argument_types::Array{DataType,1}
  reference_argument_types::Array{DataType,1}
  return_type::DataType
  function_pointer::Ptr{Void}
  thunk_pointer::Ptr{Void}
end

function __init__()
  @static if is_windows()
    Libdl.dlopen(cxx_wrap_path, Libdl.RTLD_GLOBAL)
  end
  ccall((:initialize, cxx_wrap_path), Void, (Any, Any, Any), CxxWrap, CppAny, CppFunctionInfo)

  Base.linearindexing(::ConstArray) = Base.LinearFast()
  Base.size(arr::ConstArray) = arr.size
  Base.getindex(arr::ConstArray, i::Integer) = unsafe_load(arr.ptr.ptr, i)
end

# Load the modules in the shared library located at the given path
function load_modules(path::AbstractString)
  module_lib = Libdl.dlopen(path, Libdl.RTLD_GLOBAL)
  registry = ccall((:create_registry, cxx_wrap_path), Ptr{Void}, ())
  ccall(Libdl.dlsym(module_lib, "register_julia_modules"), Void, (Ptr{Void},), registry)
  return registry
end

function get_module_names(registry::Ptr{Void})
  ccall((:get_module_names, cxx_wrap_path), Array{AbstractString}, (Ptr{Void},), registry)
end

function get_module_functions(registry::Ptr{Void})
  ccall((:get_module_functions, cxx_wrap_path), Array{CppFunctionInfo}, (Ptr{Void},), registry)
end

function bind_constants(registry::Ptr{Void}, m::Module)
  ccall((:bind_module_constants, cxx_wrap_path), Void, (Ptr{Void},Any), registry, m)
end

function exported_symbols(registry::Ptr{Void}, modname::AbstractString)
  ccall((:get_exported_symbols, cxx_wrap_path), Array{AbstractString}, (Ptr{Void},AbstractString), registry, modname)
end

function reference_types(registry::Ptr{Void}, modname::AbstractString)
  ccall((:get_reference_types, cxx_wrap_path), Array{DataType}, (Ptr{Void},AbstractString), registry, modname)
end

function allocated_types(registry::Ptr{Void}, modname::AbstractString)
  ccall((:get_allocated_types, cxx_wrap_path), Array{DataType}, (Ptr{Void},AbstractString), registry, modname)
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
argument_overloads(t::DataType) = DataType[]
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

smart_pointer_type(t::DataType) = t
smart_pointer_type{T <: CppAny}(::Type{T}) = SmartPointer{T}

map_julia_arg_type(t::DataType) = Union{t,smart_pointer_type(t),argument_overloads(t)...}
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

  map_c_arg_type(t::DataType) = t
  map_c_arg_type{T <: AbstractString}(::Type{Array{T,1}}) = Any
  map_c_arg_type(::Type{DataType}) = Any
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
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$st) = unsafe_load(reinterpret(Ptr{$rt}, pointer_from_objref(x)))))
    Core.eval(Base, :(cconvert(::Type{$rt}, x::$(SmartPointer{st})) = x[]))
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
  for func in functions
    if func.name ∈ basenames
      Core.eval(Base, build_function_expression(func))
    else
      Core.eval(julia_mod, build_function_expression(func))
    end
  end
end

# Create modules defined in the given library, wrapping all their functions and types
function wrap_modules(registry::Ptr{Void}, parent_mod=Main)
  module_names = get_module_names(registry)
  jl_modules = Module[]
  for mod_name in module_names
    modsym = Symbol(mod_name)
    if isdefined(parent_mod, modsym)
      jl_mod = getfield(parent_mod, modsym)
    else
      jl_mod = Core.eval(parent_mod, :(module $modsym end))
    end
    push!(jl_modules, jl_mod)
    bind_constants(registry, jl_mod)
  end

  module_functions = get_module_functions(registry)
  for (jl_mod, mod_functions) in zip(jl_modules, module_functions)
    wrap_reference_converters(registry, jl_mod)
    wrap_functions(mod_functions, jl_mod)
  end

  for (jl_mod, mod_name) in zip(jl_modules, module_names)
    exps = [Symbol(s) for s in exported_symbols(registry, mod_name)]
    Core.eval(jl_mod, :(export $(exps...)))
  end
end

# Wrap modules in the given path
function wrap_modules(so_path::AbstractString, parent_mod=Main)
  registry = CxxWrap.load_modules(lib_path(so_path))
  wrap_modules(registry, parent_mod)
end

# Place the types for the module with the name corresponding to the current module name in the current module
function wrap_module_types(registry, parent_mod=Main)
  module_names = get_module_names(registry)
  mod_idx = 0
  wanted_name = string(module_name(current_module()))
  for (i,mod_name) in enumerate(module_names)
    if mod_name == wanted_name
      bind_constants(registry, current_module())
      mod_idx = i
      break
    end
  end

  if mod_idx == 0
    error("Module $wanted_name not found in C++")
  end

  exps = [Symbol(s) for s in exported_symbols(registry, wanted_name)]
  Core.eval(current_module(), :(export $(exps...)))
end

function wrap_module_functions(registry, parent_mod=Main)
  module_names = get_module_names(registry)
  mod_idx = 0
  wanted_name = string(module_name(current_module()))
  for (i,mod_name) in enumerate(module_names)
    if mod_name == wanted_name
      mod_idx = i
      break
    end
  end

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
  registry = CxxWrap.load_modules(lib_path(so_path))
  wrap_module(registry, parent_mod)
end

immutable SafeCFunction
  fptr::Ptr{Void}
  return_type::DataType
  argtypes::Array{DataType,1}
end

safe_cfunction(f::Function, rt::DataType, args::Tuple) = SafeCFunction(cfunction(f, rt, args), rt, [t for t in args])

end # module
