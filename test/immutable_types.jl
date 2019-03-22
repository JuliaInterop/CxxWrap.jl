module ImmutableTypes
  include(joinpath(@__DIR__, "testcommon.jl"))

  struct ImmutableBits
    a::Float64
    b::Float64
  end

  struct A
    x :: Float32
    y :: Float32
  end

  @wrapmodule libimmutable_types

  function __init__()
    @initcxx
  end

  mutable struct MutableBits
    a::Float64
    b::Float64
  end

  function make_immutable()
    result = ccall((:make_immutable,libimmutable_types), MutableBits, ())
    finalizer(result) do x
      ccall((:print_final,libimmutable_types), Cvoid, (MutableBits,), x)
    end
  end
end

using CxxWrap
using Test

# let imm = ImmutableTypes.ImmutableBits(1.0, 2.0)
#   @test ImmutableTypes.increment_immutable(imm) == ImmutableTypes.ImmutableBits(2.0, 3.0)
# end

let a = ImmutableTypes.A(2,3)
  @test ImmutableTypes.f(a) == 5.0
  @test ImmutableTypes.g(a) == 5.0
  @test ImmutableTypes.h(a) == 5.0
  @test ImmutableTypes.h(C_NULL) == 0.0
end

let f = Float32(5.0), a = [f]
  @test ImmutableTypes.twice_val(f) == 10.0
  @test ImmutableTypes.twice_cref(f) == 10.0
  @test ImmutableTypes.twice_ref(Ref(f)) == 10.0
  @test ImmutableTypes.twice_cptr(f) == 10.0
  @test ImmutableTypes.twice_ptr(Ref(f)) == 10.0
  @test ImmutableTypes.twice_ptr(pointer(a)) == 10.0
  @test ImmutableTypes.twice_ptr(a) == 10.0
  ImmutableTypes.twice_ptr_mut(a)
  @test a[1] == 10.0
end

let f = Ref(Float32(2.0))
  ImmutableTypes.twice_ref_mut(f)
  @test f[] == 4.0
end

# println("start test")
# a = Vector{Int}()
# b = Vector{Int}()
# println("end test")

# @show ImmutableTypes.arrtest()
# @show typeof(ImmutableTypes.arrtest())

# @show ImmutableTypes.make_immutable()
