# Hello world example, similar to the Boost.Python hello world
include(joinpath(@__DIR__, "testcommon.jl"))

# Wrap the functions defined in C++
wrap_modules(libhello)

# Output:
@show CppHello.greet()

# Test the result
@test CppHello.greet() == "hello, world"
