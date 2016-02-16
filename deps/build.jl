using BinDeps

@BinDeps.setup

# The base library, needed to wrap functions
cpp_wrapper = library_dependency("cpp_wrapper", aliases=["libcpp_wrapper"])

prefix=joinpath(BinDeps.depsdir(cpp_wrapper),"usr")
cpp_wrapper_srcdir = joinpath(BinDeps.depsdir(cpp_wrapper),"src","cpp_wrapper")
cpp_wrapper_builddir = joinpath(BinDeps.depsdir(cpp_wrapper),"builds","cpp_wrapper")
lib_suffix = @windows? "dll" : (@osx? "dylib" : "so")
julia_base_dir = splitdir(JULIA_HOME)[1]
julia_lib = joinpath(julia_base_dir, "lib", "julia", "libjulia.$lib_suffix")
if !isfile(julia_lib)
	julia_lib = joinpath(julia_base_dir, "lib", "libjulia.$lib_suffix")
end
if !isfile(julia_lib)
	julia_lib = joinpath(julia_base_dir, "lib64", "julia", "libjulia.$lib_suffix")
end
if !isfile(julia_lib)
	throw(ErrorException("Could not locate Julia library at $julia_lib"))
end
julia_include_dir = joinpath(julia_base_dir, "include", "julia")
provides(BuildProcess,
	(@build_steps begin
		CreateDirectory(cpp_wrapper_builddir)
		@build_steps begin
			ChangeDirectory(cpp_wrapper_builddir)
			FileRule(joinpath(prefix,"lib", "libcpp_wrapper.$lib_suffix"),@build_steps begin
				`cmake -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE="Release"  -DJULIA_INCLUDE_DIRECTORY="$julia_include_dir" -DJULIA_LIBRARY="$julia_lib" $cpp_wrapper_srcdir`
				`make`
				`make install`
			end)
		end
	end),cpp_wrapper)

# Functions library for testing
examples = library_dependency("functions", aliases=["libfunctions"])

examples_srcdir = joinpath(BinDeps.depsdir(examples),"src","examples")
examples_builddir = joinpath(BinDeps.depsdir(examples),"builds","examples")
provides(BuildProcess,
	(@build_steps begin
		CreateDirectory(examples_builddir)
		@build_steps begin
			ChangeDirectory(examples_builddir)
			FileRule(joinpath(prefix,"lib", "libfunctions.$lib_suffix"),@build_steps begin
				`cmake -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE="Release" $examples_srcdir`
				`make`
				`make install`
			end)
		end
	end),examples)

@BinDeps.install
