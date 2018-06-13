include(joinpath(@__DIR__, "testcommon.jl"))

@test ccall((:internalthrow, libexcept), Cint, (Cint,), -1) == 1
@test ccall((:internalthrow, libexcept), Cint, (Cint,), -2) == 2
@test ccall((:internalthrow, libexcept), Cint, (Cint,), -1) == 1

# This crashes when linking CxxWrap compiled with VS for 32-bit targets due to a mingw32 bug, see:
# https://ghc.haskell.org/trac/ghc/ticket/10435
# Only happens with SEHOP enabled, as is the case on appveyor
try
  ccall((:internalthrow, libexcept), Cint, (Cint,), 1) == 0
  @test false
catch
  println("exception 1")
  @test true
end

try
  ccall((:internalthrow, libexcept), Cint, (Cint,), 2) == 0
  @test false
catch
  println("exception 2")
  @test true
end

try
  ccall((:internalthrow, libexcept), Cint, (Cint,), 3) == 0
  @test false
catch
  println("exception 3")
  @test true
end
