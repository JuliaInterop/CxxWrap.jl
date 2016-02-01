module CppWrapper

using BinDeps
@BinDeps.load_dependencies

const cpp_wrapper_lib = Libdl.dlopen(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libcpp_wrapper"), Libdl.RTLD_GLOBAL)

# Base type for wrapped C++ types
abstract CppAny

# Encapsulate information about a function
type CppFunctionInfo
  name::AbstractString
  argument_types::Array{DataType,1}
  return_type::DataType
  function_pointer::Ptr{Void}
  thunk_pointer::Ptr{Void}
end

function __init__()
  ccall(Libdl.dlsym(cpp_wrapper_lib, "initialize"), Void, (Any, Any, Any), CppWrapper, CppAny, CppFunctionInfo)
end

# Load the modules in the shared library located at the given path
function load_modules(path::AbstractString)
  module_lib = Libdl.dlopen(path, Libdl.RTLD_GLOBAL)
  registry = ccall(Libdl.dlsym(cpp_wrapper_lib, "create_registry"), Ptr{Void}, ())
  ccall(Libdl.dlsym(module_lib, "register_julia_modules"), Void, (Ptr{Void},), registry)
  return registry
end

function get_module_names(registry::Ptr{Void})
  ccall(Libdl.dlsym(cpp_wrapper_lib, "get_module_names"), Array{AbstractString}, (Ptr{Void},), registry)
end

function get_module_functions(registry::Ptr{Void})
  ccall(Libdl.dlsym(cpp_wrapper_lib, "get_module_functions"), Array{CppFunctionInfo}, (Ptr{Void},), registry)
end

function bind_types(registry::Ptr{Void}, m::Module)
  ccall(Libdl.dlsym(cpp_wrapper_lib, "bind_module_types"), Void, (Ptr{Void},Any), registry, m)
end

# Build the expression to wrap the given function
function build_function_expression(func::CppFunctionInfo)
  # Name of the function
  fname = symbol(func.name)

  # Arguments and types
  argtypes = func.argument_types
  argsymbols = map((i) -> symbol(:arg,i[1]), enumerate(argtypes))

  # Return type
  return_type = func.return_type

  # Function pointer
  fpointer = func.function_pointer
  assert(fpointer != C_NULL)

  # Thunk
  thunk = func.thunk_pointer

  # Build the types for the ccall argument list
  c_arg_types = DataType[]
  for argtype in argtypes
    if argtype <: CppAny
      push!(c_arg_types, Any)
    else
      push!(c_arg_types, argtype)
    end
  end

  # Build the final call expression
  call_exp = nothing
  if thunk == C_NULL
    call_exp = :(ccall($fpointer, $return_type, ($(c_arg_types...),), $(argsymbols...))) # Direct pointer call
  else
    call_exp = :(ccall($fpointer, $return_type, (Ptr{Void}, $(c_arg_types...)), $thunk, $(argsymbols...))) # use thunk (= std::function)
  end
  assert(call_exp != nothing)

  # Generate overloads for some types
  overload_map = Dict([(Cint,[Int]), (Cuint,[UInt,Int]), (Float64,[Int])])
  nargs = length(argtypes)

  counters = ones(Int, nargs);
  for i in 1:nargs
    if haskey(overload_map, argtypes[i])
        counters[i] += length(overload_map[argtypes[i]])
    end
  end

  function recurse_overloads!(idx::Int, newargs, results)
    if idx > nargs
        push!(results, deepcopy(newargs))
        return
    end
    for i in 1:counters[idx]
        newargs[idx] = i == 1 ? argtypes[idx] : overload_map[argtypes[idx]][i-1]
        recurse_overloads!(idx+1, newargs, results)
    end
  end

  newargs = Array{DataType,1}(nargs);
  overload_sigs = Array{Array{DataType,1},1}();
  recurse_overloads!(1, newargs, overload_sigs);

  function_expressions = quote end
  for overloaded_signature in overload_sigs
    argmap = Expr[]
    for (t, s) in zip(overloaded_signature, argsymbols)
      push!(argmap, :($s::$t))
    end

    func_declaration = :($fname($(argmap...)))
    push!(function_expressions.args, :($func_declaration = $call_exp))
  end

  return function_expressions
end

# Wrap functions from the cpp module to the passed julia module
function wrap_functions(functions, julia_mod)
  for func in functions
    if(func.name == "deepcopy_internal")
      Base.eval(build_function_expression(func))
    else
      julia_mod.eval(build_function_expression(func))
    end
  end
end

# Wrap all functions, placing the wrapper in the current module
function wrap_functions(functions)
  wrap_functions(functions, current_module())
end

# Create modules defined in the given library, wrapping all their functions and types
function wrap_modules(registry::Ptr{Void}, parent_mod=Main)
  module_names = get_module_names(registry)
  module_types = get_module_types(registry)
  jl_modules = Module[]
  for (mod_name, mod_types) in zip(module_names, module_types)
    modsym = symbol(mod_name)
    jl_mod = parent_mod.eval(:(module $modsym end))
    push!(jl_modules, jl_mod)
    bind_types(registry, jl_mod)
  end

  module_functions = get_module_functions(registry)
  for (jl_mod, mod_functions) in zip(jl_modules, module_functions)
    wrap_functions(mod_functions, jl_mod)
  end
end

# Wrap modules in the given path
function wrap_modules(so_path::AbstractString, parent_mod=Main)
  registry = CppWrapper.load_modules(so_path)
  wrap_modules(registry, parent_mod)
end

export wrap_modules

end # module
