using CppWrapper
using Base.Test

function basic_test()
  pdir = Pkg.dir("CppWrapper")
  const lib = Libdl.dlopen(joinpath(pdir,"deps","usr","lib","libfunctions"), Libdl.RTLD_GLOBAL)
  ccall(Libdl.dlsym(lib,"init"), Void, ())
  get_f_ptr = Libdl.dlsym(lib,"get_function")
  get_d_ptr = Libdl.dlsym(lib,"get_data")

  half_d_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_d")
  half_i_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_i")
  half_u_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_u")
  thrird_lambda_fptr = ccall(get_f_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "third_lambda")
  half_d_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_d")
  half_i_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_i")
  half_u_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "half_u")
  thrird_lambda_dptr = ccall(get_d_ptr, Ptr{Void}, (Cstring, Cstring), "functions", "third_lambda")

  @test ccall(half_d_fptr, Cdouble, (Ptr{Void},Cdouble,), half_d_dptr, -3) == -1.5
  @test ccall(half_i_fptr, Cint, (Ptr{Void},Cint,), half_i_dptr, -3) == -1
  @test ccall(half_u_fptr, Cuint, (Ptr{Void},Cuint,), half_u_dptr, 3) == 1
  @test ccall(thrird_lambda_fptr, Cdouble, (Ptr{Void},Cdouble,), thrird_lambda_dptr, -3) == -1.
end

basic_test()