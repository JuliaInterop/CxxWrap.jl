using .StdLib: StdQueue

Base.size(v::StdQueue) = (Int(cppsize(v)),)
Base.length(v::StdQueue) = Int(cppsize(v))
Base.isempty(v::StdQueue) = q_empty(v)
Base.push!(v::StdQueue, x) = (push_back!(v, x); v)
Base.first(v::StdQueue) = front(v)
Base.pop!(v::StdQueue) = (pop_front!(v); v)