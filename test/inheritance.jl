# Hello world example, similar to the Boost.Python hello world

using CppWrapper
using Base.Test

# Wrap the functions defined in C++
wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libinheritance"))

using CppInheritance.A, CppInheritance.B

# Default constructor
b = B()
@test CppInheritance.message(b) == "B"
