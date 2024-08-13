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
