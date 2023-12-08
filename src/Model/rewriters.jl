#=
rewriters.jl

Rewrite constraints in JuMP models
=#

"""
    boxify_constraints(model::Model)

Enumerate all constraints of a model and compute lower and upper
bounds for them. Then, rewrite the constraints to use the bounds.

This assumes that the bounds can be estimated.
"""

function _boxify_constraint!(
    model::Model,
    constraint_ref::ConstraintRef,
    constraint::ScalarConstraint{GenericAffExpr{T, VariableRef}, TSet}
    ) where {T<:Real, TSet<:MOI.AbstractScalarSet}

    envelop = merge(infer_limits(constraint.func), constraint.set)
    constraint_name = name(constraint_ref)

    @match envelop begin
        Infeasible() => begin
            # TODO: annotate the model as infeasible and return
            error("Model is infeasible at constraint: $constraint")
        end
        Constant(value) => begin
            #=
            Below is the straight-forward transformation.
            However, there is probably a better way:
            Observe that at this point we have figured out that a
            linear expression is constant. Hence, we can solve for
            one of the variables and substitude to the rest of the model.
            Hopefully, standard solvers will pick that up, but we do not
            currently perform this useful simplification.
            =#

            f = constraint.func
            new_f = GenericAffExpr(T(0), f.terms)
            new_interval = MOI.EqualTo(value - f.constant)
            new_constraint = ScalarConstraint(new_f, new_interval)
            delete(model, constraint_ref)
            add_constraint(model, new_constraint, constraint_name)
        end
        Box(_, _) => begin
            f = constraint.func
            box = envelop
            box = box - f.constant
            range = box.upper - box.lower
            @assert range > T(0)

            # Adjust the terms of the function so that the range
            # of the new function has a length of 1, and that the
            # function does not have a constant term.
            # This is needed to guarantee that the slack variable
            # takes value in the range [0,1].

            terms = f.terms |>
                    Map(kv -> (kv.first, kv.second/range)) |>
                    OrderedCollections.OrderedDict

            new_f = GenericAffExpr(T(0), terms)
            box = box / range

            new_interval = MOI.Interval(box.lower, box.upper)
            new_constraint = ScalarConstraint(new_f, new_interval)

            delete(model, constraint_ref)
            add_constraint(model, new_constraint, constraint_name)
        end
    end
end

function boxify_constraints!(model::Model)
    for constraint_ref in all_constraints(model; include_variable_in_set_constraints=false)
        constraint = constraint_object(constraint_ref)
        _boxify_constraint!(model, constraint_ref, constraint)
    end

    return model
end

function boxify_constraints(model::Model)
    model = copy(model)
    boxify_constraints!(model)
    return model
end

"""
    convert_to_equations(model::Model)

Convert all constraints of a model to equations.
"""

function _convert_to_equation!(
    model::Model,
    index::Integer,
    constraint_ref::ConstraintRef,
    constraint::ScalarConstraint{GenericAffExpr{T, VariableRef}, MOI.Interval{T}}
    ) where T<:Real

    @debug "Converting constraint" index constraint_ref
    @assert constraint.set.upper - constraint.set.lower ≈ 1

    constraint_name = name(constraint_ref)

    #=
    We need to transform the following constraint: l≤f≤u,
    where l and u are the computed bounds.
    Due to previous transformations, we assume that u-l=1.
    With the introduction of the slacks we get: f-δₗ=l and f+dᵤ=u.
    By subtracting, we find that δₗ + δᵤ = 1.
    Hence, one of the two equalities is now redundant.
    We will keep the upper one.
    =#

    delta_upper_info = VariableInfo(true, T(0.0), true, T(1.0), false, T(0.0), false, T(0.0), false, false)

    # TODO: Implement and provide a custom error function below
    delta_upper_var = build_variable(error, delta_upper_info)
    delta_upper = add_variable(model, delta_upper_var, "δ[$index]")

    f = constraint.func
    terms = f.terms |> Map(kv -> (kv.first, T(kv.second))) |> OrderedCollections.OrderedDict
    upper_terms = merge(terms, Dict(delta_upper => T(1.0)))
    upper_f = GenericAffExpr(f.constant, upper_terms)

    upper_constraint = ScalarConstraint(upper_f, MOI.EqualTo(constraint.set.upper))

    delete(model, constraint_ref)
    add_constraint(model, upper_constraint, constraint_name)
end

function _convert_to_equation!(
    ::Model,
    ::Integer,
    ::ConstraintRef,
    ::ScalarConstraint{GenericAffExpr{T, VariableRef}, MOI.EqualTo{T}}
    ) where T<:Real

    # Nothing to do
end

_convert_to_equation!(model::Model, constraint_ref::ConstraintRef) =
    _convert_to_equation!(model, constraint_ref.index.value, constraint_ref, constraint_object(constraint_ref))

function convert_to_equations!(model::Model)
    for constraint_ref in all_constraints(model; include_variable_in_set_constraints=false)
        _convert_to_equation!(model, constraint_ref)
    end
end

function convert_to_equations(model::Model)
    model = copy(model)
    convert_to_equations!(model)
    return model
end

"""
    convert_constraints_to_penalties(model::Model, penalty::T)

Receives a model with equality constraints and converts them to
penalty terms in the objective function.
Assuming a constraint of the form `f(x) = c`, this contributes to
an additive penalty term of the form `penalty * (f(x) - c)^2`.

"""

function _convert_constraint_to_penalty_term(constraint::ScalarConstraint{GenericAffExpr{T, VariableRef}, MOI.EqualTo{T}}) where T<:Real
    x = constraint.func - constraint.set.value
    return x * x
end

function convert_constraints_to_penalties!(model::Model, penalty::T) where T<:Real
    if penalty < zero(T)
        error("Penalty must be non-negative")
    end
    if penalty ≈ zero(T)
        @warn "The penalty term is zero ($penalty); all constraints will be removed"

        for constraint_ref in all_constraints(model; include_variable_in_set_constraints=false)
            delete(model, constraint_ref)
        end

        return
    end

    if objective_sense(model) == MAX_SENSE
        # When maximizing, the penalty terms are subtracted
        penalty = -penalty
    end

    objective = mapreduce(
        cref -> penalty * _convert_constraint_to_penalty_term(constraint_object(cref)),
        +,
        all_constraints(model; include_variable_in_set_constraints=false)
        ;
        init = objective_function(model)
    )
    set_objective_function(model, objective)

    for constraint_ref in all_constraints(model; include_variable_in_set_constraints=false)
        delete(model, constraint_ref)
    end
end

function convert_constraints_to_penalties(model::Model, penalty::T) where T<:Real
    model = copy(model)
    convert_constraints_to_penalties!(model, penalty)
    return model
end
