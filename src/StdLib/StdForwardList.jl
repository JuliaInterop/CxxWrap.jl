using .StdLib: StdForwardList

Base.isempty(v::StdForwardList) = flist_isempty(v)
Base.first(v::StdForwardList) = flist_front(v)
Base.empty!(v::StdForwardList) = (flist_empty!(v); v)
Base.pushfirst!(v::StdForwardList, x) = (flist_push_front!(v, x); v)
Base.popfirst!(v::StdForwardList) = (flist_pop_front!(v); v)

Base.:(==)(a::StdForwardListIterator, b::StdForwardListIterator) = iterator_is_equal(a, b)
_forward_list_iteration_tuple(v::StdForwardList, state::StdForwardListIterator) = (state == iteratorend(v)) ? nothing : (iterator_value(state), state)
Base.iterate(v::StdForwardList) = _forward_list_iteration_tuple(v, iteratorbegin(v))
Base.iterate(v::StdForwardList, state::StdForwardListIterator) = (state != iteratorend(v)) ? _forward_list_iteration_tuple(v, iterator_next(state)) : nothing

function Base.show(io::IO, ::MIME"text/plain", container::StdForwardList)
    print(io, "StdForwardList[")

    iterator = iterate(container)
    for i in 1:5
        if iterator === nothing
            break
        end
        item, state = iterator
        i > 1 && print(io, ", ")
        print(io, item)
        iterator = iterate(container, state)
    end

    if iterator !== nothing
        print(io, ", ...")
    end

    print(io, "]")
end