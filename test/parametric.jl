# Hello world example, similar to the Boost.Python hello world

using CxxWrap
using Base.Test
using Compat

# Wrap the functions defined in C++
wrap_modules(CxxWrap._l_parametric)

import ParametricTypes.TemplateType, ParametricTypes.NonTypeParam

p1 = TemplateType{ParametricTypes.P1, ParametricTypes.P2}()
p2 = TemplateType{ParametricTypes.P2, ParametricTypes.P1}()

println("Dumping object p1:")
dump(p1)

@test ParametricTypes.get_first(p1) == 1
@test ParametricTypes.get_second(p2) == 1
@test typeof(ParametricTypes.get_first(p1)) == Int32
@test typeof(ParametricTypes.get_second(p2)) == Int32

@test ParametricTypes.get_first(p2) == 10.
@test ParametricTypes.get_second(p1) == 10.
@test typeof(ParametricTypes.get_first(p2)) == Float64
@test typeof(ParametricTypes.get_second(p1)) == Float64

@test ParametricTypes.TemplateDefaultType{ParametricTypes.P1}() != nothing

nontype1 = ParametricTypes.NonTypeParam{Int32, Int32(1)}()
@test ParametricTypes.get_nontype(nontype1) == 1

nontype2 = ParametricTypes.NonTypeParam{UInt32, UInt32(2)}()
@test ParametricTypes.get_nontype(nontype2) == UInt32(2)

nontype3 = ParametricTypes.NonTypeParam{Int32, Int32(1)}(3)
@test ParametricTypes.get_nontype(nontype3) == 3

nontype4 = ParametricTypes.NonTypeParam{Int64, Int64(64)}()
@test ParametricTypes.get_nontype(nontype4) == Int64(64)

concr = ParametricTypes.ConcreteTemplate{Float64}()
@test isa(concr, ParametricTypes.AbstractTemplate{Float64})
@test isa(concr, ParametricTypes.AbstractTemplate)
@test isa(concr, ParametricTypes.ConcreteTemplate)
abst = ParametricTypes.to_base(concr)
@test isa(abst, ParametricTypes.AbstractTemplate{Float64})
@test isa(abst, ParametricTypes.AbstractTemplate)
