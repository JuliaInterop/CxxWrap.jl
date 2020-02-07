using Test
using libcxxwrap_julia_jll

excluded = ["runtests.jl", "testcommon.jl"]

if Sys.iswindows() && Sys.WORD_SIZE == 32
  push!(excluded, "except.jl")
end

@testset "CxxWrap tests" begin
  for f in filter(fname -> fname ∉ excluded, readdir())
    println("Running tests from $f...")
    include(f)
  end
end