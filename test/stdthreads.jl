using CxxWrap
using Test

const threadvalues = zeros(2)

function updatevalue(i)
  @inbounds while threadvalues[i] < i*1e7 
    threadvalues[i] += i
  end
end

t1_cfunc = @safe_cfunction(() -> updatevalue(1), Cvoid, ())
t2_cfunc = @safe_cfunction(() -> updatevalue(2), Cvoid, ())
t1 = StdThread(t1_cfunc)
t2 = StdThread(t2_cfunc)

t1_orig_handle = StdLib.get_id(t1)
t2_orig_handle = StdLib.get_id(t2)
StdLib.swap(t1,t2)
@test t1_orig_handle == StdLib.get_id(t2)
@test t2_orig_handle == StdLib.get_id(t1)

@test StdLib.joinable(t1)
@test StdLib.joinable(t2)

StdLib.join(t1)
StdLib.join(t2)

@test !StdLib.joinable(t1)
@test !StdLib.joinable(t2)
@test threadvalues == [1e7, 2e7]
