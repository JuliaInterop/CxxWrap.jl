using .StdLib: StdStack

Base.size(v::StdStack) = (Int(cppsize(v)),)
Base.length(v::StdStack) = Int(cppsize(v))
Base.isempty(v::StdStack) = stack_isempty(v)
Base.push!(v::StdStack, x) = (stack_push!(v, x); v)
Base.first(v::StdStack) = stack_top(v)
Base.pop!(v::StdStack) = (stack_pop!(v); v)