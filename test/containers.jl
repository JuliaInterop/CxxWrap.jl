using Test

function func1(arr)
  @test arr[1] == 1.0
  @test arr[2] == 2.0
  @test arr[3] == 3.0
end

module Containers
  include(joinpath(@__DIR__, "testcommon.jl"))
  @wrapmodule CxxWrap.CxxWrapCore.libjlcxx_containers()

  function __init__()
    @initcxx
  end

  export test_tuple, const_ptr, const_ptr_arg, const_vector, const_matrix
end
using Main.Containers

@testset "$(basename(@__FILE__)[1:end-3])" begin

@test test_tuple() == (1,2.0,3.0f0)

cptr = const_ptr()
@test isbitstype(typeof(cptr))
@test const_ptr_arg(cptr) == (1., 2., 3.)

let cv = const_vector(), n = 1000000
  @test size(cv) == (3,)
  result = zeros(3)
  for i in 1:n
    result .+= const_vector()
  end
  @test result == n*[1.,2.,3.]
end

cm = const_matrix()
@test size(cm) == (3,2)
@test cm == [[1.,2.,3.] [4.,5.,6.]]
println("Displaying const matrix")
display(cm)
println()

mm = Containers.mutable_array()
println("Displaying mutable matrix")
display(mm)
println()
mm .= 1.0
@test Containers.check_mutable_array(mm)
Containers.do_embedding_test()

@test Containers.array_return() == ["hello", "world"]
@test Containers.tuple_int_pointer() == (C_NULL,1)

let a1 = [UInt8(3)], a2 = [UInt8(5)]
  @test Containers.uint8_ptr(pointer(a1)) == 3
  @test Containers.uint8_ptr(pointer(a2)) == 5
  @test Containers.uint8_arrayref([pointer(a1), pointer(a2)]) == 8
end

end