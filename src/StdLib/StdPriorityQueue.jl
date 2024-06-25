using .StdLib: StdPriorityQueue

Base.size(v::StdPriorityQueue) = (Int(cppsize(v)),)
Base.length(v::StdPriorityQueue) = Int(cppsize(v))
Base.isempty(v::StdPriorityQueue) = pq_isempty(v)
Base.first(v::StdPriorityQueue) = isempty(v) ? nothing : pq_top(v)
Base.push!(v::StdPriorityQueue, x) = (pq_push!(v, x); v)
function Base.pop!(v::StdPriorityQueue)
    isempty(v) && throw(ArgumentError("Cannot pop from an empty priority queue"))
    val = pq_top(v)
    pq_pop!(v)
    return val
end