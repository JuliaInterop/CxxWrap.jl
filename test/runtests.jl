using Base.Test

excluded = ["runtests.jl"]

if is_windows() && Sys.WORD_SIZE == 32
  push!(excluded, "except.jl")
end

@testset "CxxWrap tests" begin
  @testset "$f" for f in filter(fname -> fname ∉ excluded, readdir())
    include(f)
  end
end
