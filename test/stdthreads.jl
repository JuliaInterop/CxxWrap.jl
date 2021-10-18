using CxxWrap
using Test

const collectedvalues = zeros(3)
const nbcollected = Ref(0)
const controlvalue = Ref(0.0)
const currentvalue = Ref(0.0)

const t1status = Ref("")
const t2status = Ref("")

#const collectedptr = pointer(collectedvalues)


function updatevalue()
  t2status[] = "started"
  while true
    if controlvalue[] < 1.0
      currentvalue[] = 2.0
    elseif controlvalue[] < 2.0
      currentvalue[] = 3.0
    elseif  controlvalue[] < 3.0
      currentvalue[] = 4.0
    else
      t2status[] = "finished"
      return
    end
  end
end

function collectvalues()
  t1status[] = "started"
  while true
    i = nbcollected[]
    x = currentvalue[]
    if x == 0
      continue
    end
    @inbounds if i == 0
      collectedvalues[1] = x
      nbcollected[] += 1
    elseif collectedvalues[i] != x
      collectedvalues[i+1] = x
      nbcollected[] += 1
    end
    if nbcollected[] == 3
      t1status[] = "finished"
      return
    end
  end
end

updatevalue_c = @safe_cfunction(updatevalue, Cvoid, ())
collectvalues_c = @safe_cfunction(collectvalues, Cvoid, ())
t1 = StdThread(collectvalues_c)
t2 = StdThread(updatevalue_c)

t1_orig_handle = StdLib.get_id(t1)
t2_orig_handle = StdLib.get_id(t2)
StdLib.swap(t1,t2)
@test t1_orig_handle == StdLib.get_id(t2)
@test t2_orig_handle == StdLib.get_id(t1)

@test StdLib.joinable(t1)
@test StdLib.joinable(t2)
@test t1status[] == t2status[] == "started"

@test currentvalue[] == 2

controlvalue[] = 1

@test currentvalue[] == 3

controlvalue[] = 2

@test currentvalue[] == 4
controlvalue[] = 5

@test t1status[] == t2status[] == "finished"

StdLib.join(t1)
StdLib.join(t2)

@test !StdLib.joinable(t1)
@test !StdLib.joinable(t2)
@test collectedvalues == [2.0, 3.0, 4.0]
