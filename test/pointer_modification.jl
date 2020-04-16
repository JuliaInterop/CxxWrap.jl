module PtrModif
  function divrem(a,b)
    r = Ref(CxxPtr{MyData}(C_NULL))
    q = PtrModif.divrem(CxxPtr(a),CxxPtr(b),r)
    return (q,r[])
  end

  include(joinpath(@__DIR__, "testcommon.jl"))
  @wrapmodule CxxWrap.CxxWrapCore.libpointer_modification()

  function __init__()
    @initcxx
  end

end

using BenchmarkTools
using CxxWrap
using Test

@testset "$(basename(@__FILE__)[1:end-3])" begin

let d = PtrModif.MyData()
  PtrModif.setvalue!(d, 10)
  @test PtrModif.readpointerptr(Ref(CxxPtr(d))) == 10
  PtrModif.setvalue!(d, 20)
  @test PtrModif.readpointerref(Ref(CxxPtr(d))) == 20
end

let nd = Ref(CxxPtr{PtrModif.MyData}(C_NULL))
  @test isnull(nd[])
  PtrModif.writepointerref!(nd)
  @test !isnull(nd[])
  @test PtrModif.value(nd[][]) == 30
  PtrModif.setvalue!(nd[][], 40)
  @test PtrModif.value(nd[][]) == 40
  PtrModif.delete(nd[]) # Some manual management needed here
end

# Simulation of the Issue #133 use case
let a = PtrModif.MyData(9), b = PtrModif.MyData(2)
  (q,r) = PtrModif.divrem(a,b)
  @test PtrModif.value.((q,r[])) == (4,1)
  PtrModif.delete(r)
  (q,r) = PtrModif.divrem(q[],b)
  @test PtrModif.value(q) == 2
  @test isnull(r)
end

let a = PtrModif.MyData(9), b = PtrModif.MyData(2)
  (q,r) = PtrModif.prettydivrem(CxxPtr(a), CxxPtr(b))
  @test PtrModif.value.((q,r)) == (4,1)
end

end

GC.gc()
@test PtrModif.alive_count() == 0

# Must be after the GC test, because BenchmarkTools keeps a reference to the value

let a = PtrModif.MyData(11)
  println("value timing:")
  @btime PtrModif.value($a)
end
