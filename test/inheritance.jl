# Hello world example, similar to the Boost.Python hello world

println("Running inheritace.jl...")

using CxxWrap
using Base.Test

# Wrap the functions defined in C++
wrap_modules(CxxWrap._l_inheritance)

using CppInheritance.A, CppInheritance.B

# Default constructor
b = B()
@test CppInheritance.message(b) == "B"
