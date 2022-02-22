# # Independent set problem

# ## Problem definition
# In graph theory, an [independent set](https://en.wikipedia.org/wiki/Independent_set_(graph_theory)) is a set of vertices in a graph, no two of which are adjacent.
# In the following, we are going to defined the independent set problem on the Petersen graph.

using GraphTensorNetworks, Graphs

graph = Graphs.smallgraph(:petersen)

# We can visualize this graph using the following function
rot15(a, b, i::Int) = cos(2i*π/5)*a + sin(2i*π/5)*b, cos(2i*π/5)*b - sin(2i*π/5)*a

locations = [[rot15(0.0, 1.0, i) for i=0:4]..., [rot15(0.0, 0.6, i) for i=0:4]...]

show_graph(graph; locs=locations)

# In order to display your plot with [`show_graph`](@ref), you need to call this function in
# * a [VSCode](https://github.com/julia-vscode/julia-vscode) editor,
# * a [Jupyter](https://github.com/JunoLab/Juno.jl) notebook,
# * or a [Pluto](https://github.com/fonsp/Pluto.jl) notebook,
#
# rather than a Julia REPL that does not have a graphical display.

# ## Tensor network representation
# Let ``G=(V,E)`` be the target graph that we want to solve.
# The tensor network representation map a vertex ``i\in V`` to a label ``s_i \in \{0, 1\}`` of dimension ``2`` in a tensor network, where we use ``0`` (``1``) to denote a vertex is absent (present) in the set.
# For each label ``s_i``, we defined a parametrized rank-one vertex tensor ``W(x_i)`` as
# ```math
# W(x_i) = \left(\begin{matrix}
#     1 \\
#     x_i
# \end{matrix}\right).
# ```
# We use subscripts to index tensor elements, e.g. ``W(x_i)_0=1`` is the first element associated with ``s_i=0`` and ``W(x_i)_1=x_i`` is the second element associated with ``s_i=1``.
# Similarly, on each edge ``(u, v)``, we define a matrix ``B`` indexed by ``s_u`` and ``s_v`` as
# ```math
# B = \left(\begin{matrix}
#     1  & 1\\
#     1 & 0
# \end{matrix}\right).
# ```

# We can use [`IndependentSet`](@ref) to construct a tensor network
# corresponding to the independent set problem on our target graph.
problem = IndependentSet(graph; optimizer=TreeSA());

# Key word argument `optimizer` specifies the contraction order optimizer of the tensor network.
# Here we use the local search based optimizer [`TreeSA`](@ref).
# The return value `problem` contains a field `code` that specifies the tensor network and its contraction order.
# The optimal contraction time and space complexity of an independent set problem is ``2^{{\rm tw}(G)}``,
# where ``{\rm tw(G)}`` is the [tree-width](https://en.wikipedia.org/wiki/Treewidth) of ``G``.
# One can check the time, space and read-write complexity with the following function.

timespacereadwrite_complexity(problem)

# The return values are `log2` of the the number of iterations, the number elements in the largest tensor during contraction and the number of tensor element read-write operations.
# For more information about how to improve the contraction order, please check the [Performance Tips](@ref).

# ## Solving properties

# ### Maximum independent set size ``\alpha(G)``
maximum_independent_set_size = solve(problem, SizeMax())[]

# Function [`solve`](@ref) takes two positional arguments, the problem instance and the wanted property.
# Here [`SizeMax`](@ref) means finding the solution with maximum set size.

# ### Counting properties
# ##### counting all independent sets
count_all_independent_sets = solve(problem, CountingAll())[]

# Here [`CountingAll`](@ref) means finding all possible solutions.

# ##### counting independent sets with sizes ``\alpha(G)`` and ``\alpha(G)-1``
count_max2_independent_sets = solve(problem, CountingMax(2))[]

# Here [`CountingMax`](@ref) means finding solutions with largest-2 sizes,
# the positional argument has default value `1`.

# ##### independence polynomial
# The graph polynomial for the independent set problem is known as the independence polynomial.
# ```math
# I(G, x) = \sum_{k=0}^{\alpha(G)} a_k x^k,
# ```
# where ``\alpha(G)`` is the maximum independent set size, 
# ``a_k`` is the number of independent sets of size ``k``.
# The total number of independent sets is thus equal to ``I(G, 1)``.
# There are 3 methods to compute a graph polynomial, `:finitefield`, `:fft` and `:polynomial`.
# These methods are introduced in the docstring of [`GraphPolynomial`](@ref).
independence_polynomial = solve(problem, GraphPolynomial(; method=:finitefield))[]

