module BasicTypes
  include(joinpath(@__DIR__, "testcommon.jl"))

  struct ImmutableBits
    a::Float64
    b::Float64
  end

  struct A
    x :: Float32
    y :: Float32
  end

  @wrapmodule libbasic_types

  function __init__()
    @initcxx
  end

  mutable struct MutableBits
    a::Float64
    b::Float64
  end

  function make_immutable()
    result = ccall((:make_immutable,libbasic_types), MutableBits, ())
    finalizer(result) do x
      ccall((:print_final,libbasic_types), Cvoid, (MutableBits,), x)
    end
  end
end

using CxxWrap
using Test

let imm = BasicTypes.ImmutableBits(1.0, 2.0)
  @test BasicTypes.increment_immutable(imm) == BasicTypes.ImmutableBits(2.0, 3.0)
end

let a = BasicTypes.A(2,3)
  @test BasicTypes.f(a) == 5.0
  @test BasicTypes.g(a) == 5.0
  @test BasicTypes.h(a) == 5.0
  @test BasicTypes.h(C_NULL) == 0.0
end

let f = Float32(5.0), a = [f]
  @test BasicTypes.twice_val(f) == 10.0
  @test BasicTypes.twice_cref(f) == 10.0
  @test BasicTypes.twice_ref(Ref(f)) == 10.0
  @test BasicTypes.twice_cptr(f) == 10.0
  @test BasicTypes.twice_ptr(Ref(f)) == 10.0
  @test BasicTypes.twice_ptr(pointer(a)) == 10.0
  @test BasicTypes.twice_ptr(a) == 10.0
  BasicTypes.twice_ptr_mut(a)
  @test a[1] == 10.0
end

let f = Ref(Float32(2.0))
  BasicTypes.twice_ref_mut(f)
  @test f[] == 4.0
end

let a = Ref(BasicTypes.A(1,2))
  b = BasicTypes.return_a_ptr(a)
  @test a[].x == 2
  @test a[].y == 3
  @test unsafe_load(b) == a[]

  b = BasicTypes.return_a_cptr(a)
  @test a[].x == 3
  @test a[].y == 4
  @test unsafe_load(b) == a[]

  b = BasicTypes.return_a_ref(a)
  @test a[].x == 4
  @test a[].y == 5
  @test b[] == a[]

  b = BasicTypes.return_a_cref(a)
  @test a[].x == 5
  @test a[].y == 6
  @test b[] == a[]
end

let s = "abc"
  @test BasicTypes.strlen_cchar(s) == length(s)
  @test BasicTypes.strlen_char(s) == length(s)
end

let s = BasicTypes.CppString("hello")
  BasicTypes.print_str(s)
end

# println("start test")
# a = Vector{Int}()
# b = Vector{Int}()
# println("end test")

# @show BasicTypes.arrtest()
# @show typeof(BasicTypes.arrtest())

# @show BasicTypes.make_immutable()
