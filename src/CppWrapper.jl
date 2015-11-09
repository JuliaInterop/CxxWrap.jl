module CppWrapper

using BinDeps
@BinDeps.load_dependencies

const cpp_wrapper_lib = Libdl.dlopen(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libcpp_wrapper"), Libdl.RTLD_GLOBAL)

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

# Build the expression to wrap the given function
function build_function_expression(func)
  # Name of the function
  fname = symbol(ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_name"), Any, (Ptr{Void},), func))

  # Arguments and types
  argtypes = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_arguments"), Array{DataType, 1}, (Ptr{Void},), func)
  argsymbols = map((i) -> symbol(:arg,i[1]), enumerate(argtypes))
  argmap = Expr[]
  for (t, s) in zip(argtypes, argsymbols)
    push!(argmap, :($s::$t))
  end

  # Return type and conversion
  return_type = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_return_type"), Any, (Ptr{Void},), func)
  needs_convert = Bool(ccall(Libdl.dlsym(cpp_wrapper_lib, "get_function_needs_convert"), Cuchar, (Ptr{Void},), func))

  # Build conversion expression
  conversion_expression = nothing
  if(needs_convert)
    conversion_func = ccall(Libdl.dlsym(cpp_wrapper_lib, "get_conversion_function"), Ptr{Void}, (Ptr{Void},), func)
    if(conversion_func == C_NULL)
      throw(KeyError("Conversion function for $fname return type $return_type"))
    end
  end

  quote
    function $fname($(argmap...))
      println("Calling function ", string($fname))
    end
  end
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

# Create modules defined in the given library, wrapping all their functions
function wrap_modules(so_path, parent_mod=Main)
  modules = CppWrapper.load_modules(eval(so_path))
  for cpp_mod in modules
    modsym = symbol(get_module_name(cpp_mod))
    jl_mod = parent_mod.eval(:(module $modsym end))
    wrap_functions(cpp_mod, jl_mod)
  end
end

end # module
