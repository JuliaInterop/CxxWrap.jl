isdefined(Base, :__precompile__) && __precompile__()

module CxxWrap

using Compat

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

# C++ std::shared_ptr
type SharedPtr{T} <: CppAny
  cpp_object::Ptr{Void}
end

# C++ std::unique_ptr
type UniquePtr{T} <: CppAny
  cpp_object::Ptr{Void}
end

immutable StrictlyTypedNumber{NumberT}
  value::NumberT
end

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
  if VERSION < v"0.5-dev"
    return :call
  end
  return :(arg1::$(fn._type))
end

make_func_declaration(fn, argmap) = :($(process_fname(fn))($(argmap...)))
function make_func_declaration(fn::CallOpOverload, argmap)
  if VERSION < v"0.5-dev"
    return :($(process_fname(fn))($(argmap...)))
  end
  return :($(process_fname(fn))($((argmap[2:end])...)))
end

function make_overloaded_call(fn, argtypes, argsymbols)
  return :(invoke($(process_fname(fn)), ($(argtypes...),), $([:(convert($t, $a)) for (t,a) in zip(argtypes, argsymbols)]...)))
end

function make_overloaded_call(fn::ConstructorFname, argtypes, argsymbols)
  if VERSION < v"0.5-dev"
    return invoke(make_overloaded_call, (Any,Any,Any), :call, argtypes, argsymbols)
  end
  return :(invoke($(fn._type), ($(argtypes...),), $([:(convert($t, $a)) for (t,a) in zip(argtypes, argsymbols)]...)))
end

function make_overloaded_call(fn::CallOpOverload, argtypes, argsymbols)
  if VERSION < v"0.5-dev"
    return invoke(make_overloaded_call, (Any,Any,Any), :call, argtypes, argsymbols)
  end
  return :(invoke(arg1, ($((argtypes[2:end])...),), $([:(convert($t, $a)) for (t,a) in zip(argtypes[2:end], argsymbols[2:end])]...)))
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

  function map_c_arg_type(t::DataType)
    if(t <: CppBits)
      return t
    end
    if ((t <: CppAny) || (t <: CppDisplay) || (t <: Tuple)) || (t <: CppArray)
      return Any
    end

    if t == Array{AbstractString,1} || t == Array{String,1}
      return Any
    end

    return t
  end
  map_c_arg_type{T}(a::Type{StrictlyTypedNumber{T}}) = T

  map_julia_arg_type(t::DataType) = t
  map_julia_arg_type{T}(a::Type{StrictlyTypedNumber{T}}) = T

  # Build the types for the ccall argument list
  c_arg_types = [map_c_arg_type(t) for t in argtypes]
  return_type = map_c_arg_type(func.return_type)

  # Build the final call expression
  call_exp = nothing
  if thunk == C_NULL
    call_exp = :(ccall($fpointer, $return_type, ($(c_arg_types...),), $(argsymbols...))) # Direct pointer call
  else
    call_exp = :(ccall($fpointer, $return_type, (Ptr{Void}, $(c_arg_types...)), $thunk, $(argsymbols...))) # use thunk (= std::function)
  end
  assert(call_exp != nothing)

  nargs = length(argtypes)

  function recurse_overloads!(idx::Int, newargs, results)
    if idx > nargs
        push!(results, deepcopy(newargs))
        return
    end
    for i in 1:(length(argument_overloads(argtypes[idx]))+1)
        newargs[idx] = i == 1 ? argtypes[idx] : argument_overloads(argtypes[idx])[i-1]
        recurse_overloads!(idx+1, newargs, results)
    end
  end

  newargs = Array{DataType,1}(nargs);
  overload_sigs = Array{Array{DataType,1},1}();
  recurse_overloads!(1, newargs, overload_sigs);

  # Build an array of arg1::Type1... expressions
  function argmap(signature)
    result = Expr[]
    for (t, s) in zip(signature, argsymbols)
      push!(result, :($s::$(map_julia_arg_type(t))))
    end
    return result
  end

  function_expressions = [:($(make_func_declaration(func.name, argmap(argtypes))) = $call_exp)]
  for signature in overload_sigs[2:end] # the first "overload" is the same as the base signature, so skip it
    push!(function_expressions, :($(make_func_declaration(func.name, argmap(signature))) = $(make_overloaded_call(func.name, [map_julia_arg_type(t) for t in argtypes], argsymbols))))
  end
  return function_expressions
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
    if in(func.name, basenames)
      for f in build_function_expression(func)
        Core.eval(Base, f)
      end
    else
      for f in build_function_expression(func)
        Core.eval(julia_mod, f)
      end
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

# Place the functions and types into the current module
function wrap_module(registry, parent_mod=Main)
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

  module_functions = get_module_functions(registry)
  wrap_functions(module_functions[mod_idx], current_module())

  exps = [Symbol(s) for s in exported_symbols(registry, wanted_name)]
  Core.eval(current_module(), :(export $(exps...)))
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

export wrap_modules, wrap_module, safe_cfunction, load_modules

end # module
