# Wrap the functions defined in C++
module CppHello
  include(joinpath(@__DIR__, "testcommon.jl"))
  @wrapmodule libhello
end

using Test

# Output:
@show CppHello.greet()

# Test the result
@test CppHello.greet() == "hello, world"
