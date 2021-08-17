using Polynomials
using OMEinsum: NestedEinsum, getixs, getiy
using FFTW
using LightGraphs

export contractx, contractf, graph_polynomial, optimize_code
export Independence, MaximalIndependence, Matching, Coloring
const EinTypes = Union{EinCode,NestedEinsum}

abstract type GraphProblem end
"""
    Independence{CT<:EinTypes} <: GraphProblem
    Independence(graph; kwargs...)

Independent set problem. For `kwargs`, check `optimize_code` API.
"""
struct Independence{CT<:EinTypes} <: GraphProblem
    code::CT
end

"""
    Independence{CT<:EinTypes} <: GraphProblem
    Independence(graph; kwargs...)

Independent set problem. For `kwargs`, check `optimize_code` API.
"""
struct MaximalIndependence{CT<:EinTypes} <: GraphProblem
    code::CT
end

"""
    Matching{CT<:EinTypes} <: GraphProblem
    Matching(graph; kwargs...)

Vertex matching problem. For `kwargs`, check `optimize_code` API.
"""
struct Matching{CT<:EinTypes} <: GraphProblem
    code::CT
end

"""
    Coloring{K,CT<:EinTypes} <: GraphProblem
    Coloring{K}(graph; kwargs...)

K-Coloring problem. For `kwargs`, check `optimize_code` API.
"""
struct Coloring{K,CT<:EinTypes} <: GraphProblem
    code::CT
end
Coloring{K}(code::ET) where {K,ET<:EinTypes} = Coloring{K,ET}(code)

"""
    labels(code)

Return a vector of unique labels in an Einsum token.
"""
function labels(code::EinTypes)
    res = []
    for ix in OMEinsum.getixs(OMEinsum.flatten(code))
        for l in ix
            if l ∉ res
                push!(res, l)
            end
        end
    end
    return res
end

"""
    graph_polynomial(problem, method; usecuda=false, kwargs...)

Computing the graph polynomial for specific problem.

* `problem` can be one of the following instances,
    * `Independence` for the independence polynomial,
    * `MaximalIndependence` for the maximal independence polynomial,
    * `Matching` for the matching polynomial,

* `method` can be one of the following inputs,
    * `Val(:finitefield)`, compute exactly with the finite field method.
        It consumes additional kwargs [`max_iter`, `maxorder`], where `maxorder` is maximum order of polynomial
        and `max_iter` is the maximum number of primes numbers to use in the finitefield algebra.
        `max_iter` can be determined automatically in most cases.
    * `Val(:polynomial)`, compute directly with `Polynomial` number type,
    * `Val(:fft)`, compute with the fast fourier transformation approach, fast but needs to tune the hyperparameter `r`.
        It Consumes additional kwargs [`maxorder`, `r`]. The larger `r` is,
        the more accurate the factors of high order terms, and the less accurate the factors of low order terms.
    * `Val(:fitting)`, compute with the polynomial fitting approach, fast but inaccurate for large graphs.
"""
function graph_polynomial end

function graph_polynomial(gp::GraphProblem, ::Val{:fft}; usecuda=false, 
        maxorder=graph_polynomial_maxorder(gp; usecuda=usecuda), r=1.0)
	ω = exp(-2im*π/(maxorder+1))
	xs = r .* collect(ω .^ (0:maxorder))
	ys = [asscalar(contractx(gp, x; usecuda=usecuda)) for x in xs]
	Polynomial(ifft(ys) ./ (r .^ (0:maxorder)))
end

function graph_polynomial(gp::GraphProblem, ::Val{:fitting}; usecuda=false,
        maxorder = graph_polynomial_maxorder(gp; usecuda=usecuda))
	xs = (0:maxorder)
	ys = [asscalar(contractx(gp, x; usecuda=usecuda)) for x in xs]
	fit(xs, ys, maxorder)
end

