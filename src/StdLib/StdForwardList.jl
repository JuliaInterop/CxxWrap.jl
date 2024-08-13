using .StdLib: StdForwardList

Base.isempty(v::StdForwardList) = flist_isempty(v)
Base.first(v::StdForwardList) = flist_front(v)
Base.empty!(v::StdForwardList) = (flist_empty!(v); v)
Base.pushfirst!(v::StdForwardList, x) = (flist_push_front!(v, x); v)
Base.popfirst!(v::StdForwardList) = (flist_pop_front!(v); v)

function Base.show(io::IO, ::MIME"text/plain", container::StdForwardList{T}) where {T}
    print(io, "StdForwardList{", T, "}")

    iterator = iterate(container)
    if iterator === nothing
        print(io, "()")
        return
    end

    print(io, ":")
    count = 0
    while iterator !== nothing && count < 10
        item, state = iterator
        print(io, "\n  ", item)
        iterator = iterate(container, state)
        count += 1
    end

    if iterator !== nothing
        print(io, "\n  ⋮")
    end
end