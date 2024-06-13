using CxxWrap
using Test

# Can use invalid character literals (e.g. '\xa8') as of Julia 1.9:
# https://github.com/JuliaLang/julia/pull/44989
malformed_char(x) = reinterpret(Char, UInt32(x) << 24)

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

let str = "\x01\x00\x02"
  std_str = StdString(codeunits(str))
  @test length(std_str) == 1
  @test collect(std_str) == ['\x01']
  @test ncodeunits(std_str) == 1
  @test codeunits(std_str) == b"\x01"

  std_str = StdString(str)
  @test length(std_str) == 3
  @test collect(std_str) == ['\x01', '\x00', '\x02']
  @test ncodeunits(std_str) == 3
  @test codeunits(std_str) == b"\x01\x00\x02"

  std_str = StdString(str, 2)
  @test length(std_str) == 2
  @test collect(std_str) == ['\x01', '\x00']
  @test ncodeunits(std_str) == 2
  @test codeunits(std_str) == b"\x01\x00"

  std_str = convert(StdString, str)
  @test length(std_str) == 3
  @test collect(std_str) == ['\x01', '\x00', '\x02']
  @test ncodeunits(std_str) == 3
  @test codeunits(std_str) == b"\x01\x00\x02"
  @test convert(String, std_str) == str
end

let str = "α\0β"
  std_str = StdString(codeunits(str))
  @test length(std_str) == 1
  @test collect(std_str) == ['α']
  @test ncodeunits(std_str) == 2
  @test codeunits(std_str) == b"α"

  std_str = StdString(str)
  @test length(std_str) == 3
  @test collect(std_str) == ['α', '\0', 'β']
  @test ncodeunits(std_str) == 5
  @test codeunits(std_str) == b"α\0β"

  std_str = StdString(str, 4)
  @test length(std_str) == 3
  @test collect(std_str) == ['α', '\0', malformed_char(0xce)]
  @test ncodeunits(std_str) == 4
  @test codeunits(std_str) == b"α\0\xce"

  std_str = convert(StdString, str)
  @test length(std_str) == 3
  @test collect(std_str) == ['α', '\0', 'β']
  @test ncodeunits(std_str) == 5
  @test codeunits(std_str) == b"α\0β"
  @test convert(String, std_str) == str
end

@testset "StdString" begin
  @testset "null-terminated constructors" begin
    c_str = Cstring(Base.unsafe_convert(Ptr{Cchar}, "visible\0hidden"))
    @test StdString(c_str) == "visible"
    @test StdString(b"visible\0hidden") == "visible"
    @test StdString(UInt8[0xff, 0x00, 0xff]) == "\xff"
  end

  @testset "iterate" begin
    s = StdString("𨉟")
    @test iterate(s) == ('𨉟', 5)
    @test iterate(s, firstindex(s)) == ('𨉟', 5)
    @test iterate(s, 2) == (malformed_char(0xa8), 3)
    @test iterate(s, 3) == (malformed_char(0x89), 4)
    @test iterate(s, 4) == (malformed_char(0x9f), 5)
    @test iterate(s, 5) === nothing
    @test iterate(s, typemax(Int)) === nothing
  end

  @testset "getindex" begin
    s = StdString("α")
    @test getindex(s, firstindex(s)) == 'α'
    @test_throws StringIndexError getindex(s, 2)
    @test_throws BoundsError getindex(s, 3)
  end
end

@testset "StdWString" begin
  @testset "iterate" begin
    char = codeunit(StdWString()) == UInt32 ? '😄' : 'α'
    s = StdWString(string(char))
    @test iterate(s) == (char, 2)
    @test iterate(s, firstindex(s)) == (char, 2)
    @test iterate(s, 2) === nothing
    @test iterate(s, typemax(Int)) === nothing
  end

  @testset "getindex" begin
    char = codeunit(StdWString()) == UInt32 ? '😄' : 'α'
    s = StdWString(string(char))
    @test getindex(s, firstindex(s)) == char
    @test_throws BoundsError getindex(s, 2)
  end
end

