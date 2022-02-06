export best_solutions, best2_solutions, solutions, all_solutions
export bestk_solutions

"""
    best_solutions(problem; all=false, usecuda=false)
    
Find optimal solutions with bounding.

* When `all` is true, the program will use set for enumerate all possible solutions, otherwise, it will return one solution for each size.
* `usecuda` can not be true if you want to use set to enumerate all possible solutions.
"""
function best_solutions(gp::GraphProblem; all=false, usecuda=false)
    if all && usecuda
        throw(ArgumentError("ConfigEnumerator can not be computed on GPU!"))
    end
    syms = symbols(gp)
    T = (all ? set_type : sampler_type)(CountingTropical{Int64}, length(syms), bondsize(gp))
    vertex_index = Dict([s=>i for (i, s) in enumerate(syms)])
    xst = generate_tensors(l->TropicalF64(1.0), gp)
    ymask = trues(fill(2, length(getiyv(gp.code)))...)
    if usecuda
        xst = CuArray.(xst)
        ymask = CuArray(ymask)
    end
    if all
        xs = generate_tensors(l->_onehotv(T, vertex_index[l], 1, get_weight(gp, vertex_index[l])), gp)
        return bounding_contract(AllConfigs{1}(), gp.code, xst, ymask, xs)
    else
        @assert ndims(ymask) == 0
        t, res = solution_ad(gp.code, xst, ymask)
        N = length(vertex_index)
        return fill(CountingTropical(asscalar(t).n, ConfigSampler(StaticBitVector(map(l->res[l], 1:N)))))
    end
end

"""
    solutions(problem, basetype; all, usecuda=false)
    
General routine to find solutions without bounding,

* `basetype` can be a type with counting field,
    * `CountingTropical{Float64,Float64}` for finding optimal solutions,
    * `Polynomial{Float64, :x}` for enumerating all solutions,
    * `Max2Poly{Float64,Float64}` for optimal and suboptimal solutions.
* When `all` is true, the program will use set for enumerate all possible solutions, otherwise, it will return one solution for each size.
* `usecuda` can not be true if you want to use set to enumerate all possible solutions.
"""
function solutions(gp::GraphProblem, ::Type{BT}; all, usecuda=false) where BT
    if all && usecuda
        throw(ArgumentError("ConfigEnumerator can not be computed on GPU!"))
    end
    return contractf(fx_solutions(gp, BT, all), gp; usecuda=usecuda)
end

"""
    best2_solutions(problem; all=true, usecuda=false)

Finding optimal and suboptimal solutions.
"""
best2_solutions(gp::GraphProblem; all=true, usecuda=false) = solutions(gp, Max2Poly{Float64,Float64}; all=all, usecuda=usecuda)

function bestk_solutions(gp::GraphProblem, k::Int)
    syms = symbols(gp)
    vertex_index = Dict([s=>i for (i, s) in enumerate(syms)])
    xst = generate_tensors(l->TropicalF64(1.0), gp)
    ymask = trues(fill(2, length(getiyv(gp.code)))...)
    T = set_type(TruncatedPoly{k,Float64,Float64}, length(syms), bondsize(gp))
    xs = generate_tensors(l->_onehotv(T, vertex_index[l], 1, get_weight(gp, vertex_index[l])), gp)
    return bounding_contract(AllConfigs{k}(), gp.code, xst, ymask, xs)
end

"""
    all_solutions(problem)

Finding all solutions.
e.g. when the problem is `MaximalIndependence`, it computes all maximal independent sets, or the maximal cliques of it complement.
"""
all_solutions(gp::GraphProblem) = solutions(gp, Polynomial{Float64,:x}, all=true, usecuda=false)

# return a mapping from label to variable `x`
for GP in [:Independence, :Matching, :MaximalIndependence, :MaxCut, :PaintShop]
    @eval function fx_solutions(gp::$GP, ::Type{BT}, all::Bool) where BT
        syms = symbols(gp)
        T = (all ? set_type : sampler_type)(BT, length(syms), bondsize(gp))
        vertex_index = Dict([s=>i for (i, s) in enumerate(syms)])
        return l->_onehotv(T, vertex_index[l], 1, get_weight(gp, vertex_index[l]))
    end
end
function fx_solutions(gp::Coloring{K}, ::Type{BT}, all::Bool) where {K,BT}
    syms = symbols(gp)
    T = (all ? set_type : sampler_type)(BT, length(syms), bondsize(gp))
    vertex_index = Dict([s=>i for (i, s) in enumerate(syms)])
    return function (l)
        map(1:K) do k
            _onehotv(T, vertex_index[l], k, get_weight(gp, vertex_index[l]))
        end
    end
end
function _onehotv(::Type{Polynomial{BS,X}}, x, v, w) where {BS,X}
    @assert isone(w)
    Polynomial{BS,X}([zero(BS), onehotv(BS, x, v)])
end
function _onehotv(::Type{TruncatedPoly{K,BS,OS}}, x, v, w) where {K,BS,OS}
    @assert isone(w)
    TruncatedPoly{K,BS,OS}(ntuple(i->i<K ? zero(BS) : onehotv(BS, x, v), K),one(OS))
end
function _onehotv(::Type{CountingTropical{TV,BS}}, x, v, w) where {TV,BS}
    CountingTropical{TV,BS}(TV(w), onehotv(BS, x, v))
end

for GP in [:Independence, :Matching, :MaximalIndependence, :Coloring]
    @eval symbols(gp::$GP) = labels(gp.code)
end
symbols(gp::MaxCut) = getixsv(gp.code)
symbols(gp::PaintShop) = getixsv(gp.code)
