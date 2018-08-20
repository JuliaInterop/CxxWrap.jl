using Test

excluded = ["build.jl", "runtests.jl", "testcommon.jl"]

if Sys.iswindows() && Sys.WORD_SIZE == 32
  push!(excluded, "except.jl")
end

include(joinpath(@__DIR__, "build.jl"))

@testset "CxxWrap tests" begin
  @testset "$f" for f in filter(fname -> fname ∉ excluded, readdir())
    println("Running tests from $f...")
    include(f)
  end
  # second include for types.jl, to test reloading
  include("types.jl")
end