function graph_polynomial(gp::GraphProblem, ::Val{:polynomial}; usecuda=false)
    @assert !usecuda "Polynomial type can not be computed on GPU!"
    contractx(gp::GraphProblem, Polynomial([0, 1.0]))
end

function _polynomial_single(gp::GraphProblem, ::Type{T}; usecuda, maxorder) where T
	xs = 0:maxorder
	ys = [asscalar(contractx(gp, T(x); usecuda=usecuda)) for x in xs]
	A = zeros(T, maxorder+1, maxorder+1)
	for j=1:maxorder+1, i=1:maxorder+1
		A[j,i] = T(xs[j])^(i-1)
	end
	A \ T.(ys)
end

function graph_polynomial(gp::GraphProblem, ::Val{:finitefield}; usecuda=false,
        maxorder=graph_polynomial_maxorder(gp; usecuda=usecuda), max_iter=100)
    TI = Int32  # Int 32 is faster
    N = typemax(TI)
    YS = []
    local res
    for k = 1:max_iter
	    N = prevprime(N-TI(1))
        T = Mods.Mod{N,TI}
        rk = _polynomial_single(gp, T; usecuda=usecuda, maxorder=maxorder)
        push!(YS, rk)
        if maxorder==1
            return Polynomial(Mods.value.(YS[1]))
        elseif k != 1
            ra = improved_counting(YS[1:end-1])
            res = improved_counting(YS)
            ra == res && return Polynomial(res)
        end
    end
    @warn "result is potentially inconsistent."
    return Polynomial(res)
end
function improved_counting(sequences)
    map(yi->Mods.CRT(yi...), zip(sequences...))
end

"""
    optimize_code(code; optmethod=:kahypar, sc_target=17, max_group_size=40, nrepeat=10, imbalances=0.0:0.001:0.8)

Optimize the contraction order.

* `optmethod` can be one of
    * `:kahypar`, the kahypar + greedy approach, takes kwargs [`sc_target`, `max_group_size`, `imbalances`].
    Check `optimize_kahypar` method in package `OMEinsumContractionOrders`.
    * `:auto`, also the kahypar + greedy approach, but determines `sc_target` automatically. It is slower!
    * `:greedy`, the greedy approach. Check in `optimize_greedy` in package `OMEinsum`.
    * `:raw`, do nothing and return the raw EinCode.
"""
function optimize_code(code::EinTypes; optmethod=:kahypar, sc_target=17, max_group_size=40, nrepeat=10, imbalances=0.0:0.001:0.8)
    size_dict = Dict([s=>2 for s in labels(code)])
    optcode = if optmethod == :kahypar
        optimize_kahypar(code, size_dict; sc_target=sc_target, max_group_size=max_group_size, imbalances=imbalances)
    elseif optmethod == :greedy
        optimize_greedy(code, size_dict; nrepeat=nrepeat)
    elseif optmethod == :auto
        optimize_kahypar_auto(code, size_dict; max_group_size=max_group_size, effort=500)
    elseif optmethod == :raw
        code
    else
        ArgumentError("optimizer `$optmethod` not defined.")
    end
    println("time/space complexity is $(OMEinsum.timespace_complexity(optcode, size_dict))")
    return optcode
end

contractx(gp::GraphProblem, x; usecuda=false) = contractf(_->x, gp; usecuda=usecuda)
function contractf(f, gp::GraphProblem; usecuda=false)
    xs = generate_tensors(f, gp)
    if usecuda
        xs = CuArray.(xs)
    end
    dynamic_einsum(gp.code, xs)
end

############### Problem specific implementations ################
### independent set ###
function Independence(g::SimpleGraph; kwargs...)
    rawcode = EinCode(([(i,) for i in LightGraphs.vertices(g)]..., # labels for vertex tensors
                    [minmax(e.src,e.dst) for e in LightGraphs.edges(g)]...), ())  # labels for edge tensors
    Independence(optimize_code(rawcode; kwargs...))
