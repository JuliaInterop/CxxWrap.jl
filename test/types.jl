include(joinpath(@__DIR__, "testcommon.jl"))

# Wrap the functions defined in C++
module CppTypes

using CxxWrap

struct ImmutableBits
  a::Float64
  b::Float64
end

@wrapmodule(Main.libtypes)

export enum_to_int, get_enum_b, World
export AConstRef, ReturnConstRef, value, CallOperator, ConstPtrConstruct

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
@test CppTypes.greet(fw) == "factory hello"

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
@test_throws ErrorException CppTypes.greet_weak(swf2) == "shared factory hello"

swfr = CppTypes.shared_world_ref()
@test CppTypes.greet(swfr) == "shared factory hello ref"
CppTypes.reset_shared_world!(swfr, "reset shared pointer")
@test CppTypes.greet(swfr) == "reset shared pointer"
CppTypes.reset_shared_world!(swfr, "shared factory hello ref")

@test CppTypes.greet(CppTypes.boxed_world_factory()) == "boxed world"
@test CppTypes.greet(CppTypes.boxed_world_pointer_factory()) == "boxed world pointer"
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
@test CppTypes.greet(CppTypes.ConstPtrConstruct(wptr)) == "default hello"

call_op = CppTypes.CallOperator()
@test call_op() == 43
@test call_op(42) == 42

mutable struct JuliaTestType
    a::Float64
    b::Float64
end

function julia_test_func(data)
  println("a: ", data.a, ", b: ", data.b)
  @test data.a == 2.
  @test data.b == 3.
end

CppTypes.call_testype_function()

@test CppTypes.enum_to_int(CppTypes.EnumValA) == 0
@test CppTypes.enum_to_int(CppTypes.EnumValB) == 1
@test CppTypes.get_enum_b() == CppTypes.EnumValB
@test CppTypes.EnumValA + CppTypes.EnumValB == CppTypes.EnumValB
@test CppTypes.EnumValA | CppTypes.EnumValB == CppTypes.EnumValB

foovec = Any[CppTypes.Foo("a", [1.0, 2.0, 3.0]), CppTypes.Foo("b", [11.0, 12.0, 13.0])] # Must be Any because of the boxing
@show CppTypes.name(foovec[1])
@show CppTypes.data(foovec[1])
CppTypes.print_foo_array(foovec)

@test !isnull(CppTypes.return_ptr())
@test isnull(CppTypes.return_null())

imm = CppTypes.ImmutableBits(1.0, 2.0)
@show CppTypes.increment_immutable(imm)