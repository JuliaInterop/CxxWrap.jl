function func1(arr)
  @test arr[1] == 1.0
  @test arr[2] == 2.0
  @test arr[3] == 3.0
end

module Containers
  include(joinpath(@__DIR__, "testcommon.jl"))
  @wrapmodule libjlcxx_containers

  export test_tuple, const_ptr, const_ptr_arg, const_vector, const_matrix
end
using Main.Containers

@test test_tuple() == (1,2.0,3.0f0)

cptr = const_ptr()
@test isbitstype(typeof(cptr))
@test const_ptr_arg(cptr) == (1., 2., 3.)

cv = const_vector()
@test size(cv) == (3,)
@test cv == [1.,2.,3.]

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
