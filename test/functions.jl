include(joinpath(@__DIR__, "testcommon.jl"))
cxx_available = false

const functions_lib_path = libfunctions

# Wrap the functions defined in C++
module CppHalfFunctions Main.@wrapmodule(Main.functions_lib_path, :init_half_module) end
module CppTestFunctions Main.@wrapmodule(Main.functions_lib_path, :init_test_module) end

# Test functions from the CppHalfFunctions module
@test CppHalfFunctions.half_d(3) == 1.5
@show methods(CppHalfFunctions.half_d)
@test CppHalfFunctions.half_i(-2) == -1
@test CppHalfFunctions.half_u(3) == 1
@test CppHalfFunctions.half_lambda(2.) == 1.
if get(ENV, "APPVEYOR", "") == "" # Disabled on Windows CI due to https://github.com/JuliaLang/julia/issues/28325
  @test CppHalfFunctions.strict_half(3.) == 1.5
end
@test_throws MethodError CppHalfFunctions.strict_half(3)

# Test functions from the CppTestFunctions module
@test CppTestFunctions.concatenate_numbers(4, 2.) == "42"
@test hasmethod(CppTestFunctions.concatenate_numbers, (Union{Cint,CxxWrap.argument_overloads(Cint)...},Union{Cdouble,CxxWrap.argument_overloads(Cdouble)...}))
@test CppTestFunctions.concatenate_strings(2, "ho", "la") == "holahola"
@test CppTestFunctions.test_int32_array(Int32[1,2])
@test CppTestFunctions.test_int64_array(Int64[1,2])
@test CppTestFunctions.test_float_array(Float32[1.,2.])
@test CppTestFunctions.test_double_array([1.,2.])
if !(Sys.iswindows() && Sys.WORD_SIZE == 32)
  @test_throws ErrorException CppTestFunctions.test_exception()
end
ta = [1.,2.]
@test CppTestFunctions.test_array_len(ta) == 2
@test CppTestFunctions.test_array_get(ta, Int64(0)) == 1.
@test CppTestFunctions.test_array_get(ta, Int64(1)) == 2.
CppTestFunctions.test_array_set(ta, Int64(0), 3.)
CppTestFunctions.test_array_set(ta, Int64(1), 4.)
@test ta[1] == 3.
@test ta[2] == 4.
@test CppTestFunctions.test_type_name("IO") == "IO"

@test CppTestFunctions.test_long_long() == 42
@test CppTestFunctions.test_short() == 43

# Test GC protection array
a = "str1"
b = "str2"
c = "str3"
protect_container = CxxWrap._gc_protected
start_len = length(protect_container)
gcprotect(a)
gcprotect(b)
@test length(protect_container) == start_len + 2
@test protect_container[objectid(a)] == (a,1)
gcunprotect(a)
@test length(protect_container) == start_len + 1

@test CppTestFunctions.test_julia_call(1.,2.) == 2
@test CppTestFunctions.test_string_array(["first", "second"])
darr = [1.,2.]
CppTestFunctions.test_append_array!(darr)
@test darr == [1.,2.,3.]

testf(x,y) = x+y
@show c_func = @safe_cfunction(testf, Float64, (Float64,Float64))
CppTestFunctions.test_safe_cfunction(c_func)
CppTestFunctions.test_safe_cfunction2(c_func)

function testf_arf(v::Vector{Float64}, s::String)
  r = sum(v)
  printstyled("callback in Julia: $(s) = $(r)\n", color=:green)
  return r
end

c_func_arf = @safe_cfunction(testf_arf, Float64, (Any,Any))

CppTestFunctions.fn_clb(c_func_arf)
CppTestFunctions.fn_clb2(testf_arf)

function testf2(p::ConstPtr{Float64}, n_elems::Int)
  arr = ConstArray(p, n_elems)
  @test arr[1] == 1.0
  @test arr[2] == 2.0
  return
end
c_func2 = @safe_cfunction(testf2, Nothing, (ConstPtr{Float64},Int))
CppTestFunctions.test_safe_cfunction3(c_func2)

dref = Ref(0.0)
CppTestFunctions.test_double_ref(dref)
@test dref[] == 1.0

