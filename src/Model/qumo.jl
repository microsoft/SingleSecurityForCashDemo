#=
qumo.jl

Convert a (subset of) JuMP model to QUMO formulation.
The QUMO formulation is composed of a quadratic matric `Q`
and a linear vector `c` such that the objective function
is `0.5*x'Qx + c'x + constant`.

*NOTE*: Observe the 0.5 factor in the quadratic term.
=#

function convert_to_qumo(
    model::Model,
    objective::GenericQuadExpr{T, GenericVariableRef{T}}
    ) where T<:Real

    vars = all_variables(model)
    number_of_variables = length(vars)
    linear_terms = zeros(T, number_of_variables)

    binaries = vars |> Filter(is_binary) |> Map(x -> x.index.value) |> collect

    for (var, v) in objective.aff.terms
        linear_terms[var.index.value] += v
    end

    quadratic = []
    for (pair, v) in objective.terms
        i = pair.a
        j = pair.b
        if i == j && is_binary(i)
            linear_terms[i.index.value] += v
        else
            #=
            Observe that if i==j and the variable with index i
            is not binary, then the term is continuous. We need
            to add the diagonal term and we need to add it twice
            because the definition we use for the QUMO problem
            is 0.5*x'Qx + c'x + constant, observe the 0.5 factor.
            =#
            push!(quadratic, (i.index.value, j.index.value, v))
            push!(quadratic, (j.index.value, i.index.value, v))
        end
    end

    is, js, vs = unzip(quadratic)
    return (;
        Quadratic = sparse(is, js, vs, number_of_variables, number_of_variables),
        Linear = linear_terms,
        Binaries = binaries,
        Constant = objective.aff.constant,
        Names = map(x -> JuMP.name(x), vars)
    )
end

function convert_to_qumo(model::Model, penalty::T) where T<:Real
    @assert penalty > T(0) "Penalty ($penalty) must always be positive"

    model = copy(model)
    boxify_constraints!(model)
    convert_to_equations!(model)
    convert_constraints_to_penalties!(model, penalty)

    objective = objective_function(model)
    return convert_to_qumo(model, objective)
end
