using Compat
using BinDeps

function prompt_cmake()
  try
    run(pipeline(`cmake --version`, stdout=DevNull, stderr=DevNull))
    return
  catch
    error("command \"cmake\" not found in path, please install CMake and make sure it can be found")
  end
end

libdir_opt = ""
@static if is_windows()
  libdir_opt = Sys.WORD_SIZE==32 ? "32" : ""
end

@static if is_windows()
  # prefer building if requested
  if haskey(ENV, "BUILD_ON_WINDOWS") && ENV["BUILD_ON_WINDOWS"] == "1"
    prompt_cmake()
    saved_defaults = deepcopy(BinDeps.defaults)
    empty!(BinDeps.defaults)
    append!(BinDeps.defaults, [BuildProcess])
  end
else
  prompt_cmake()
end


@BinDeps.setup

function find_julia_lib(lib_suffix::AbstractString, julia_base_dir::AbstractString)
  julia_lib = joinpath(julia_base_dir, "lib", "julia", "libjulia.$lib_suffix")
  if !isfile(julia_lib)
    julia_lib = joinpath(julia_base_dir, "lib", "libjulia.$lib_suffix")
  end
  if !isfile(julia_lib)
    julia_lib = joinpath(julia_base_dir, "lib64", "julia", "libjulia.$lib_suffix")
  end
  if !isfile(julia_lib)
    julia_lib = joinpath(julia_base_dir, "lib64", "libjulia.$lib_suffix")
  end
  if !isfile(julia_lib)
    julia_lib = joinpath(julia_base_dir, "lib", "x86_64-linux-gnu", "julia", "libjulia.$lib_suffix")
  end
  if !isfile(julia_lib)
    julia_lib = joinpath(julia_base_dir, "lib", "x86_64-linux-gnu", "libjulia.$lib_suffix")
  end
  return julia_lib
end

# The base library, needed to wrap functions
cxx_wrap = library_dependency("cxx_wrap", aliases=["libcxx_wrap"])

prefix=joinpath(BinDeps.depsdir(cxx_wrap),"usr")
cxx_wrap_srcdir = joinpath(BinDeps.depsdir(cxx_wrap),"src","cxx_wrap")
cxx_wrap_builddir = joinpath(BinDeps.depsdir(cxx_wrap),"builds","cxx_wrap")
lib_prefix = @static is_windows() ? "" : "lib"
lib_suffix = @static is_windows() ? "dll" : (@static is_apple() ? "dylib" : "so")
julia_base_dir = splitdir(JULIA_HOME)[1]
julia_lib = ""
for suff in ["dll", "dll.a", "dylib", "so"]
  julia_lib = find_julia_lib(suff, julia_base_dir)
  if isfile(julia_lib)
    println("Found Julia library at ", julia_lib)
    break
  end
end

if !isfile(julia_lib)
  throw(ErrorException("Could not locate Julia library at $julia_lib"))
end

julia_include_dir = joinpath(julia_base_dir, "include", "julia")
if !isdir(julia_include_dir)  # then we're running directly from build
  julia_base_dir_aux = splitdir(splitdir(JULIA_HOME)[1])[1]  # useful for running-from-build
  julia_include_dir = joinpath(julia_base_dir_aux, "usr", "include" )
  julia_include_dir *= ";" * joinpath(julia_base_dir_aux, "src", "support" )
  julia_include_dir *= ";" * joinpath(julia_base_dir_aux, "src" )
end

makeopts = ["--", "-j", "$(Sys.ARCH == :armv7l ? 2 : Sys.CPU_CORES+2)"]

# Set generator if on windows
genopt = "Unix Makefiles"
@static if is_windows()
  if get(ENV, "MSYSTEM", "") == ""
    makeopts = "--"
    if Sys.WORD_SIZE == 64
      genopt = "Visual Studio 14 2015 Win64"
    else
      genopt = "Visual Studio 14 2015"
    end
  else
    lib_prefix = "lib" #Makefiles on windows do keep the lib prefix
  end
end

# Functions library for testing
example_labels = [:cxxwrap_containers, :except, :extended, :functions, :hello, :inheritance, :parametric, :types]
examples = BinDeps.LibraryDependency[]
for l in example_labels
  @eval $l = $(library_dependency(string(l), aliases=["lib"*string(l)]))
  push!(examples, eval(:($l)))
end
examples_srcdir = joinpath(BinDeps.depsdir(functions),"src","examples")
examples_builddir = joinpath(BinDeps.depsdir(functions),"builds","examples")
deps = [cxx_wrap; examples]

cxx_steps = @build_steps begin
  `cmake -G "$genopt" -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE="Release"  -DJULIA_INCLUDE_DIRECTORY="$julia_include_dir" -DJULIA_LIBRARY="$julia_lib" -DLIBDIR_SUFFIX=$libdir_opt $cxx_wrap_srcdir`
  `cmake --build . --config Release --target install $makeopts`
end

example_paths = AbstractString[]
for l in example_labels
  push!(example_paths, joinpath(prefix,"lib$libdir_opt", "$(lib_prefix)$(string(l)).$lib_suffix"))
end

examples_steps = @build_steps begin
  `cmake -G "$genopt" -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE="Release" -DLIBDIR_SUFFIX=$libdir_opt $examples_srcdir`
  `cmake --build . --config Release --target install $makeopts`
end

# If built, always run cmake, in case the code changed
if isdir(cxx_wrap_builddir)
  BinDeps.run(@build_steps begin
    ChangeDirectory(cxx_wrap_builddir)
    cxx_steps
  end)
end
if isdir(examples_builddir)
  BinDeps.run(@build_steps begin
    ChangeDirectory(examples_builddir)
    examples_steps
  end)
end

provides(BuildProcess,
  (@build_steps begin
    CreateDirectory(cxx_wrap_builddir)
    @build_steps begin
      ChangeDirectory(cxx_wrap_builddir)
      FileRule(joinpath(prefix,"lib$libdir_opt", "$(lib_prefix)cxx_wrap.$lib_suffix"),cxx_steps)
    end
  end), cxx_wrap)

provides(BuildProcess,
  (@build_steps begin
    CreateDirectory(examples_builddir)
    @build_steps begin
      ChangeDirectory(examples_builddir)
      FileRule(example_paths, examples_steps)
    end
  end), examples)

@static if is_windows()
  provides(Binaries, Dict(URI("https://github.com/JuliaInterop/CxxWrap.jl/releases/download/v0.1.8/CxxWrap-julia-$(VERSION.major).$(VERSION.minor)-win$(Sys.WORD_SIZE).zip") => deps), os = :Windows)
end

@BinDeps.install Dict([(:cxx_wrap, :_l_cxx_wrap),
                       (:cxxwrap_containers, :_l_containers),
                       (:except, :_l_except),
                       (:extended, :_l_extended),
                       (:functions, :_l_functions),
                       (:hello, :_l_hello),
                       (:inheritance, :_l_inheritance),
                       (:parametric, :_l_parametric),
                       (:types, :_l_types)])

@static if is_windows()
  if haskey(ENV, "BUILD_ON_WINDOWS") && ENV["BUILD_ON_WINDOWS"] == "1"
    empty!(BinDeps.defaults)
    append!(BinDeps.defaults, saved_defaults)
  end
end
