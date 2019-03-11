module PtrModif
  include(joinpath(@__DIR__, "testcommon.jl"))
  @wrapmodule libpointer_modification

  function __init__()
    @initcxx
  end

  function divrem(a,b)
    r = nullptr(MyData)
    q = divrem(a,b,Ref(r))
    return (q,r)
  end
end

using CxxWrap
using Test

let d = PtrModif.MyData()
  PtrModif.setvalue!(d, 10)
  @test PtrModif.readpointerptr(Ptr{PtrModif.MyDataAllocated}(pointer_from_objref(d))) == 10
  PtrModif.setvalue!(d, 20)
  @test PtrModif.readpointerref(Ref(d)) == 20
  PtrModif.writepointerref!(Ref(d))
  @test PtrModif.value(d) == 30
end

let nd = nullptr(PtrModif.MyData)
  @test isnull(nd)
  PtrModif.writepointerref!(Ref(nd))
  @test PtrModif.value(nd) == 30
  PtrModif.setvalue!(nd, 40)
end

# Simulation of the Issue #133 use case
let a = PtrModif.MyData(9), b = PtrModif.MyData(2)
  (q,r) = PtrModif.divrem(a,b)
  @test PtrModif.value.((q,r)) == (4,1)
  (q,r) = PtrModif.divrem(q,b)
  @test PtrModif.value(q) == 2
  @test isnull(r)
end

let a = PtrModif.MyData(9), b = PtrModif.MyData(2)
  (q,r) = PtrModif.prettydivrem(a,b)
  @test PtrModif.value.((q,r)) == (4,1)
end

GC.gc()
@test PtrModif.alive_count() == 0

# Must be after the GC test, because BenchmarkTools keeps a reference to the value

using BenchmarkTools

let a = PtrModif.MyData(11)
  println("value timing:")
  @btime PtrModif.value($a)
  println("return_arg timing:")
  @btime PtrModif.return_arg($a)
end
