# Hello world example, similar to the Boost.Python hello world

using Base.Test
using Compat
using CxxWrap

# Wrap the functions defined in C++
wrap_modules(CxxWrap._l_types)

using CppTypes
using CppTypes.World

# Stress test
for i in 1:1000000
  d = CppTypes.DoubleData()
end

# Default constructor
@test World <: CxxWrap.CppAny
@test supertype(World) == CxxWrap.CppAny
w = World()
println("Dumping type w...")
dump(w)
@test CppTypes.greet(w) == "default hello"

@show fw = CppTypes.world_factory()
@test CppTypes.greet(fw) == "factory hello"

@show swf = CppTypes.shared_world_factory()
@test CppTypes.greet(swf) == "shared factory hello" # Uses the shared ptr overload
@test CppTypes.greet(CppTypes.get(swf)) == "shared factory hello" # Explicitly get the shared ptr

@show uwf = CppTypes.unique_world_factory()
@test CppTypes.greet(CppTypes.get(uwf)) == "unique factory hello"

CppTypes.set(w, "hello")
@show CppTypes.greet(w)
@test CppTypes.greet(w) == "hello"

w = World("constructed")
@test CppTypes.greet(w) == "constructed"

w_assigned = w
w_deep = deepcopy(w)

@test w_assigned == w
@test w_deep != w

# Destroy w: w and w_assigned should be dead, w_deep alive
finalize(w)
println("finalized w")
if !(is_windows() && Sys.WORD_SIZE == 32)
  @test_throws ErrorException CppTypes.greet(w)
  println("throw test 1 passed")
  @test_throws ErrorException CppTypes.greet(w_assigned)
  println("throw test 2 passed")
end
@test CppTypes.greet(w_deep) == "constructed"
println("completed deepcopy test")

noncopyable = CppTypes.NonCopyable()
other_noncopyable = deepcopy(noncopyable)
@test other_noncopyable.cpp_object == noncopyable.cpp_object

import CppTypes.ImmutableDouble

if VERSION >= v"0.5" # not supported on 0.4 anymore
  @test sizeof(ImmutableDouble) == 8
  @test isbits(ImmutableDouble)
  @test length(fieldnames(ImmutableDouble)) == 1
  println("creating bitsval1")
  bitsval1 = ImmutableDouble(1)
  println("created bitsval1")
  @test bitsval1.value == 1.
  @test bitsval1 == 1.
  @test CppTypes.getvalue(bitsval1) == 1
  bitsval2 = CppTypes.ImmutableDouble(2)
  @test bitsval2 == 2
  @test typeof(bitsval1 + bitsval2) == CppTypes.ImmutableDouble
  @test (bitsval1 + bitsval2) == 3.
end

@test value(value(ReturnConstRef())) == 42

wptr = World()
@test CppTypes.greet(ConstPtrConstruct(wptr)) == "default hello"

call_op = CallOperator()
@test call_op() == 43

type JuliaTestType
    a::Float64
    b::Float64
end

function julia_test_func(data)
  println("a: ", data.a, ", b: ", data.b)
  @test data.a == 2.
  @test data.b == 3.
end

CppTypes.call_testype_function()

@test enum_to_int(CppTypes.EnumValA) == 0
@test enum_to_int(CppTypes.EnumValB) == 1
@test get_enum_b() == CppTypes.EnumValB
