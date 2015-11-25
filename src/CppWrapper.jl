module CppWrapper

using BinDeps
@BinDeps.load_dependencies

const cpp_wrapper_lib = Libdl.dlopen(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libcpp_wrapper"), Libdl.RTLD_GLOBAL)

# Base type for wrapped C++ types
abstract CppType

# Load the modules in the shared library located at the given path
function load_modules(path::AbstractString)
  module_lib = Libdl.dlopen(path, Libdl.RTLD_GLOBAL)
  registry = ccall(Libdl.dlsym(cpp_wrapper_lib, "create_registry"), Ptr{Void}, ())
  ccall(Libdl.dlsym(module_lib, "register_julia_modules"), Void, (Ptr{Void},), registry)
  modules = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_modules"), Array{Ptr{Void}}, (Ptr{Void},), registry)
end

get_module_name(mod) = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_module_name"), Any, (Ptr{Void},), mod)

# Given an array of modules, find the one with the passed name
function get_module_by_name(modules, searched_name::AbstractString)
  for mod in modules
    name = get_module_name(mod)
    if(name == searched_name)
      return mod
    end
  end
  throw(KeyError(searched_name))
end

# Get the functions of the given module
get_functions(mod) = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_functions"), Array{Ptr{Void}, 1}, (Ptr{Void},), mod)

# Get the function name for a given function
get_function_name(func) = symbol(ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_name"), Any, (Ptr{Void},), func))

# Build the expression to wrap the given function
function build_function_expression(func)
  # Name of the function
  fname = get_function_name(func)

  # Arguments and types
  argtypes = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_arguments"), Array{DataType,1}, (Ptr{Void},), func)
  argsymbols = map((i) -> symbol(:arg,i[1]), enumerate(argtypes))

  # Return type
  return_type = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_return_type"), Any, (Ptr{Void},), func)

  # Function pointer
  fpointer = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_pointer"), Ptr{Void}, (Ptr{Void},), func)
  assert(fpointer != C_NULL)

  # Thunk
  thunk = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_thunk"), Ptr{Void}, (Ptr{Void},), func)

  # Build the types for the ccall argument list
  c_arg_types = DataType[]
  for argtype in argtypes
    if argtype <: CppType
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

  function_expressions
  return function_expressions
end

# Wrap functions from the cpp module to the passed julia module
function wrap_functions(cpp_mod, julia_mod)
  functions = get_functions(cpp_mod)
  for func in functions
    julia_mod.eval(build_function_expression(func))
  end
end

# Wrap all functions, placing the wrapper in the current module
function wrap_functions(cpp_mod)
  wrap_functions(cpp_mod, current_module())
end

# Create modules defined in the given library, wrapping all their functions and types
function wrap_modules(so_path, parent_mod=Main)
  modules = CppWrapper.load_modules(eval(so_path))
  for cpp_mod in modules
    modsym = symbol(get_module_name(cpp_mod))
    jl_mod = parent_mod.eval(:(module $modsym end))
    ccall(Libdl.dlsym(cpp_wrapper_lib, "create_types"), Void, (Any,Ptr{Void}), jl_mod, cpp_mod)
    wrap_functions(cpp_mod, jl_mod)
  end
end

export wrap_modules

end # module