@testset "StdVector" begin
  @testset "parameterized constructors" begin
    vec = StdVector{Int}()
    @test vec isa StdVector{Int}
    @test isempty(vec)

    vec = StdVector{Int}([])
    @test vec isa StdVector{Int}
    @test isempty(vec)

    vec = StdVector{Any}([])
    @test vec isa StdVector{Any}
    @test isempty(vec)

    vec = StdVector{Int}([1,2,3])
    @test vec isa StdVector{Int}
    @test vec == [1,2,3]

    vec = StdVector{Any}([1,2,3])
    @test vec isa StdVector{Any}
    @test vec == [1,2,3]

    vec = StdVector{Float64}([1,2,3])
    @test vec isa StdVector{Float64}
    @test vec == [1.0,2.0,3.0]

    vec = StdVector{CxxBool}([true, false, true])
    @test vec isa StdVector{CxxBool}
    @test vec == [true, false, true]

    vec = StdVector{StdString}(["a", "b", "c"])
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    svec_alloc = StdString.(["a", "b", "c"])::Vector{CxxWrap.StdLib.StdStringAllocated}
    vec = StdVector{StdString}(svec_alloc)
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    svec_ref = CxxRef.(StdString["a", "b", "c"])
    vec = StdVector{StdString}(svec_ref)
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    svec_deref = getindex.(svec_ref)::Vector{CxxWrap.StdLib.StdStringDereferenced}
    vec = StdVector{StdString}(svec_deref)
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    @test_throws MethodError StdVector{Bool}([true])
    @test_throws MethodError StdVector{eltype(svec_alloc)}(svec_alloc)
    @test_throws MethodError StdVector{eltype(svec_deref)}(svec_deref)
  end

  @testset "constructors" begin
    @test_throws MethodError StdVector()

    vec = StdVector(Int[])
    @test vec isa StdVector{Int}
    @test isempty(vec)

    vec = StdVector(Any[])
    @test vec isa StdVector{Any}
    @test isempty(vec)

    vec = StdVector([1,2,3])
    @test vec isa StdVector{Int}
    @test vec == [1,2,3]

    vec = StdVector(Any[1,2,3])
    @test vec isa StdVector{Any}
    @test vec == [1,2,3]

    vec = StdVector([1.0, 2.0, 3.0])
    @test vec isa StdVector{Float64}
    @test vec == [1,2,3]

    vec = StdVector([true, false, true])
    @test vec isa StdVector{CxxBool}
    @test vec == [true, false, true]

    vec = StdVector(StdString["a", "b", "c"])
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    svec_alloc = StdString.(["a", "b", "c"])::Vector{CxxWrap.StdLib.StdStringAllocated}
    vec = StdVector(svec_alloc)
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    svec_ref = CxxRef.(StdString["a", "b", "c"])
    vec = StdVector(svec_ref)
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    svec_deref = getindex.(svec_ref)::Vector{CxxWrap.StdLib.StdStringDereferenced}
    vec = StdVector(svec_deref)
    @test vec isa StdVector{StdString}
    @test vec == ["a", "b", "c"]

    @test_throws MethodError StdVector(["a", "b", "c"])
  end

  @testset "mutating with integer" begin
    stvec = StdVector(Int32[1,2,3])
    @test stvec == [1,2,3]
    push!(stvec,1)
    @test stvec == [1,2,3,1]
    resize!(stvec, 2)
    @test stvec == [1,2]
    append!(stvec, Int32[2,1])
    @test stvec == [1,2,2,1]
    empty!(stvec)
    @test isempty(stvec)
  end

  @testset "mutating with bool" begin
    bvec = StdVector([true, false, true])
    append!(bvec, [true])
    @test bvec == [true, false, true, true]
  end

  @testset "mutating with StdString" begin
    cxxstrings = StdString["one", "two", "three"]
    svec = StdVector(CxxRef.(cxxstrings))
    @test svec == ["one", "two", "three"]
    push!(svec, StdString("four"))
    @test svec == ["one", "two", "three", "four"]
    cxxappstrings = StdString["five", "six"]
    append!(svec, CxxRef.(cxxappstrings))
    @test svec == ["one", "two", "three", "four", "five", "six"]
    empty!(svec)
    @test isempty(svec)
  end
end

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
  @test length(deque1) == 0
  push!(deque1, 7)
  push!(deque1, 9)
  @test length(deque1) == 2
  deque2 = deque1
  popfirst!(deque2)
  @test length(deque2) == 1
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