# ### Configuration properties
# ##### finding one maximum independent set (MIS)
# One can use [`SingleConfigMax`](@ref) to find one of the solution with largest set size, and it has two implementations.
# The unbounded (default) version uses [`ConfigSampler`](@ref) to sample one of the best solutions directly.
# The bounded version uses the binary gradient back-propagation (see our paper) to compute the gradients.
# It requires caching intermediate states, but is often faster (on CPU) because it can use [`TropicalGEMM`](https://github.com/TensorBFS/TropicalGEMM.jl) (see [Performance Tips](@ref)).
max_config = solve(problem, SingleConfigMax(; bounded=false))[]

# The return value contains a bit string, and one should read this bit string from left to right.
# Having value 1 at i-th bit means vertex ``i`` is in the maximum independent set.
# One can visualize this MIS with the following function.
show_graph(graph; locs=locations, vertex_colors=
    [iszero(max_config.c.data[i]) ? "white" : "red" for i=1:nv(graph)])

# ##### enumeration of all MISs
# One can use [`ConfigsMax`](@ref) to find all solutions with largest-K set sizes.
# It also has two implementations.
# The bounded (default) version is always prefered because it can significantly use the memory usage.
all_max_configs = solve(problem, ConfigsMax(1; bounded=true))[]

using Compose

m = length(all_max_configs.c)

imgs = ntuple(k->show_graph(graph;
                    locs=locations, scale=0.25,
                    vertex_colors=[iszero(all_max_configs.c[k][i]) ? "white" : "red"
                    for i=1:nv(graph)]), m);

Compose.set_default_graphic_size(18cm, 4cm)

Compose.compose(context(),
     ntuple(k->(context((k-1)/m, 0.0, 1.2/m, 1.0), imgs[k]), m)...)

# ##### enumeration of all IS configurations
# One can use [`ConfigsAll`](@ref) to enumerate all sets satisfying the problem constraint.
all_independent_sets = solve(problem, ConfigsAll())[]

# It is often difficult to store all configurations in a vector.
# A more clever way to store the data is using the [`TreeConfigEnumerator`](@ref) format.
all_independent_sets_tree = solve(problem, ConfigsAll(; tree_storage=true))[]

# The results encode the configurations in the sum-product-tree format. One can count and enumerate them explicitly by typing
length(all_independent_sets_tree)

# 

collect(all_independent_sets_tree)

# To save/read a set of configuration to disk, one can type the following
filename = tempname()

save_configs(filename, all_independent_sets; format=:binary)

loaded_sets = load_configs(filename; format=:binary, bitlength=10)

# !!! note
#     When loading data, one needs to provide the `bitlength` if the data is saved in binary format.
#     Because the bitstring length is not stored.

# !!! note
#     Check section [Maximal independent set problem](@ref) for examples of finding graph properties related to minimum sizes:
#     * [`SizeMin`](@ref) for enumerating minimum set size,
#     * [`CountingMin`](@ref) for enumerating minimum set size,
#     * [`SingleConfigMin`](@ref) for enumerating minimum set size,
#     * [`ConfigsMin`](@ref) for enumerating minimum set size,


# ## Weights and open vertices
# [`IndependentSet`](@ref) accepts weights as a key word argument.
# The following code computes the weighted MIS problem.
problem = IndependentSet(graph; weights=collect(1:10))

max_config_weighted = solve(problem, SingleConfigMax())[]

show_graph(graph; locs=locations, vertex_colors=
          [iszero(max_config_weighted.c.data[i]) ? "white" : "red" for i=1:nv(graph)])

# The following code computes the MIS tropical tensor (reference to be added) with open vertices 1, 2 and 3.
problem = IndependentSet(graph; openvertices=[1,2,3])

mis_tropical_tensor = solve(problem, SizeMax())

# The MIS tropical tensor shows the MIS size under different configuration of open vertices.
# It is useful in MIS tropical tensor analysis.
# One can compatify (reference to be added) this MIS-Tropical tensor by typing

mis_compactify!(mis_tropical_tensor)

# It will eliminate some entries having no contribution to the MIS size when embeding this local graph into a larger one.