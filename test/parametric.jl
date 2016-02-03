# Hello world example, similar to the Boost.Python hello world

println("Running parametric.jl...")

using CppWrapper
using Base.Test

# Wrap the functions defined in C++
wrap_modules(joinpath(Pkg.dir("CppWrapper"),"deps","usr","lib","libparametric"))

p1 = ParametricTypes.Parametric{ParametricTypes.P1, ParametricTypes.P2}()
p2 = ParametricTypes.Parametric{ParametricTypes.P2, ParametricTypes.P1}()

println("Dumping object p1:")
xdump(p1)

@test ParametricTypes.get_first(p1) == 1
@test ParametricTypes.get_second(p2) == 1
@test typeof(ParametricTypes.get_first(p1)) == Int32
@test typeof(ParametricTypes.get_second(p2)) == Int32

@test ParametricTypes.get_first(p2) == 10.
@test ParametricTypes.get_second(p1) == 10.
@test typeof(ParametricTypes.get_first(p2)) == Float64
@test typeof(ParametricTypes.get_second(p1)) == Float64