@testset "StdPriorityQueue" begin
  pq = StdPriorityQueue{Int64}()
  @test length(pq) == 0
  push!(pq, 5)
  push!(pq, 1)
  @test isempty(pq) == false
  pq = push!(pq, 4)
  pq = push!(pq, 10)
  @test length(pq) == 4
  @test first(pq) == 10
  @test pop!(pq) == 10
  @test length(pq) == 3
  @test pop!(pq) == 5
  @test pop!(pq) == 4
  @test pop!(pq) == 1
  @test isempty(pq) == true
  @test isnothing(first(pq))
  @test_throws ArgumentError pop!(pq)
end

@testset "StdSet and StdUnorderedSet" begin
  for StdSetType in (StdSet, StdUnorderedSet)
    @testset "Set with integers" begin
      set = StdSetType{Int64}()
      @test isempty(set) == true
      @test length(set) == 0
      set = push!(set, 10)
      push!(set, 20)
      @test isempty(set) == false
      @test length(set) == 2
      @test (10 ∈ set) == true
      @test (20 ∈ set) == true
      set = delete!(set, 20)
      @test length(set) == 1
      @test (20 ∈ set) == false
      @test (30 ∈ set) == false
      empty!(set)
      @test isempty(set) == true
    end

    @testset "Set with bools" begin
      set = StdSetType{CxxBool}()
      @test isempty(set) == true
      @test length(set) == 0
      push!(set, true)
      push!(set, false)
      @test isempty(set) == false
      @test length(set) == 2
      @test (true ∈ set) == true
      @test (false ∈ set) == true
      set = empty!(set)
      @test isempty(set) == true
    end

    @testset "Set with floats" begin
      set = StdSetType{Float64}()
      @test isempty(set) == true
      @test length(set) == 0
      push!(set, 1.4)
      push!(set, 2.2)
      @test isempty(set) == false
      @test length(set) == 2
      @test (1.4 ∈ set) == true
      @test (10.0 ∈ set) == false
      @test (2.2 ∈ set) == true
      empty!(set)
      @test isempty(set) == true
    end
  end
end

@testset "StdMultiset and StdUnorderedMultiset" begin
  for StdMultisetType in (StdMultiset, StdUnorderedMultiset)
    @testset "Multiset with integers" begin
      multiset = StdMultisetType{Int64}()
      @test isempty(multiset) == true
      @test length(multiset) == 0
      multiset = push!(multiset, 10)
      push!(multiset, 20)
      push!(multiset, 20)
      count(20, multiset) == 2
      @test isempty(multiset) == false
      @test length(multiset) == 3
      @test (10 ∈ multiset) == true
      @test (20 ∈ multiset) == true
      multiset = delete!(multiset, 20)
      @test length(multiset) == 1
      @test (20 ∈ multiset) == false
      @test (30 ∈ multiset) == false
      empty!(multiset)
      @test isempty(multiset) == true
    end
  
    @testset "Multiset with bools" begin
      multiset = StdMultisetType{CxxBool}()
      push!(multiset, true)
      push!(multiset, true)
      push!(multiset, true)
      push!(multiset, false)
      @test isempty(multiset) == false
      @test count(true, multiset) == 3
      @test count(false, multiset) == 1
      @test length(multiset) == 4
      multiset = delete!(multiset, true)
      @test length(multiset) == 1
      multiset = empty!(multiset)
      @test length(multiset) == 0
      @test isempty(multiset) == true
    end
  
    @testset "Multiset with floats" begin
      multiset = StdMultisetType{Float64}()
      @test isempty(multiset) == true
      @test length(multiset) == 0
      push!(multiset, 1.4)
      push!(multiset, 2.2)
      push!(multiset, 2.2)
      @test isempty(multiset) == false
      @test length(multiset) == 3
      @test (1.4 ∈ multiset) == true
      @test count(1.4, multiset) == 1
      @test (10.0 ∈ multiset) == false
      @test count(10.0, multiset) == 0
      @test (2.2 ∈ multiset) == true
      @test count(2.2, multiset) == 2
      empty!(multiset)
      @test isempty(multiset) == true
    end
  end
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

end

end
