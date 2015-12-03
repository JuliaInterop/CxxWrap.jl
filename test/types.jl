# Hello world example, similar to the Boost.Python hello world

using CppWrapper
using Base.Test

# Wrap the functions defined in C++
wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libtypes"))

using CppTypes
using CppTypes.World

# Default constructor
@test World <: CppWrapper.CppAny
@test super(World) == CppWrapper.CppAny
w = World()
@test CppTypes.greet(w) == "default hello"

CppTypes.set(w, "hello")
@show CppTypes.greet(w)
@test CppTypes.greet(w) == "hello"

w = World("constructed")
@test CppTypes.greet(w) == "constructed"

delete(w)
@test_throws ErrorException CppTypes.greet(w)
