# Hello world example, similar to the Boost.Python hello world

using CppWrapper
using Base.Test

# Wrap the functions defined in C++
wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libtypes"))

# Default constructor
@test CppTypes.World <: CppWrapper.CppType
@test super(CppTypes.World) == CppWrapper.CppType
w = CppTypes.World()

CppTypes.set(w, "hello")
@show CppTypes.greet(w)
@test CppTypes.greet(w) == "hello"
