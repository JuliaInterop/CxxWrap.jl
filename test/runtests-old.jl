using CppWrapper
using Base.Test

const lib = Libdl.dlopen(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libfunctions"), Libdl.RTLD_GLOBAL)
const get_f_ptr = Libdl.dlsym(lib,"get_function")
const get_d_ptr = Libdl.dlsym(lib,"get_data")

function basic_test()
  ccall(Libdl.dlsym(lib,"init"), Void, ())
  get_f_ptr = Libdl.dlsym(lib,"get_function")
  get_d_ptr = Libdl.dlsym(lib,"get_data")

  half_d_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_d")
  half_i_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_i")
  half_u_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_u")
  thrird_lambda_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "third_lambda")
  @show half_d_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_d")
  @show half_i_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_i")
  @show half_u_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_u")
  @show thrird_lambda_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "third_lambda")

  @test ccall(half_d_fptr, Cdouble, (Cdouble,), -3) == -1.5
  @test ccall(half_i_fptr, Cint, (Cint,), -3) == -1
  @test ccall(half_u_fptr, Cuint, (Cuint,), 3) == 1
  @test ccall(thrird_lambda_fptr, Cdouble, (Ptr{Void},Cdouble,), thrird_lambda_dptr, -3) == -1.
end

basic_test()

const test_size = 50000000
const numbers = rand(test_size)
output = zeros(test_size)

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

function half_julia(d::Float64)
  d*0.5;
end

const half_fptr_c = Libdl.dlsym(lib,"half_c")
function half_c(d::Float64)
  ccall(half_fptr_c, Cdouble, (Cdouble,), d)
end

const half_d_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_d")
function half_cpp(d::Float64)
  ccall(half_d_fptr, Cdouble, (Cdouble,), d)
end

const half_lambda_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_lambda")
const half_lambda_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_lambda")
function half_lambda(d::Float64)
  ccall(half_lambda_fptr, Cdouble, (Ptr{Void},Cdouble,), half_lambda_dptr, d)
end

# test that a "half" function does what it should
function test_half_function(f)
  input = [2.]
  output = [0.]
  f(input, output)
  @test output[1] == 1.
end

make_loop_function(:julia)
make_loop_function(:c)
make_loop_function(:cpp)
make_loop_function(:lambda)

test_half_function(half_loop_julia!)
test_half_function(half_loop_c!)
test_half_function(half_loop_cpp!)
test_half_function(half_loop_lambda!)

print("Julia test:\n")
@time half_loop_julia!(numbers, output)
@time half_loop_julia!(numbers, output)

print("C test:\n")
@time half_loop_c!(numbers, output)
@time half_loop_c!(numbers, output)

print("C++ test:\n")
@time half_loop_cpp!(numbers, output)
@time half_loop_cpp!(numbers, output)

print("lambda test:\n")
@time half_loop_lambda!(numbers, output)
@time half_loop_lambda!(numbers, output)
