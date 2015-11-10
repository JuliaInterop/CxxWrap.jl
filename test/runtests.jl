using CppWrapper
using Base.Test

# Wrap the functions defined in C++
CppWrapper.wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libfunctions"))

# Test functions from the CppHalfFunctions module
@test CppHalfFunctions.half_d(3) == 1.5
@test CppHalfFunctions.half_i(-2) == -1
@test CppHalfFunctions.half_u(3) == 1
@test CppHalfFunctions.half_lambda(2.) == 1.

# Test functions from the CppTestFunctions module
@test CppTestFunctions.concatenate_numbers(4, 2.) == "42"
@test length(methods(CppTestFunctions.concatenate_numbers)) == 4 # due to overloads
@test CppTestFunctions.concatenate_strings(2, "ho", "la") == "holahola"
