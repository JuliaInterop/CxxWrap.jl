using .StdLib: StdForwardList

Base.isempty(v::StdForwardList) = flist_isempty(v)
Base.first(v::StdForwardList) = flist_front(v)
Base.empty!(v::StdForwardList) = (flist_empty!(v); v)
Base.pushfirst!(v::StdForwardList, x) = (flist_push_front!(v, x); v)
Base.popfirst!(v::StdForwardList) = (flist_pop_front!(v); v)