using CxxWrap
using Test

@testset "$(basename(@__FILE__)[1:end-3])" begin

let s = StdString("test")
  println("This prints a test string: ", s)
  @test s == "test"
  stref = CxxRef(s)
  @test stref[] == s
  @test stref == stref
end

let s = "šČô_φ_привет_일보"
  @show StdWString(s)
  @test StdWString(s) == s
  @test String(StdWString(s)) == s
end

let s = "😄😈😼"
  @show StdWString(s)
  @test StdWString(s) == s
  @test String(StdWString(s)) == s
end

let s = "café"
  @show StdString(s)
  @test StdString(s) == s
  @test String(StdString(s)) == s
end

let s = StdString("foo")
  @test String(s) == "foo"
  sref = CxxRef(s)
  @test sref[] == "foo"
  @test String(sref) == "foo"
  @test unsafe_string(CxxWrap.StdLib.c_str(s)) == "foo"
  @test unsafe_string(CxxWrap.StdLib.c_str(s),2) == "fo"
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
  @test vref[1] == 1
  vref[3] = 10
  @test vref[3] == 10
  vref[3] = 3
end

let
  valarr1 = StdValArray{Float64}()
  @test length(valarr1) == 0
  valarr2 = StdValArray([1.0, 2.0, 3.0])
  @test valarr2 == [1.0, 2.0, 3.0]
  valarr2[2] = sum(valarr2)
  @show valarr2
  @test valarr2[2] == 6
end


let
  @show "test deque"
  deque1 = StdDeque{Int64}()
  deque2 = StdDeque{Int64}(5, 3)
  @test length(deque1) == 0
  @test length(deque2) == 5
  push!(deque1, 7)
  pushfirst!(deque1, 9)
  @test length(deque1) == 2
  resize!(deque2, 3)
  @test length(deque2) == 3
  resize!(deque2, 8)
  @test length(deque2) == 8
  setindex!(deque2, 0, 1)
  @test getindex(deque2, 1) == 0
  pop!(deque2)
  popfirst!(deque2)
  @test length(deque2) == 6
  @test isempty(deque2) == false
  empty!(deque2)
  @test isempty(deque2) == true
  deque3 = deque1
  @test length(deque3) == 2
  (val, state) = iterate(deque3)
  @test val == 9
  (val, state) = iterate(deque3, state)
  @test val == 7
  @test state == nothing
end

let
  @show "test queue"
  queue = StdQueue{Int64}()
  @test length(queue) == 0
  push!(queue, 10)
  push!(queue, 20)
  @test length(queue) == 2
  @test first(queue) == 10
  pop!(queue)
  @test first(queue) == 20
  @test length(queue) == 1
end

@static if isdefined(StdLib, :HAS_RANGES)

@testset "StdFill" begin
  @testset "fill StdVector" begin
    v = StdVector{Int64}([1, 2, 3, 4, 5])
    fill!(v, 1)
    for x in v
      @test x == 1
    end
  end

  @testset "fill StdValArray" begin
    v = StdValArray([1.0, 2.0, 3.0])
    fill!(v, 2)
    for x in v
      @test x == 2
    end
  end

  @testset "fill StdDeque" begin
    deq = StdDeque{Int64}()
    for i = 1:10
      push!(deq, i)
    end
    fill!(deq, 3)
    for x in deq
      @test x == 3
    end
  end
end

@testset "StdDequeIterator" begin
  d = StdDeque{Int64}()
  for i = 1:4
    push!(d, i)
  end
  iteration_tuple = iterate(d)
  for i = 1:4
    @test iteration_tuple[1] == i
    iteration_tuple = iterate(d, iteration_tuple[2])
  end
end

end

end # StdLib
