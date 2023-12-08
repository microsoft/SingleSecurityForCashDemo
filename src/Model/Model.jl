#=
Model.jl

Functionality for manipulating JuMP models
and converting them to QUMO.

=#

module Models

using JuMP
using MLStyle
using OrderedCollections
using SparseArrays
using Transducers
using Unzip

include("bounds.jl")
include("rewriters.jl")
include("qumo.jl")

end # module