using CppWrapper
using Base.Test

# Wrap the functions defined in C++
CppWrapper.wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libfunctions"))

# Test functions from the CppHalfFunctions module
@test CppHalfFunctions.half_d(3.) == 1.5
@test CppHalfFunctions.half_i(Cint(-2)) == -1
@test CppHalfFunctions.half_u(Cuint(3)) == 1
@test CppHalfFunctions.half_lambda(2.) == 1.

# Test functions from the CppTestFunctions module
@show CppTestFunctions.concatenate_numbers(Cint(4), 2.)
@show methods(CppTestFunctions.concatenate_strings)
@show CppTestFunctions.concatenate_strings(Cint(2), "ho", "la")
