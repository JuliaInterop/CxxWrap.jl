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

    vec = StdVector{StdString}(["p", "q", "r"])
    @test vec isa StdVector{StdString}
    @test vec == ["p", "q", "r"]

    svec_alloc = StdString.(["p", "q", "r"])::Vector{CxxWrap.StdLib.StdStringAllocated}
    vec = StdVector{StdString}(svec_alloc)
    @test vec isa StdVector{StdString}
    @test vec == ["p", "q", "r"]

    let svec = StdString["a", "b", "c"]
      svec_ref = CxxRef.(svec)
      GC.gc()
      vec = StdVector{StdString}(svec_ref)
      GC.gc()
      @test vec isa StdVector{StdString}
      @test vec == ["a", "b", "c"]

      svec_deref = getindex.(svec_ref)::Vector{CxxWrap.StdLib.StdStringDereferenced}
      vec = StdVector{StdString}(svec_deref)
      @test vec isa StdVector{StdString}
      @test vec == ["a", "b", "c"]

      @test_throws MethodError StdVector{Bool}([true])
      @test_throws MethodError StdVector{eltype(svec_alloc)}(svec_alloc)
      @test_throws MethodError StdVector{eltype(svec_deref)}(svec_deref)

      @test svec[1] == "a"
      @test svec[2] == "b"
      @test svec[3] == "c"
    end
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

    vec = StdVector(StdString["x", "y", "z"])
    @test vec isa StdVector{StdString}
    @test vec == ["x", "y", "z"]

    svec_alloc = StdString.(["x", "y", "z"])::Vector{CxxWrap.StdLib.StdStringAllocated}
    vec = StdVector(svec_alloc)
    @test vec isa StdVector{StdString}
    @test vec == ["x", "y", "z"]

    let svec = StdString["x", "y", "z"]
      svec_ref = CxxRef.(svec)
      vec = StdVector(svec_ref)
      @test vec isa StdVector{StdString}
      @test vec == ["x", "y", "z"]

      svec_deref = getindex.(svec_ref)::Vector{CxxWrap.StdLib.StdStringDereferenced}
      vec = StdVector(svec_deref)
      @test vec isa StdVector{StdString}
      @test vec == ["x", "y", "z"]
    end

    @test_throws MethodError StdVector(["x", "y", "z"])
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
  deque1 = push!(deque1, 9)
  @test length(deque1) == 2
  for (i, x) in enumerate(deque1)
    if i == 1
      @test x == 7
    elseif i == 2
      @test x == 9
    end
  end
  @test sum(deque1) == 16
  deque2 = deque1
  popfirst!(deque2)
  @test length(deque2) == 1
end

@testset "StdQueue" begin
  @testset "Queue with integers" begin
    queue = StdQueue{Int64}()
    @test length(queue) == 0
    @test isempty(queue) == true
    push!(queue, 10)
    queue = push!(queue, 20)
    @test length(queue) == 2
    @test first(queue) == 10
    pop!(queue)
    @test first(queue) == 20
    @test length(queue) == 1
    @test isempty(queue) == false  
  end

  @testset "Queue with floats" begin
    queue = StdQueue{Float64}()
    @test length(queue) == 0
    @test isempty(queue) == true
    push!(queue, 1.54)
    push!(queue, 20.2)
    @test length(queue) == 2
    @test first(queue) == 1.54
    queue = pop!(queue)
    @test first(queue) == 20.2
    @test length(queue) == 1
    @test isempty(queue) == false  
  end
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

@testset "StdStack" begin
  @testset "Stack with integers" begin
    stack = StdStack{Int64}()
    @test length(stack) == 0
    @test isempty(stack) == true
    push!(stack, 7)
    stack = push!(stack, 20)
    push!(stack, 2)
    @test first(stack) == 2
    @test length(stack) == 3
    stack = pop!(stack)
    @test first(stack) == 20
    @test isempty(stack) == false
    while !isempty(stack) 
      pop!(stack)
    end
    @test isempty(stack) == true
  end

  @testset "Stack with floats" begin
    stack = StdStack{Float64}()
    @test length(stack) == 0
    @test isempty(stack) == true
    push!(stack, 1.54)
    push!(stack, 20.2)
    @test length(stack) == 2
    @test first(stack) == 20.2
    pop!(stack)
    @test first(stack) == 1.54
    @test length(stack) == 1
    @test isempty(stack) == false  
  end
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
      @test Set(set) == Set([10, 20]) # Tests the iterators
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
      ten_count = 0
      twenty_count = 0
      # Tests the iterators
      for x in multiset
        ten_count += x == 10
        twenty_count += x == 20
      end
      @test ten_count == 1
      @test twenty_count == 2
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