end

function generate_tensors(fx, gp::Independence)
    ixs = getixs(flatten(gp.code))
    T = typeof(fx(ixs[1][1]))
    return map(ixs) do ix
        # if the tensor rank is 1, create a vertex tensor.
        # otherwise the tensor rank must be 2, create a bond tensor.
        length(ix)==1 ? misv(fx(ix[1])) : misb(T)
    end
end
misb(::Type{T}) where T = [one(T) one(T); one(T) zero(T)]
misv(val::T) where T = [one(T), val]

graph_polynomial_maxorder(gp::Independence; usecuda) = Int(sum(contractx(gp, TropicalF64(1.0); usecuda=usecuda)).n)

### coloring ###
Coloring(g::SimpleGraph; kwargs...) = Coloring(Independence(g; kwargs...).code)
function generate_tensors(fx, c::Coloring{K}) where K
    ixs = getixs(flatten(code))
    T = eltype(fx(ixs[1][1]))
    return map(ixs) do ix
        # if the tensor rank is 1, create a vertex tensor.
        # otherwise the tensor rank must be 2, create a bond tensor.
        length(ix)==1 ? coloringv(f(ix[1])) : coloringb(T, K)
    end
end

# coloring bond tensor
function coloringb(::Type{T}, k::Int) where T
    x = ones(T, k, k)
    for i=1:k
        x[i,i] = zero(T)
    end
    return x
end
# coloring vertex tensor
coloringv(vals::Vector{T}) where T = vals

### matching ###
function Matching(g::SimpleGraph; kwargs...)
    rawcode = EinCode(([(minmax(e.src,e.dst),) for e in LightGraphs.edges(g)]..., # labels for edge tensors
                    [([minmax(i,j) for j in neighbors(g, i)]...,) for i in LightGraphs.vertices(g)]...,), ())       # labels for vertex tensors
    Matching(optimize_code(rawcode; kwargs...))
end

function generate_tensors(fx, m::Matching)
    ixs = OMEinsum.getixs(flatten(m.code))
    T = typeof(fx(ixs[1][1]))
    n = length(unique(vcat(collect.(ixs)...)))  # number of vertices
    tensors = []
    for i=1:length(ixs)
        if i<=n
            @assert length(ixs[i]) == 1
            t = T[one(T), fx(ixs[i][1])] # fx is defined on edges.
        else
            t = match_tensor(T, length(ixs[i]))
        end
        push!(tensors, t)
    end
    return tensors
end
function match_tensor(::Type{T}, n::Int) where T
    t = zeros(T, fill(2, n)...)
    for ci in CartesianIndices(t)
        if sum(ci.I .- 1) <= 1
            t[ci] = one(T)
        end
    end
    return t
end

graph_polynomial_maxorder(m::Matching; usecuda) = Int(sum(contractx(m, TropicalF64(1.0); usecuda=usecuda)).n)

### maximal independent set ###
function MaximalIndependence(g::SimpleGraph; kwargs...)
    rawcode = EinCode(([(LightGraphs.neighbors(g, v)..., v) for v in LightGraphs.vertices(g)]...,), ())
    MaximalIndependence(optimize_code(rawcode; kwargs...))
end

function generate_tensors(fx, mi::MaximalIndependence)
    ixs = OMEinsum.getixs(flatten(mi.code))
    T = eltype(fx(ixs[1][end]))
	return map(ixs) do ix
        neighbortensor(fx(ix[end]), length(ix))
    end
end
function neighbortensor(x::T, d::Int) where T
    t = zeros(T, fill(2, d)...)
    for i = 2:1<<(d-1)
        t[i] = one(T)
    end
    t[1<<(d-1)+1] = x
    return t
end

graph_polynomial_maxorder(mi::MaximalIndependence; usecuda) = Int(sum(contractx(mi, TropicalF64(1.0); usecuda=usecuda)).n)