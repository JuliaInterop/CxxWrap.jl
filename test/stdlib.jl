using CxxWrap
using Test

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

svec = StdVector(["one", "two", "three"])
@test all(svec .== ["one", "two", "three"])
push!(svec, "four")
@test all(svec .== ["one", "two", "three", "four"])
append!(svec, ["five", "six"])
@test all(svec .== ["one", "two", "three", "four", "five", "six"])
empty!(svec)
@test isempty(svec)