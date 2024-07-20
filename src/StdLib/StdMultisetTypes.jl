using .StdLib: StdMultiset, StdUnorderedMultiset

for StdMultisetType in (StdMultiset, StdUnorderedMultiset)
    Base.size(v::StdMultisetType) = (Int(cppsize(v)),)
    Base.length(v::StdMultisetType) = Int(cppsize(v))
    Base.isempty(v::StdMultisetType) = multiset_isempty(v)
    Base.empty!(v::StdMultisetType) = (multiset_empty!(v); v)
    Base.push!(v::StdMultisetType, x) = (multiset_insert!(v, x); v)
    Base.in(x, v::StdMultisetType) = multiset_in(v, x)
    Base.delete!(v::StdMultisetType, x) = (multiset_delete!(v, x); v)
    Base.count(x, v::StdMultisetType) = multiset_count(v, x)
end

Base.:(==)(a::StdMultisetIterator, b::StdMultisetIterator) = iterator_is_equal(a, b)
_multiset_iteration_tuple(v::StdMultiset, state::StdMultisetIterator) = (state == iteratorend(v)) ? nothing : (iterator_value(state), state)
Base.iterate(v::StdMultiset) = _multiset_iteration_tuple(v, iteratorbegin(v))
Base.iterate(v::StdMultiset, state::StdMultisetIterator) = (state != iteratorend(v)) ? _multiset_iteration_tuple(v, iterator_next(state)) : nothing

Base.:(==)(a::StdUnorderedMultisetIterator, b::StdUnorderedMultisetIterator) = iterator_is_equal(a, b)
_unordered_multiset_iteration_tuple(v::StdUnorderedMultiset, state::StdUnorderedMultisetIterator) = (state == iteratorend(v)) ? nothing : (iterator_value(state), state)
Base.iterate(v::StdUnorderedMultiset) = _unordered_multiset_iteration_tuple(v, iteratorbegin(v))
Base.iterate(v::StdUnorderedMultiset, state::StdUnorderedMultisetIterator) = (state != iteratorend(v)) ? _unordered_multiset_iteration_tuple(v, iterator_next(state)) : nothing