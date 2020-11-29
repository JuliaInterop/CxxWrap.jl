using Test
using libcxxwrap_julia_jll

excluded = ["runtests.jl", "testcommon.jl"]

if Sys.iswindows() && Sys.WORD_SIZE == 32
  push!(excluded, "except.jl")
end

if get(ENV, "CXXWRAP_DISABLE_GC", "0") == "1"
  println("disabling GC for tests")
  GC.enable(false)
end

@testset "CxxWrap tests" begin
  for f in filter(fname -> fname ∉ excluded, readdir(@__DIR__))
    println("Running tests from $f...")
    include(f)
  end
end