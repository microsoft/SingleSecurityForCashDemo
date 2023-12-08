#=
mathopt.jl

Modeling of the transaction settlement problem as a mathematical optimization problem,
using JuMP.

=#

abstract type SolverBackend end

struct HiGHSBackend <: SolverBackend end
struct GurobiBackend <: SolverBackend end

function create_model(market::Market{T}) where T <: Real
    ntransactions = number_of_transactions(market)
    nparticipants = number_of_participants(market)

    model = Model()
    @variable(model, x[1:ntransactions], Bin)
    @constraint(model, market.setup.security .+ market.transactions.security * x .>= T(0))
    @constraint(model, market.setup.currency .+ market.transactions.currency * x .+
                       market.setup.conversion .* (market.setup.security .+ market.transactions.security * x) .>= T(0))
    @objective(model, Max, sum(x))

    # assign names to constraints
    constraints = all_constraints(model; include_variable_in_set_constraints=false)
    @assert length(constraints) == 2 * nparticipants
    for i in 1:nparticipants
        set_name(constraints[i], "security[$i]")
        set_name(constraints[i + nparticipants], "currency[$i]")
    end

    return model
end

solve(::SolverBackend, model::GenericModel{T}; kwargs...) where T<:Real = error("Solver not implemented")

function solve(::HiGHSBackend, model::GenericModel{T}; silent::Bool=false) where T<:Real
    set_optimizer(model, HiGHS.Optimizer)

    if silent
        set_silent(model)
        set_optimizer_attribute(model, "output_flag", false)
    end

    optimize!(model)
    @assert termination_status(model) == OPTIMAL
    solution_summary(model)
    x = all_variables(model)

    if all(is_binary, all_variables(model))
        solution = value.(x) |> Map(x -> Int32(x)) |> (x -> findall(x .== 1))

        return solution
    else
        solution = all_variables(model) |> Filter(is_binary) |> Map(x -> Int32(value(x))) |> (x -> findall(x .== 1))
        extras = all_variables(model) |> Map(x -> JuMP.name(x) => value(x)) |> collect |> Dict

        return solution, extras
    end

end

solve(model::GenericModel{T}; backend::SolverBackend=HiGHSBackend(), kwargs...) where T<:Real = solve(backend, model; kwargs...)
