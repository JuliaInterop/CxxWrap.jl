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
  @test length(deque1) == 0
  push!(deque1, 7)
  push!(deque1, 9)
  @test length(deque1) == 2
  deque2 = deque1
  popfirst!(deque2)
  @test length(deque2) == 1
end

end
