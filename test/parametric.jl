# Hello world example, similar to the Boost.Python hello world

println("Running parametric.jl...")

using CxxWrap
using Base.Test

# Wrap the functions defined in C++
wrap_modules(Pkg.dir("CxxWrap","deps","usr","lib","libparametric"))

import ParametricTypes.TemplateType, ParametricTypes.NonTypeParam

p1 = TemplateType{ParametricTypes.P1, ParametricTypes.P2}()
p2 = TemplateType{ParametricTypes.P2, ParametricTypes.P1}()

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

nontype1 = ParametricTypes.NonTypeParam{Int32, Int32(1)}()
@test ParametricTypes.get_nontype(nontype1) == 1

nontype2 = ParametricTypes.NonTypeParam{UInt32, UInt32(2)}()
@test ParametricTypes.get_nontype(nontype2) == UInt32(2)

nontype3 = ParametricTypes.NonTypeParam{Int32, Int32(1)}(3)
@test ParametricTypes.get_nontype(nontype3) == 3

nontype4 = ParametricTypes.NonTypeParam{Int64, Int64(64)}()
@test ParametricTypes.get_nontype(nontype4) == Int64(64)
