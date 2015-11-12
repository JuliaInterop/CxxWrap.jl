# Tests for the functions library in deps/examples

using CppWrapper
using Base.Test

const functions_lib_path = joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libfunctions")

# Wrap the functions defined in C++
CppWrapper.wrap_modules(functions_lib_path)

# Test functions from the CppHalfFunctions module
@test CppHalfFunctions.half_d(3) == 1.5
@test CppHalfFunctions.half_i(-2) == -1
@test CppHalfFunctions.half_u(3) == 1
@test CppHalfFunctions.half_lambda(2.) == 1.

# Test functions from the CppTestFunctions module
@test CppTestFunctions.concatenate_numbers(4, 2.) == "42"
@test length(methods(CppTestFunctions.concatenate_numbers)) == 4 # due to overloads
@test CppTestFunctions.concatenate_strings(2, "ho", "la") == "holahola"

# Performance tests
const test_size = 50000000
const numbers = rand(test_size)
output = zeros(test_size)

# Build a function to loop over the test array
function make_loop_function(name)
    fname = symbol(:half_loop_,name,:!)
    inner_name = symbol(:half_,name)
    @eval begin
        function $(fname)(n::Array{Float64,1}, out_arr::Array{Float64,1})
            test_length = length(n)
          for i in 1:test_length
                out_arr[i] = $(inner_name)(n[i])
          end
        end
    end
end

# Julia version
half_julia(d::Float64) = d*0.5

# C version
half_c(d::Float64) = ccall((:half_c, functions_lib_path), Cdouble, (Cdouble,), d)

# Bring C++ versions into scope
using CppHalfFunctions.half_d, CppHalfFunctions.half_lambda, CppHalfFunctions.half_loop_cpp!

# Make the looping functions
make_loop_function(:julia)
make_loop_function(:c)
make_loop_function(:d) # C++ with regular C++ function pointer
make_loop_function(:lambda) # C++ lambda, so using std::function

# test that a "half" function does what it should
function test_half_function(f)
  input = [2.]
  output = [0.]
  f(input, output)
  @test output[1] == 1.
end
test_half_function(half_loop_julia!)
test_half_function(half_loop_c!)
test_half_function(half_loop_d!)
test_half_function(half_loop_lambda!)
@show methods(half_loop_cpp!)
test_half_function(half_loop_cpp!)

# Run timing tests
println("---- Half test timings ----")
println("Julia test:")
@time half_loop_julia!(numbers, output)
@time half_loop_julia!(numbers, output)

println("C test:")
@time half_loop_c!(numbers, output)
@time half_loop_c!(numbers, output)

println("C++ test:")
@time half_loop_d!(numbers, output)
@time half_loop_d!(numbers, output)

println("C++ lambda test:")
@time half_loop_lambda!(numbers, output)
@time half_loop_lambda!(numbers, output)
