#=
market.jl

Helper structures and functions for the single security transaction settlement.

=#

"""
    Setup{T, TV}

Setup of the transaction settlement scenario. This stores the initial state of the system.
"""
struct Setup{T <: Real, TV <: AbstractVector{T}}
    currency::TV
    security::TV
    conversion::TV
end

"""
    Transaction{T, TM}

Set of transactions.
"""
struct Transaction{T <: Real, TM <: AbstractMatrix{T}}
    currency::TM
    security::TM
end

"""
    Market{T, TV, TM}

A transaction settlement problem. It stores the initial condititions and the
set of requested transactions.
"""
struct Market{T <: Real, TV <: AbstractVector{T}, TM <: AbstractMatrix{T}}
    setup::Setup{T, TV}
    transactions::Transaction{T, TM}
end

number_of_participants(market::Market) = length(market.setup.currency)
number_of_transactions(market::Market) = size(market.transactions.security, 2)

struct MarketState{T<:Real}
    Currency::Vector{T}
    Security::Vector{T}
    AfterConversion::Vector{T}
end

function _vectorize(x::Vector{Tuple{Int32, T}}) where T
    dimension = maximum(x)[1]
    v = zeros(T, dimension)
    for (i, value) in x
        v[i] = value
    end
    return v
end

function _parse_setup(::Type{T}, setup::Scenario)::Setup where {T <: AbstractFloat}
    currency, security, conversion = map(x -> begin
        id = Int32(x.id.id)
        currency_balance = T(x.currency_balance)
        security_balance = T(x.security_balance)
        if x.exchange_factor === nothing
            exchange_factor = T(0.0)
        else
            exchange_factor = T(x.exchange_factor.currency) / T(x.exchange_factor.security)
        end

        (id, currency_balance), (id, security_balance), (id, exchange_factor)
    end, setup.initial) |> unzip |> Map(_vectorize) |> collect;

    return Setup(T.(currency), T.(security), T.(conversion))
end

function _parse_transactions(::Type{T}, setup::Scenario)::Transaction where {T <: AbstractFloat}
    security, currency = map(x -> begin
        id = Int32(x.id.id)
        security_from = Int32(x.security_from.id)
        security_to = Int32(x.security_to.id)
        security_amount = T(x.security_amount)
        currency_from = Int32(x.cash_from.id)
        currency_to = Int32(x.cash_to.id)
        currency_amount = T(x.cash_amount)

        (security_from, id, -security_amount),
        (security_to, id, security_amount),
        (currency_from, id, -currency_amount),
        (currency_to, id, currency_amount)
    end, setup.transactions) |> unzip |> (
        x -> begin
            security_out = x[1]
            security_in = x[2]
            currency_out = x[3]
            currency_in = x[4]

            everything = [security_out; security_in; currency_out; currency_in]
            number_of_transactions, _ = findmax(x -> x[2], everything)
            number_of_participants, _ = findmax(x -> x[1], everything)

            @info "Number of transactions: $number_of_transactions, number of participants: $number_of_participants"

            securities = [security_out; security_in]
            currencies = [currency_out; currency_in]

            # Create sparse matrices
            securities_matrix = securities |> unzip |> (x -> sparse(x[1], x[2], x[3], number_of_participants, number_of_transactions))
            currencies_matrix = currencies |> unzip |> (x -> sparse(x[1], x[2], x[3], number_of_participants, number_of_transactions))

            securities_matrix, currencies_matrix
        end
    )

    return Transaction(T.(currency), T.(security))
end

function parse(::Type{T}, scenario::Scenario)::Market where {T <: AbstractFloat}
    setup = _parse_setup(T, scenario)
    transactions = _parse_transactions(T, scenario)

    number_of_participants = length(scenario.initial)
    number_of_transactions = length(scenario.transactions)

    @assert size(setup.currency) == (number_of_participants,)
    @assert size(setup.security) == (number_of_participants,)
    @assert size(setup.conversion) == (number_of_participants,)
    @assert size(transactions.security) == (number_of_participants, number_of_transactions)
    @assert size(transactions.currency) == (number_of_participants, number_of_transactions)

    return Market(setup, transactions)
end

function parse_from_file(::Type{T}, filename::AbstractString)::Market where {T <: AbstractFloat}
    scenario = ParseSingleCSV.parse_file(filename)
    validate(scenario)
    return parse(T, scenario)
end

function execute(transactions::Vector{TIndex}, market::Market) where TIndex <: Integer
    currency = copy(market.setup.currency)
    security = copy(market.setup.security)

    for transaction in transactions
        currency .+= market.transactions.currency[:, transaction]
        security .+= market.transactions.security[:, transaction]

        @debug begin
            println("Transaction $transaction")
            println("C: ", currency)
            println("S: ", security)
            println("E: ", currency .+ market.setup.conversion .* security)
        end
    end

    # Currencies and securities cannot disappear
    @assert sum(security) == sum(market.setup.security)
    @assert sum(currency) == sum(market.setup.currency)

    after_conversion = currency .+ market.setup.conversion .* security

    # Return the final state of the system for further analysis
    return MarketState(currency, security, after_conversion)
end

function admissible(transactions::Vector{TIndex}, market::Market; state::Union{Nothing, MarketState}=nothing) where TIndex <: Integer
    if state === nothing
        state = execute(transactions, market)
    end
    ntransactions = number_of_transactions(market)
    pending_transactions = setdiff(1:ntransactions, transactions)

    result = []
    @simd for transaction in pending_transactions
        @debug "Examing unfulfilled transaction $transaction"
        final_securities = state.Security .+ market.transactions.security[:, transaction]
        could_be_executed =
            all(final_securities .>= 0) &&
            all(state.Currency .+ market.transactions.currency[:, transaction] .+ market.setup.conversion .* final_securities .>= 0)

        if could_be_executed
            @debug "Transaction $transaction could be executed"
            push!(result, transaction)
        end
    end

    return result
end

function validate_solution(solution::Vector{TIndex}, market::Market; check_admissible::Bool=false) where TIndex <: Integer
    state = execute(solution, market)

    invalid_securities = findall(state.Security .< 0)
    invalid_balance = findall(state.AfterConversion .< 0)

    if !isempty(invalid_securities)
        @error "Invalid securities: $(invalid_securities)"
    end
    if !isempty(invalid_balance)
        @error "Invalid balances  : $(invalid_balance)"
    end

    @assert all(state.Security .>= 0)
    @assert all(state.AfterConversion .>= 0)

    if check_admissible
        valid = admissible(solution, market; state=state)
        @assert isempty(valid) "Extra transactions that can be admitted: $(valid)"
    else
        @info "Not checking for admissable transactions"
    end
end
