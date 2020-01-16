using Test

excluded = ["build.jl", "deps.jl", "runtests.jl", "testcommon.jl"]

if Sys.iswindows() && Sys.WORD_SIZE == 32
  push!(excluded, "except.jl")
end

include(joinpath(@__DIR__, "build.jl"))

exename = joinpath(Sys.BINDIR, Base.julia_exename())

for f in filter(fname -> fname ∉ excluded, readdir())
  println("Running tests from $f...")
  run(`$exename --check-bounds=yes --color=yes $f`)
end
