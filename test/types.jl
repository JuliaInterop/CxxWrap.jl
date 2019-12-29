include(joinpath(@__DIR__, "testcommon.jl"))

# Wrap the functions defined in C++
module CppTypes

using CxxWrap

@wrapmodule(Main.libtypes)

const greet = getindex ∘ greet_cref

export enum_to_int, get_enum_b, World
export AConstRef, ReturnConstRef, value, CallOperator, ConstPtrConstruct

julia_greet1(w::World) = greet_lambda(w)
@cxxdereference julia_greet2(w::World) = greet_lambda(w)

end

# Stress test
for i in 1:1000000
  global d = CppTypes.DoubleData()
end

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
w_deep = deepcopy(w)

@test w_assigned == w
@test w_deep != w

# Destroy w: w and w_assigned should be dead, w_deep alive
finalize(w)
println("finalized w")
if !(Sys.iswindows() && Sys.WORD_SIZE == 32)
  @test_throws ErrorException CppTypes.greet(w)
  println("throw test 1 passed")
  @test_throws ErrorException CppTypes.greet(w_assigned)
  println("throw test 2 passed")
end
@test CppTypes.greet(w_deep) == "constructed"
println("completed deepcopy test")

wnum = CppTypes.World(1)
@test CppTypes.greet(wnum) == "NumberedWorld"
finalize(wnum)
@test CppTypes.greet(wnum) == "NumberedWorld"

noncopyable = CppTypes.NonCopyable()
other_noncopyable = deepcopy(noncopyable)
@test other_noncopyable.cpp_object == noncopyable.cpp_object

@test CppTypes.value(CppTypes.value(CppTypes.ReturnConstRef())) == 42

wptr = CppTypes.World()
@test CppTypes.greet(CppTypes.ConstPtrConstruct(CxxPtr(wptr))) == "default hello"

call_op = CppTypes.CallOperator()
@test call_op() == 43
@test call_op(42) == 42

mutable struct JuliaTestType
    a::Float64
    b::Float64
end

function julia_test_func(data)
  println("a: ", data.a, ", b: ", data.b)
  @test data.a == 2.0
  @test data.b == 3.0
end

CppTypes.call_testtype_function()

@test CppTypes.enum_to_int(CppTypes.EnumValA) == 0
@test CppTypes.enum_to_int(CppTypes.EnumValB) == 1
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

@test CppTypes.greet_vector(wvec1) == string(("world$i " for i in 1:5)...)[1:end-1]

a = [4.0]
return_int() = Int32(3)
return_ptr_double() = pointer(a)
return_world() = CppTypes.World("returned_world")
wptr = CppTypes.World("returned_world_ptr")
wref = CppTypes.World("returned_world_ref")
return_world_ptr() = CxxPtr(wptr)
return_world_ref() = CxxRef(wref)

@test CppTypes.test_unbox() == fill(true,7)

@test_throws MethodError CppTypes.julia_greet1(fw)
@test_throws MethodError CppTypes.julia_greet1(swf)
@test CppTypes.julia_greet2(fw) == "factory hello"
@test CppTypes.julia_greet2(swf) == "shared factory hello"