module TestCxxDereference
  using CxxWrap

  struct Foo end

  CxxWrap.reference_type_union(::Type{Foo}) = Union{Foo, CxxWrap.CxxBaseRef{Foo}}
  CxxWrap.reference_type_union(::Type{Int}) = Union{Int, Ref{Int}}
  CxxWrap.dereference_argument(x::Ref{Int}) = x[]

  @cxxdereference function foo(a::Foo, b::Int, c...)
    return b + sum(c)
  end

  @cxxdereference unnamedparam(::Type{Int}, x) = Int(x)
end

using Test
using MacroTools

@testset "$(basename(@__FILE__)[1:end-3])" begin

@test TestCxxDereference.foo(TestCxxDereference.Foo(), 2, 1,2,3) == 8
@test_throws MethodError TestCxxDereference.foo(TestCxxDereference.Foo(), Ref(2), 1,2,Ref(3.0))
@test TestCxxDereference.foo(TestCxxDereference.Foo(), Ref(2), 1,2.0,Ref(3)) == 8
@test TestCxxDereference.unnamedparam(Int, 3) == 3

end