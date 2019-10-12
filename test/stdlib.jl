using CxxWrap
using Test

let s = StdString("test")
  println("This prints a test string: ", s)
  @test s == "test"
end

let s = "šČô_φ_привет_일보"
  @show StdWString(s)
  @test StdWString(s) == s
  @test String(StdWString(s)) == s
end

stvec = StdVector(Int32[1,2,3])
@test all(stvec .== [1,2,3])
push!(stvec,1)
@test all(stvec .== [1,2,3,1])
resize!(stvec,2)
@test all(stvec .== [1,2])
append!(stvec,Int32[2,1])
@test all(stvec .== [1,2,2,1])
empty!(stvec)
@test isempty(stvec)

@test all(StdVector([1,2,3]) .== [1,2,3])
@test all(StdVector([1.0,2.0,3.0]) .== [1,2,3])
@test all(StdVector([true, false, true]) .== [true, false, true])
bvec = StdVector([true, false, true])
append!(bvec, [true])
@test all(bvec .== [true, false, true, true])

cxxstrings = StdString["one", "two", "three"]
svec = StdVector(CxxRef.(cxxstrings))
@test all(svec .== ["one", "two", "three"])
push!(svec, StdString("four"))
@test all(svec .== ["one", "two", "three", "four"])
cxxappstrings = StdString["five", "six"]
append!(svec, CxxRef.(cxxappstrings))
@test all(svec .== ["one", "two", "three", "four", "five", "six"])
empty!(svec)
@test isempty(svec)

stvec = StdVector(Int32[1,2,3])
for vref in (CxxRef(stvec), CxxPtr(stvec))
  s = 0
  for x in vref
    s += x
  end
  @test s == sum(stvec)
  @test all(vref .== [1,2,3])
end