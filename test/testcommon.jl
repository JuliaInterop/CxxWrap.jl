
using CxxWrap
using Test

if !@isdefined libjlcxx_containers

  depfile = joinpath(@__DIR__, "deps.jl")
  if !isfile(depfile)
    include(joinpath(@__DIR__, "build.jl"))
  end
  
  include(depfile)
end