using .StdLib: StdSet, StdUnorderedSet

for StdSetType in (StdSet, StdUnorderedSet)
    Base.size(v::StdSetType) = (Int(cppsize(v)),)
    Base.length(v::StdSetType) = Int(cppsize(v))
    Base.isempty(v::StdSetType) = set_isempty(v)
    Base.empty!(v::StdSetType) = (set_empty!(v); v)
    Base.push!(v::StdSetType, x) = (set_insert!(v, x); v)
    Base.in(x, v::StdSetType) = set_in(v, x)
    Base.delete!(v::StdSetType, x) = (set_delete!(v, x); v)
end

Base.:(==)(a::StdSetIterator, b::StdSetIterator) = iterator_is_equal(a, b)
_set_iteration_tuple(v::StdSet, state::StdSetIterator) = (state == iteratorend(v)) ? nothing : (iterator_value(state), state)
Base.iterate(v::StdSet) = _set_iteration_tuple(v, iteratorbegin(v))
Base.iterate(v::StdSet, state::StdSetIterator) = (state != iteratorend(v)) ? _set_iteration_tuple(v, iterator_next(state)) : nothing