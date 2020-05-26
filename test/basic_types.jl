module BasicTypes
  include(joinpath(@__DIR__, "testcommon.jl"))

  struct ImmutableBits
    a::Float64
    b::Float64
  end

  mutable struct MutableBits
    a::Float64
    b::Float64
  end

  struct A
    x :: Float32
    y :: Float32
  end

  @wrapmodule CxxWrap.CxxWrapCore.libbasic_types()

  function __init__()
    @initcxx
  end
end

using CxxWrap
using Test

result = Ref(0.0)
function test_boxed_struct(x)
    result[] = x.a + x.b
    return
end

@testset "$(basename(@__FILE__)[1:end-3])" begin

let funcs = CxxWrap.CxxWrapCore.get_module_functions(CxxWrap.StdLib)
  @test CxxWrap.StdLib.__cxxwrap_methodkeys[1] == CxxWrap.CxxWrapCore.methodkey(funcs[1])
  @test all(CxxWrap.StdLib.__cxxwrap_methodkeys .== CxxWrap.CxxWrapCore.methodkey.(funcs))
end

let a = BasicTypes.A(2,3)
  @test BasicTypes.f(a) == 5.0
  @test BasicTypes.g(a) == 5.0
  @test BasicTypes.g(Ref(a)) == 5.0
  @test BasicTypes.h(Ref(a)) == 5.0
  @test BasicTypes.h(C_NULL) == 0.0
end

let imm = BasicTypes.ImmutableBits(1.0, 2.0)
  @test BasicTypes.increment_immutable(Ref(imm)) == BasicTypes.ImmutableBits(2.0, 3.0)
end

let f = Float32(5.0), a = [f]
  @test BasicTypes.twice_val(f) == 10.0
  @test BasicTypes.twice_cref(f) == 10.0
  @test BasicTypes.twice_ref(Ref(f)) == 10.0
  @test BasicTypes.twice_cptr(Ref(f)) == 10.0
  @test BasicTypes.twice_ptr(Ref(f)) == 10.0
  @test BasicTypes.twice_ptr(pointer(a)) == 10.0
  @test BasicTypes.twice_ptr(a) == 10.0
  BasicTypes.twice_ptr_mut(a)
  @test a[1] == 10.0
end

let f = Ref(Float32(2.0))
  BasicTypes.twice_ref_mut(f)
  @test f[] == 4.0
end

let a = Ref(BasicTypes.A(1,2))
  b = BasicTypes.return_a_ptr(a)
  @test a[].x == 2
  @test a[].y == 3
  @test unsafe_load(b) == a[]

  b = BasicTypes.return_a_cptr(a)
  @test a[].x == 3
  @test a[].y == 4
  @test unsafe_load(b) == a[]

  b = BasicTypes.return_a_ref(a)
  @test a[].x == 4
  @test a[].y == 5
  @test b[] == a[]

  b = BasicTypes.return_a_cref(a)
  @test a[].x == 5
  @test a[].y == 6
  @test b[] == a[]
end

let s = "abc"
  @test BasicTypes.strlen_cchar(s) == length(s)
  @test BasicTypes.strlen_char(s) == length(s)
end

let s = StdString("hello")
  @test BasicTypes.strlen_str(s) == 5
  @test BasicTypes.strlen_strcref(s) == 5
  @test BasicTypes.strlen_strref(s) == 5
  @test BasicTypes.strlen_strptr(CxxPtr(s)) == 5
  @test BasicTypes.strlen_strcptr(ConstCxxPtr(s)) == 5
end

let s = BasicTypes.StringHolder("hello")
  # Check reference return values
  @test BasicTypes.str_return_val(s) == "hello"
  @test BasicTypes.str_return_cref(s)[] == "hello"
  strref = BasicTypes.str_return_ref(s)
  @test strref[] == "hello"
  strptr = BasicTypes.str_return_ptr(s)
  @test strptr[] == "hello"
  @test BasicTypes.str_return_cptr(s)[] == "hello"

  # Modification through reference
  BasicTypes.replace_str_val!(strref, "world")
  @test strref[] == "world"
  @test strptr[] == "world"
  @test BasicTypes.str_return_val(s) == "world"

  # Modification through pointer
  BasicTypes.replace_str_val!(CxxRef(strptr), "bye!")
  @test strref[] == "bye!"
  @test strptr[] == "bye!"
  @test BasicTypes.str_return_val(s) == "bye!"

  # Modification through value
  strval = BasicTypes.str_return_val(s)
  BasicTypes.replace_str_val!(strval, "no really, bye!")
  @test strval == "no really, bye!"
  @test strptr[] == "bye!"

  # Check that const is respected
  strcref = BasicTypes.str_return_cref(s)
  strcptr = BasicTypes.str_return_cptr(s)
  @test_throws MethodError BasicTypes.replace_str_val!(strcref, "can't work")
  @test_throws MethodError BasicTypes.replace_str_val!(strcptr, "can't work")
end

let cfunc = @safe_cfunction(test_boxed_struct, Cvoid, (Any,))
  BasicTypes.boxed_mirrored_type(cfunc)
  @test result[] == 3.0

  BasicTypes.boxed_mutable_mirrored_type(cfunc)
  @test result[] == 5.0
end

let a = CxxChar(3), b = CxxWchar(2)
  @test typeof(a*b) == CxxWrap.CxxWrapCore.julia_int_type(CxxWchar)
  @test typeof(a+b) == CxxWrap.CxxWrapCore.julia_int_type(CxxWchar)
  @test typeof(a/b) == Float64
  @test a*b == 6
  @test a+b == 5
  @test typeof(a/a) == Float64
  @test typeof(a+a) == CxxWrap.CxxWrapCore.julia_int_type(CxxChar)
  @test typeof(a*a) == CxxWrap.CxxWrapCore.julia_int_type(CxxChar)
end

let buf = IOBuffer()
  show(buf,CxxBool(true))
  @test String(take!(buf)) == "true"
  show(buf,CxxLong(42))
  @test String(take!(buf)) == "42"
end

@test BasicTypes.test_for_each_type() == (sizeof(Float32) + sizeof(Float64))

@test BasicTypes.strict_method(CxxChar(1)) == "char"
@test BasicTypes.strict_method(CxxLong(1)) == "long"
@test_throws MethodError BasicTypes.strict_method(Int16(1))
@test BasicTypes.strict_method(CxxBool(true)) == "bool"
@test BasicTypes.strict_method(true) == "bool"
@test BasicTypes.loose_method(Int32(3)) == "int"
@test BasicTypes.loose_method(false) == "bool"

let (intnames, inttypes) = BasicTypes.julia_integer_mapping()
  lmax = maximum(length.(intnames))
  for (name, type) in zip(intnames, inttypes)
    padding = repeat(' ', lmax-length(name))
    println("$name$padding -> $type")
  end
end

end