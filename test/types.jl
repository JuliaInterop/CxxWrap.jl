include(joinpath(@__DIR__, "testcommon.jl"))

# Wrap the functions defined in C++
module CppTypes

using CxxWrap

GC.gc()
@readmodule(CxxWrap.CxxWrapCore.libtypes())
@wraptypes
CxxWrap.argument_overloads(t::Type{MyEnum}) = [Integer,MyEnum]
@wrapfunctions
GC.gc()

function __init__()
  @initcxx
end

const greet = getindex ∘ greet_cref

export enum_to_int, get_enum_b, World
export AConstRef, ReturnConstRef, value, CallOperator, ConstPtrConstruct

julia_greet1(w::World) = greet_lambda(w)
@cxxdereference julia_greet2(w::World) = greet_lambda(w)

end

module CppTypes2

using CxxWrap

@wrapmodule CxxWrap.CxxWrapCore.libtypes() :define_types2_module

function __init__()
  @initcxx
end

end

module CppTypes3

using CxxWrap

@wrapmodule CxxWrap.CxxWrapCore.libtypes() :define_types3_module

function __init__()
  @initcxx
end

end

# Stress test
function testalloc(n)
  nb_created = 0
  for i in 1:n
    nb_created +=  Int(!isnull(CxxRef(CppTypes.DoubleData())))
  end
end

function bench_greet()
  w = CppTypes.World()
  l = 0
  for i = 1:1000
    l += length(CppTypes.greet(w))
  end
  return l
end

mutable struct JuliaTestType
    a::Float64
    b::Float64
end

function julia_test_func(data)
  println("a: ", data.a, ", b: ", data.b)
  @test data.a == 2.0
  @test data.b == 3.0
end

return_int() = Int32(3)
a = [4.0]
return_ptr_double() = pointer(a)
return_world() = CppTypes.World("returned_world")
wptr = CppTypes.World("returned_world_ptr")
wref = CppTypes.World("returned_world_ref")
return_world_ptr() = CxxPtr(wptr)
return_world_ref() = CxxRef(wref)

@testset "$(basename(@__FILE__)[1:end-3])" begin

# Default constructor
w = CppTypes.World()
println("Dumping type w...")
dump(w)
@test CppTypes.greet(w) == "default hello"

@show fw = CppTypes.world_factory()
@test CppTypes.greet(fw[]) == "factory hello"

swf = CppTypes.shared_world_factory()
@test CppTypes.greet_shared(swf) == "shared factory hello"
@test CppTypes.greet_shared_const(swf) == "shared factory hello"
@test CppTypes.greet(swf[]) == "shared factory hello" # Explicit dereference
@test CppTypes.greet(swf) == "shared factory hello" # Automatic conversion
swf2 = CppTypes.smart_world_factory()
@test CppTypes.greet_smart(swf2) == "smart factory hello"
@test CppTypes.greet_smart(swf) == "shared factory hello" # auto-convert between pointers
@test CppTypes.greet(swf2[]) == "smart factory hello" # Explicit dereference
@test CppTypes.greet(swf2) == "smart factory hello" # Automatic conversion
@test CppTypes.greet_weak(swf) == "shared factory hello"
@test_throws MethodError CppTypes.greet_weak(swf2) == "shared factory hello"

swfr = CppTypes.shared_world_ref()
@test CppTypes.greet(swfr[]) == "shared factory hello ref"
CppTypes.reset_shared_world!(swfr, "reset shared pointer")
@test CppTypes.greet(swfr[]) == "reset shared pointer"
CppTypes.reset_shared_world!(swfr, "shared factory hello ref")

@test CppTypes.greet(CppTypes.boxed_world_factory()) == "boxed world"
@test CppTypes.greet(CppTypes.boxed_world_pointer_factory()[]) == "boxed world pointer"
@test CppTypes.greet(CppTypes.world_ref_factory()) == "reffed world"

@show uwf = CppTypes.unique_world_factory()
@test CppTypes.greet(uwf) == "unique factory hello"

byval = CppTypes.world_by_value()
@test CppTypes.greet(byval) == "world by value hello"

CppTypes.set(w, "hello")
@show CppTypes.greet(w)
@test CppTypes.greet(w) == "hello"
@test CppTypes.greet_lambda(w) == "hello"

w = CppTypes.World("constructed")
@test CppTypes.greet(w) == "constructed"

w_assigned = w
w_copy = copy(w)

@test w_assigned == w
@test w_copy != w

# Destroy w: w and w_assigned should be dead, w_copy alive
finalize(w)
println("finalized w")
if !(Sys.iswindows() && Sys.WORD_SIZE == 32)
  @test_throws ErrorException CppTypes.greet(w)
  println("throw test 1 passed")
  @test_throws ErrorException CppTypes.greet(w_assigned)
  println("throw test 2 passed")
end
@test CppTypes.greet(w_copy) == "constructed"
println("completed copy test")

