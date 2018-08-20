include(joinpath(@__DIR__, "testcommon.jl"))

# Wrap the functions defined in C++
module ParametricTypes

using CxxWrap
@wrapmodule(Main.libparametric)

end

import .ParametricTypes.TemplateType, .ParametricTypes.NonTypeParam

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

f3 = ParametricTypes.Foo3{Int32, Bool, Float32}()
@test length(methods(ParametricTypes.foo3_method)) == 6
f2 = ParametricTypes.Foo2{Float64}()
@test length(methods(ParametricTypes.foo2_method)) == 2

@test length(methods(ParametricTypes.foo3_free_method)) == 6
ParametricTypes.foo3_free_method(f3)

@test supertype(ParametricTypes.Foo3{Float64,ParametricTypes.P1,Float32}) == ParametricTypes.AbstractTemplate{Float64}

darr = [1.0, 2.0, 3.0]
carr = Complex{Float32}[1+2im, 3+4im]
vec1 = ParametricTypes.CppVector{Float64}(pointer(darr), 3)
vec2 = ParametricTypes.CppVector2{Float64, Float32}()
vec3 = ParametricTypes.CppVector{Complex{Float32}}(pointer(carr), 2)
@test isa(vec1, AbstractVector{Float64})
@test isa(vec2, AbstractVector{Float64})
@test isa(vec3, AbstractVector{Complex{Float32}})
@test ParametricTypes.get(vec1,0) == 1.0
@test ParametricTypes.get(vec1,1) == 2.0
@test ParametricTypes.get(vec1,2) == 3.0
@test ParametricTypes.get(vec3,0) == 1+2im
@test ParametricTypes.get(vec3,1) == 3+4im
