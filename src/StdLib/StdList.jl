using .StdLib: StdList

Base.size(v::StdList) = (Int(cppsize(v)),)
Base.length(v::StdList) = Int(cppsize(v))
Base.isempty(v::StdList) = list_isempty(v)
Base.first(v::StdList) = list_front(v)
Base.last(v::StdList) = list_back(v)
Base.empty!(v::StdList) = (list_empty!(v); v)
Base.push!(v::StdList, x) = (list_push_back!(v, x); v)
Base.pushfirst!(v::StdList, x) = (list_push_front!(v, x); v)
Base.pop!(v::StdList) = (list_pop_back!(v); v)
Base.popfirst!(v::StdList) = (list_pop_front!(v); v)


Base.:(==)(a::StdListIterator, b::StdListIterator) = iterator_is_equal(a, b)
_list_iteration_tuple(v::StdList, state::StdListIterator) = (state == iteratorend(v)) ? nothing : (iterator_value(state), state)
Base.iterate(v::StdList) = _list_iteration_tuple(v, iteratorbegin(v))
Base.iterate(v::StdList, state::StdListIterator) = (state != iteratorend(v)) ? _list_iteration_tuple(v, iterator_next(state)) : nothing

function Base.show(io::IO, ::MIME"text/plain", container::StdList{T}) where {T}
    n = length(container)
    print(io, "StdList{", T, "} with ", n, " element", n == 1 ? "" : "s")

    n == 0 && return
    print(io, ":")
    for item in Iterators.take(container, 10)
        print(io, "\n  ", item)
    end
    if n > 10
        print(io, "\n  ⋮")
    end
end