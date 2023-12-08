#=
bounds.jl

Inference of bounds of variables and expressions

=#

#=
    Envelop{T}

A type for representing the bounds of a variable or expression.

Notice: The @data macro does not allow documenation strings.
=#

@data Envelop{T} begin
    Infeasible()
    Constant(value::T)
    Box(lower::T, upper::T)
end

#
# Helper methods for manipulating envelopes with arithmetic operators
#

function Base.:+(envelop::Envelop{T}, v::T)::Envelop{T} where T
    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => return Constant(value + v)
        Box(lower, upper) => return Box(lower + v, upper + v)
    end
end
function Base.:-(envelop::Envelop{T}, v::T)::Envelop{T} where T
    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => return Constant(value - v)
        Box(lower, upper) => return Box(lower - v, upper - v)
    end
end
function Base.:*(envelop::Envelop{T}, v::T)::Envelop{T} where T
    zt = zero(T)
    if v ≈ zt
        return Constant(zt)
    end

    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => return Constant(value * v)
        Box(lower, upper) => begin
            if v > zt
                return Box(lower * v, upper * v)
            else
                return Box(upper * v, lower * v)
            end
        end
    end
end
function Base.:/(envelop::Envelop{T}, v::T)::Envelop{T} where T
    zt = zero(T)
    @assert !(v ≈ zt) "Division by zero when adjusting $envelop by $v"

    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => return Constant(value / v)
        Box(lower, upper) => begin
            if v > zt
                return Box(lower / v, upper / v)
            else
                return Box(upper / v, lower / v)
            end
        end
    end
end

#
# Estimate limits of expressions
#

"""
    infer_limits(expression::GenericAffExpr{T, GenericVariableRef{T}})::Envelop{T}

Estimate upper and lower bounds of a simple linear expression.
"""
function infer_limits(
    expression::GenericAffExpr{T, GenericVariableRef{T}}
    )::Envelop{T} where T

    expression_minimum = expression.constant
    expression_maximum = expression.constant

    for term in expression.terms
        var = term.first
        coef = term.second

        if is_fixed(var)
            value = fix_value(var)
            expression_minimum += coef * value
            expression_maximum += coef * value
        elseif is_binary(var)
            if coef > zero(T)
                expression_maximum += coef
            else
                expression_minimum += coef
            end
        elseif has_lower_bound(var) && has_upper_bound(var)
            lower = lower_bound(var)
            upper = upper_bound(var)

            if coef > zero(T)
                expression_minimum += coef * lower
                expression_maximum += coef * upper
            else
                expression_minimum += coef * upper
                expression_maximum += coef * lower
            end
        else
            raise_error("Cannot infer limits for expression $expression")
        end
    end

    return Box(expression_minimum, expression_maximum)
end

# Observe that since Base.merge is defined elsewhere,
# we cannot introduce docstrings here.

#=
    merge(envelop::Envelop{T}, lower::MOI.GreaterThan{T})::Envelop{T}

Merge an envelop with a lower bound constraint. Assuming an
expression `expr >= lower` and that we have the `envelop`
of the `expr`, then we can refine the envelop.
=#
function Base.merge(
    envelop::Envelop{T},
    lower::MOI.GreaterThan{T}
    )::Envelop{T} where T

    lower = lower.lower

    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => begin
            if value >= lower
                return envelop
            else
                return Infeasible()
            end
        end
        Box(envelop_lower, envelop_upper) => begin
            if envelop_lower > lower
                return envelop
            elseif envelop_upper < lower
                return Infeasible()
            else
                return Box(lower, envelop_upper)
            end
        end
    end
end

#=
    merge(envelop::Envelop{T}, equal::MOI.EqualTo{T})::Envelop{T}

Merge an envelop with a lower bound constraint. Assuming an
expression `expr == lower` and that we have the `envelop`
of the `expr`, then we can refine the envelop.
=#
function Base.merge(
    envelop::Envelop{T},
    equal::MOI.EqualTo{T}
    )::Envelop{T} where T

    c = equal.value

    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => begin
            if value ≈ c
                return envelop
            else
                return Infeasible()
            end
        end
        Box(envelop_lower, envelop_upper) => begin
            if envelop_lower <= c <= envelop_upper
                return Constant(c)
            else
                return Infeasible()
            end
        end
    end
end

#=
    merge(envelop::Envelop{T}, upper::MOI.LessThan{T})::Envelop{T}

Merge an envelop with an upper bound constraint. Assuming an
expression `expr <= upper` and that we have the `envelop`
of the `expr`, then we can refine the envelop.
=#
function Base.merge(
    envelop::Envelop{T},
    upper::MOI.LessThan{T}
    )::Envelop{T} where T

    upper = upper.upper

    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => begin
            if value <= lower
                return envelop
            else
                return Infeasible()
            end
        end
        Box(envelop_lower, envelop_upper) => begin
            if envelop_upper <= upper
                return envelop
            elseif upper < envelop_lower
                return Infeasible()
            else
                return Box(envelop_lower, upper)
            end
        end
    end
end

#=
    merge(envelop::Envelop{T}, interval::MOI.Interval{T})::Envelop{T}

Merge an envelop with an interval constraint. Assuming an
expression `lower <= expr <= upper` and that we have the `envelop`
of the `expr`, then we can refine the envelop.
=#
function Base.merge(
    envelop::Envelop{T},
    interval::MOI.Interval{T}
    )::Envelop{T} where T

    lower = interval.lower
    upper = interval.upper

    # This assertion is necessary because JuMP does not check
    # for valid intervals.
    @assert lower <= upper

    @match envelop begin
        Infeasible() => return envelop
        Constant(value) => begin
            if lower <= value <= upper
                return envelop
            else
                return Infeasible()
            end
        end
        Box(envelop_lower, envelop_upper) => begin
            if envelop_upper <= upper && lower <= envelop_lower
                return envelop
            elseif envelop_lower > upper || envelop_upper < lower
                return Infeasible()
            else
                new_lower = max(envelop_lower, lower)
                new_upper = min(envelop_upper, upper)
                return Box(new_lower, new_upper)
            end
        end
    end
end

#=
Consider implementation of the following sets:
- MOI.Semiinteger
- MOI.Semicontinuous

Such sets cannot be solved by natural QUMO solvers, so
we may just want to throw an exception.
One possibility for the Semicontinuous is to extend the
range to include 0, and then solve the problem.
=#