@testset "StdList" begin
  @testset "StdList with StdString" begin
    list = StdList{StdString}()
    @test isempty(list) == true
    @test length(list) == 0
    push!(list, StdString("ab"))
    list = pushfirst!(list, StdString("cd"))
    list = push!(list, StdString("ef"))
    @test length(list) == 3
    for (i, x) in enumerate(list)
      if i == 1
        @test x == "cd"
      elseif i == 2
        @test x == "ab"
      elseif i == 3
        @test x == "ef"
      end
    end
    @test prod(list) == "cdabef"
    @test first(list) == "cd"
    @test last(list) == "ef"
    list = pop!(list)
    @test last(list) == "ab"
    list = popfirst!(list)
    @test first(list) == "ab"
    list = empty!(list)
    @test isempty(list) == true
  end
  
  @testset "StdList with integers" begin
    list = StdList{Int64}()
    @test isempty(list) == true
    @test length(list) == 0
    list = push!(list, 10)
    pushfirst!(list, 20)
    list = pushfirst!(list, 30)
    @test first(list) == 30
    list = popfirst!(list)
    @test first(list) == 20
    @test last(list) == 10
    @test length(list) == 2
    empty!(list)
    @test isempty(list) == true
  end
end

@testset "StdForwardList" begin
  @testset "StdForwardList with integers" begin
    forwardlist = StdForwardList{Int64}()
    @test isempty(forwardlist) == true
    forwardlist = pushfirst!(forwardlist, 10)
    pushfirst!(forwardlist, 20)
    @test first(forwardlist) == 20
    for (i, x) in enumerate(forwardlist)
      if i == 1
        @test x == 20
      elseif i == 2
        @test x == 10
      end
    end
    forwardlist = popfirst!(forwardlist)
    @test first(forwardlist) == 10
    for x in forwardlist
      @test x == 10
    end
    @test isempty(forwardlist) == false
    forwardlist = empty!(forwardlist)
    @test isempty(forwardlist) == true
  end

  @testset "StdForwardList with StdString" begin
    forwardlist = StdForwardList{StdString}()
    @test isempty(forwardlist) == true
    forwardlist = pushfirst!(forwardlist, StdString("ab"))
    pushfirst!(forwardlist, StdString("cd"))
    @test first(forwardlist) == "cd"
    forwardlist = popfirst!(forwardlist)
    @test first(forwardlist) == "ab"
    @test isempty(forwardlist) == false
    forwardlist = empty!(forwardlist)
    @test isempty(forwardlist) == true
  end
end

@static if isdefined(StdLib, :HAS_RANGES)

@testset "STL algorithms" begin
  @testset "StdFill" begin
    v = StdList{Int64}()
    for x in 1:10
      push!(v, x)
    end
    fill!(v, 1)
    for x in v
      @test x == 1
    end
    
    v = StdForwardList{Int64}()
    for x in 1:10
      pushfirst!(v, x)
    end
    fill!(v, 1)
    for x in v
      @test x == 1
    end
  end

  @testset "StdUpperBound and StdLowerBound" begin
    containers = (StdSet{Int64}(), StdMultiset{Int64}(), StdList{Int64}())
    for container in containers
      for i in 1:2:11
        push!(container, i)
      end
    end
    
    for container in containers
      for val in container
        @test StdLib.iterator_value(StdLowerBound(container, val)) == val
        @test StdLib.iterator_value(StdUpperBound(container, val - 1)) == val
      end
    end
  end
  
  @testset "StdBinarySearch" begin
    containers = (StdVector{Int64}(), StdDeque{Int64}(), StdSet{Int64}(), StdMultiset{Int64}(), StdList{Int64}())
    for container in containers
      for i in 1:2:11
        push!(container, i)
      end
    end

    for container in containers
      for i in 1:11
        @test StdBinarySearch(container, i) == isodd(i)
      end
    end
  end

  @testset "StdListSort" begin
    list = StdList{Int64}()
    v = [1, -1, 0, 4, 20]
    for x in v
      push!(list, x)
    end
    v = sort!(v)
    list = sort!(list)
    for (a, b) in zip(list, v)
      @test a == b
    end
  end
end

end

end