wnum = CppTypes.World(1)
@test CppTypes.greet(wnum) == "NumberedWorld"
finalize(wnum)
@test CppTypes.greet(wnum) == "NumberedWorld"

noncopyable = CppTypes.NonCopyable()
@test_throws MethodError other_noncopyable = copy(noncopyable)

@test CppTypes.value(CppTypes.value(CppTypes.ReturnConstRef())) == 42

wptr = CppTypes.World()
@test CppTypes.greet(CppTypes.ConstPtrConstruct(CxxPtr(wptr))) == "default hello"

call_op = CppTypes.CallOperator()
@test call_op() == 43
@test call_op(42) == 42

CppTypes.call_testtype_function()

@test CppTypes.enum_to_int(CppTypes.EnumValA) == 0
@test CppTypes.enum_to_int(CppTypes.EnumValB) == 1
@test CppTypes.enum_to_int(1) == 1
@test call_op(CppTypes.EnumValB) == 1

@test CppTypes.get_enum_b() == CppTypes.EnumValB
@test CppTypes.EnumValA + CppTypes.EnumValB == CppTypes.EnumValB
@test CppTypes.EnumValA | CppTypes.EnumValB == CppTypes.EnumValB
@show CppTypes.EnumClassBlue
@test CppTypes.check_red(CppTypes.EnumClassRed)

foovec = Any[CppTypes.Foo(StdWString("a"), [1.0, 2.0, 3.0]), CppTypes.Foo(StdWString("b"), [11.0, 12.0, 13.0])] # Must be Any because of the boxing
@test CppTypes.name(foovec[1]) == "a"
@test CppTypes.data(foovec[1]) == [1.0, 2.0, 3.0]
@test CppTypes.name(foovec[2]) == "b"
@test CppTypes.data(foovec[2]) == [11.0, 12.0, 13.0]
CppTypes.print_foo_array(foovec)

@test !isnull(CppTypes.return_ptr())
@test isnull(CppTypes.return_null())

warr1 = CppTypes.World[CppTypes.World("world$i") for i in 1:5]
warr2 = [CppTypes.World("worldalloc$i") for i in 1:5]
wvec1 = StdVector(warr1)
wvec2 = StdVector(warr2)

for (i,(w1,w2)) in enumerate(zip(wvec1,wvec2))
  @test CppTypes.greet(w1) == "world$i"
  @test CppTypes.greet(w2) == "worldalloc$i"
end

let wvec_copy = copy.(wvec2)
  @test typeof(wvec_copy) == Vector{CppTypes.WorldAllocated}
  @test typeof(wvec_copy[1]) == CppTypes.WorldAllocated
end

@test CppTypes.greet_vector(wvec1) == string(("world$i " for i in 1:5)...)[1:end-1]

@test CppTypes.test_unbox() == fill(true,7)

@test_throws MethodError CppTypes.julia_greet1(fw)
@test_throws MethodError CppTypes.julia_greet1(swf)
@test CppTypes.julia_greet2(fw) == "factory hello"
@test CppTypes.julia_greet2(swf) == "shared factory hello"

@test bench_greet() == 1000*length(CppTypes.greet(CppTypes.World()))
_, _, _, _, memallocs = @timed bench_greet()
@test 0 < memallocs.poolalloc < 100

if isdefined(CppTypes, :IntDerived)
  Base.promote_rule(::Type{<:CppTypes.IntDerived}, ::Type{<:Number}) = Int
  @test CppTypes.IntDerived() == CppTypes.IntDerived()
  @test CppTypes.IntDerived() == 42
end

let weq = CppTypes.World()
  weqref1 = CxxRef(weq)
  weqptr1 = CxxPtr(weq)
  weqref2 = CxxRef(weq)
  weqptr2 = CxxPtr(weq)
  @test weqptr1 == weqptr2
  @test weqref1 == weqref2
  @test weq == weqref1
  @test weq == weqref1[]
  @test weqref2[] == weqptr1[]
  d = Dict{CppTypes.World, Int}()
  d[weqref1[]] = 1
  d[weqref2[]] += 1
  d[weqptr1[]] += 1
  d[weqptr2[]] += 1
  @test length(d) == 1
  @test d[weqref1[]] == 4
end

let vvec1 = StdVector([StdVector([Int32(3)])]), vvec2 = StdVector([StdVector([CppTypes.World("vvec")])])
  @test CppTypes2.vecvec(vvec1) == 3
  @test CppTypes3.vecvec(vvec1) == 6
  @test CppTypes.greet(CppTypes2.vecvec(vvec2)) == "vvec"
  @show @test CppTypes.greet(CppTypes3.vecvec(vvec2)) == "vvec"
end

end

let n = 100000
  GC.gc()
  @timed testalloc(1)
  (_, t, _, _, memallocs) = @timed testalloc(n)
  println("$n allocations took $t s")
  @test memallocs.poolalloc <= (n+4)
end
