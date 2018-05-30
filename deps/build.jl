using Compat
using BinDeps
import BinDeps.generate_steps

const JLCXX_VERSION = v"0.2.3"
const use_master = false

JLCXX_LIBDIR=get(ENV, "JLCXX_LIBDIR", "")

function generate_steps(dep::BinDeps.LibraryDependency,h::BinDeps.CustomPathBinaries,opts)
    steps = @build_steps begin
        BinDeps.ChecksumValidator(get(opts,:SHA,get(opts,:sha,"")),h.path)
    end
end

function prompt_cmake()
  try
    run(pipeline(`cmake --version`, stdout=DevNull, stderr=DevNull))
    return
  catch
    error("command \"cmake\" not found in path, please install CMake and make sure it can be found")
  end
end

@static if is_windows()
  # prefer building if requested
  if haskey(ENV, "BUILD_ON_WINDOWS") && ENV["BUILD_ON_WINDOWS"] == "1" && JLCXX_LIBDIR == ""
    prompt_cmake()
    saved_defaults = deepcopy(BinDeps.defaults)
    empty!(BinDeps.defaults)
    append!(BinDeps.defaults, [BuildProcess])
  end
else
  prompt_cmake()
end

@BinDeps.setup

build_type = get(ENV, "JLCXX_BUILD_TYPE", "Release")
build_examples = get(ENV, "JLCXX_BUILD_EXAMPLES", "ON")

# List of the libraries that will be built
lib_labels = [:cxxwrap_julia]
if build_examples == "ON"
  lib_labels = vcat(lib_labels, [:jlcxx_containers, :except, :extended, :functions, :hello, :inheritance, :parametric, :types])
end
deps = BinDeps.LibraryDependency[]
for l in lib_labels
  @eval $l = $(library_dependency(string(l), aliases=["lib"*string(l)]))
  push!(deps, eval(:($l)))
end

dep = first(deps)
depsdir = BinDeps.depsdir(dep)
if use_master
  provides(Sources,URI("https://github.com/JuliaInterop/libcxxwrap-julia/archive/master.zip"), dep, unpacked_dir="libcxxwrap-julia-master")
  jlcxx_srcdir = joinpath(depsdir, "src", "libcxxwrap-julia-master")
else
  provides(Sources,URI("https://github.com/JuliaInterop/libcxxwrap-julia/archive/v$(JLCXX_VERSION).zip"), dep, unpacked_dir="libcxxwrap-julia-$(JLCXX_VERSION)")
  jlcxx_srcdir = joinpath(depsdir, "src", "libcxxwrap-julia-$(JLCXX_VERSION)")
end

if JLCXX_LIBDIR != ""
  saved_defaults = deepcopy(BinDeps.defaults)
  empty!(BinDeps.defaults)
  append!(BinDeps.defaults, [Binaries])
  provides(Binaries, Dict(JLCXX_LIBDIR => deps))
end

prefix = joinpath(depsdir, "usr")

@static if is_windows()
    bindir = joinpath(prefix, "bin")
else
    bindir = joinpath(prefix, "lib")
end

jlcxx_builddir = joinpath(depsdir, "builds", "jlcxx")
lib_prefix = @static is_windows() ? "" : "lib"
lib_suffix = @static is_windows() ? "dll" : (@static is_apple() ? "dylib" : "so")
julia_base_dir = splitdir(JULIA_HOME)[1]
julia_executable = split(string(Base.julia_cmd()))[1][2:end]

makeopts = ["--", "-j", "$(Sys.ARCH == :armv7l ? 2 : Sys.CPU_CORES+2)"]

# Set generator if on windows
genopt = "Unix Makefiles"
@static if is_windows()
  if isdir(prefix)
    rm(prefix, recursive=true)
  end
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

deps_paths = AbstractString[]
for l in lib_labels
  push!(deps_paths, joinpath(bindir, "$(lib_prefix)$(string(l)).$lib_suffix"))
end

cxx_steps = @build_steps begin
  `cmake -G "$genopt" -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE="$build_type" -DCMAKE_PROGRAM_PATH=$JULIA_HOME -DJLCXX_BUILD_EXAMPLES=$build_examples -DJLCXX_BUILD_TESTS=OFF -DCMAKE_INSTALL_LIBDIR=lib $jlcxx_srcdir`
  `cmake --build . --config $build_type --target install $makeopts`
end

# If built, always run cmake, in case the code changed
if isdir(jlcxx_builddir)
  BinDeps.run(@build_steps begin
    ChangeDirectory(jlcxx_builddir)
    cxx_steps
  end)
end

provides(BuildProcess,
  (@build_steps begin
    GetSources(dep)
    CreateDirectory(jlcxx_builddir)
    @build_steps begin
      ChangeDirectory(jlcxx_builddir)
      FileRule(deps_paths, cxx_steps)
    end
  end), deps)

@static if is_windows()
  shortversion = "$(VERSION.major).$(VERSION.minor)"
  zipfilename = "jlcxx-julia$(shortversion)-$(Sys.WORD_SIZE)-v$(JLCXX_VERSION).zip"
  archname = Sys.WORD_SIZE == 64 ? "x64" : "x86"
  pkgverstring = string(JLCXX_VERSION)
  if use_master
    bin_uri = URI("https://ci.appveyor.com/api/projects/barche/libcxxwrap-julia/artifacts/$(zipfilename)?job=Environment%3a+JULIA_URL%3dhttps%3A%2F%2Fjulialang-s3.julialang.org%2Fbin%2Fwinnt%2f$(archname)%2f$(shortversion)%2fjulia-$(shortversion)-latest-win$(Sys.WORD_SIZE).exe%2c+CMAKE_GEN%3dVisual%20Studio%2014%202015$(Sys.WORD_SIZE==64 ? "%20Win64" : "")")
  else
    bin_uri = URI("https://github.com/JuliaInterop/libcxxwrap-julia/releases/download/v$(pkgverstring)/$(zipfilename)")
  end
  provides(Binaries, Dict(bin_uri => deps), os = :Windows)
end

if build_examples == "ON"
  @BinDeps.install Dict([(:cxxwrap_julia, :_l_jlcxx),
                         (:jlcxx_containers, :_l_containers),
                         (:except, :_l_except),
                         (:extended, :_l_extended),
                         (:functions, :_l_functions),
                         (:hello, :_l_hello),
                         (:inheritance, :_l_inheritance),
                         (:parametric, :_l_parametric),
                         (:types, :_l_types)])
else
  @BinDeps.install Dict([(:cxxwrap_julia, :_l_jlcxx)])
end

@static if is_windows()
  if haskey(ENV, "BUILD_ON_WINDOWS") && ENV["BUILD_ON_WINDOWS"] == "1" && JLCXX_LIBDIR == ""
    empty!(BinDeps.defaults)
    append!(BinDeps.defaults, saved_defaults)
  end
end

if JLCXX_LIBDIR != ""
  empty!(BinDeps.defaults)
  append!(BinDeps.defaults, saved_defaults)
end
