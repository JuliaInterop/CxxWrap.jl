using CxxWrap
using Base.Test

wrap_modules(CxxWrap._l_containers)
using Containers

#println(Base.uncompressed_ast(first(methods(test_tuple))))

@test test_tuple() == (1,2.0,3.0f0)

cptr = const_ptr()
@test isbits(typeof(cptr))
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
mm[:,:] = 1.0
@test Containers.check_mutable_array(mm)