@test CppTestFunctions.get_test_double() == 0.0
cppdref = CppTestFunctions.get_test_double_ref()
@test unsafe_load(cppdref) == 0.0
unsafe_store!(cppdref, 1.0)
@test CppTestFunctions.get_test_double() == 1.0

@test CppTestFunctions.test_const_string_return() == "test"
@test CppTestFunctions.test_datatype_conversion(Float64) == Float64

@test typeof(CppTestFunctions.test_double_pointer()) == Ptr{Float64}
@test CppTestFunctions.test_double_pointer() == C_NULL
@test typeof(CppTestFunctions.test_double2_pointer()) == Ptr{Ptr{Float64}}
@test CppTestFunctions.test_double2_pointer() == C_NULL
@test typeof(CppTestFunctions.test_double3_pointer()) == Ptr{Ptr{Ptr{Float64}}}
@test CppTestFunctions.test_double3_pointer() == C_NULL

@test CppTestFunctions.test_wstring_to_julia() == "šČô_φ_привет_일보"
@test CppTestFunctions.test_wstring_to_cpp("šČô_φ_привет_일보")

@test CppTestFunctions.real_part(2.0 + 1.0*im) == 2.0
@test CppTestFunctions.imag_part(2.0 + 1.0*im) == 1.0
@test CppTestFunctions.make_complex(Float32(3.0), Float32(4.0)) == 3.0 + 4.0*im
@test typeof(CppTestFunctions.make_complex(Float32(3.0), Float32(4.0))) == Complex{Float32}

@test CppTestFunctions.process_irrational(π, 2) == 2*π

# Performance tests
const test_size = Sys.ARCH == :armv7l ? 1000000 : 50000000
const numbers = rand(test_size)
output = zeros(test_size)

# Build a function to loop over the test array
function make_loop_function(name)
    fname = Symbol(:half_loop_,name,:!)
    inner_name = Symbol(:half_,name)
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
using .CppHalfFunctions: half_d, half_lambda, half_loop_cpp!, half_loop_jlcall!, half_loop_cfunc!

@static if cxx_available
  # Cxx.jl version
  cxx"""
  double half_cxx(const double d)
  {
    return 0.5*d;
  }
  """
  half_cxxjl(d::Float64) = @cxx half_cxx(d)
end

# Make the looping functions
make_loop_function(:julia)
make_loop_function(:c)
make_loop_function(:d) # C++ with regular C++ function pointer
make_loop_function(:lambda) # C++ lambda, so using std::function
if cxx_available
  make_loop_function(:cxxjl) # Cxx.jl version
end

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
test_half_function(half_loop_cpp!)
if cxx_available
  test_half_function(half_loop_cxxjl!)
end

# Run timing tests
println("---- Half test timings ----")
println("Julia test:")
@time half_loop_julia!(numbers, output)
@time half_loop_julia!(numbers, output)
@time half_loop_julia!(numbers, output)

println("C test:")
@time half_loop_c!(numbers, output)
@time half_loop_c!(numbers, output)
@time half_loop_c!(numbers, output)

println("C++ test:")
@time half_loop_d!(numbers, output)
@time half_loop_d!(numbers, output)
@time half_loop_d!(numbers, output)

if cxx_available
  println("Cxx.jl test:")
  @time half_loop_cxxjl!(numbers, output)
  @time half_loop_cxxjl!(numbers, output)
  @time half_loop_cxxjl!(numbers, output)
end

println("C++ lambda test:")
@time half_loop_lambda!(numbers, output)
@time half_loop_lambda!(numbers, output)
@time half_loop_lambda!(numbers, output)

println("C++ test, loop in the C++ code:")
@time half_loop_cpp!(numbers, output)
@time half_loop_cpp!(numbers, output)
@time half_loop_cpp!(numbers, output)

println("cfunction in C++ loop")
half_cfunc = @safe_cfunction(half_julia, Float64, (Float64,))
@time half_loop_cfunc!(numbers, output, half_cfunc)
@time half_loop_cfunc!(numbers, output, half_cfunc)
@time half_loop_cfunc!(numbers, output, half_cfunc)

const small_in = rand(test_size÷100)
small_out = zeros(test_size÷100)

println("jl_call inside C++ loop (array is 100 times smaller than other tests):")
@time half_loop_jlcall!(small_in, small_out)
@time half_loop_jlcall!(small_in, small_out)
@time half_loop_jlcall!(small_in, small_out)
