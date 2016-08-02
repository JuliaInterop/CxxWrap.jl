println("Running containers.jl...")

using CxxWrap
using Base.Test

wrap_modules(CxxWrap._l_containers)
using Containers

@test test_tuple() == (1,2.0,3.0f0)
