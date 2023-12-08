#=
model.jl

Implementation of the model for the simple transaction settlement problem.

=#

const TId = UInt32
const TVal = UInt32

struct PartyId
    id::TId

    function PartyId(id::Integer)
        @assert id > 0
        new(id)
    end
end

Base.show(io::IO, p::PartyId) = print(io, "P$(p.id)")

struct TransactionId
    id::TId

    function TransactionId(id::Integer)
        @assert id > 0
        new(id)
    end
end

Base.show(io::IO, p::TransactionId) = print(io, "T$(p.id)")

struct ExchangeFactor
    security::TVal
    currency::TVal

    function ExchangeFactor(security::Integer, currency::Integer)
        @assert security > 0
        @assert currency > 0
        new(security, currency)
    end
end

Base.show(io::IO, e::ExchangeFactor) = print(io, "$(e.security)S -> $(e.currency)C")

struct PartyInfo
    id::PartyId
    security_balance::TVal
    currency_balance::TVal
    exchange_factor::Union{Nothing, ExchangeFactor}
end

function Base.show(io::IO, p::PartyInfo)
    if p.exchange_factor === nothing
        print(io, "($(p.id), S:$(p.security_balance), C:$(p.currency_balance), NA)")
    else
        print(io, "($(p.id), S:$(p.security_balance), C:$(p.currency_balance), $(p.exchange_factor))")
    end
end

struct TransactionInfo
    id::TransactionId
    security_from::PartyId
    security_to::PartyId
    security_amount::TVal
    cash_from::PartyId
    cash_to::PartyId
    cash_amount::TVal
end

Base.show(io::IO, t::TransactionInfo) = print(io, "($(t.id): S:$(t.security_from)->$(t.security_to): $(t.security_amount), C:$(t.cash_from)->$(t.cash_to): $(t.cash_amount))")

struct Scenario
    initial::Vector{PartyInfo}
    transactions::Vector{TransactionInfo}
end

function Base.show(io::IO, scenario::Scenario)
    print(io, "Scenario with $(length(scenario.initial)) parties and $(length(scenario.transactions)) transactions:\n")
    print(io, "Initial balances:\n")
    for p in scenario.initial
        print(io, "  $(p)\n")
    end
    print(io, "Transactions:\n")
    for t in scenario.transactions
        print(io, "  $(t)\n")
    end
end

function validate(id::PartyId)
    @assert id.id > 0
end

function validate(id::TransactionId)
    @assert id.id > 0
end

function validate(e::ExchangeFactor)
    @assert e.security > 0
    @assert e.currency > 0
end

function validate(p::PartyInfo)
    validate(p.id)
    @assert p.security_balance >= 0
    @assert p.currency_balance >= 0
    if p.exchange_factor !== nothing
        validate(p.exchange_factor)
    end
end

function validate(t::TransactionInfo)
    validate(t.id)
    validate(t.security_from)
    validate(t.security_to)
    validate(t.cash_from)
    validate(t.cash_to)
    @assert t.security_from != t.security_to
    @assert t.cash_from != t.cash_to
    @assert t.security_from == t.cash_to
    @assert t.security_to == t.cash_from
    @assert t.security_amount > 0
    @assert t.cash_amount > 0
end

function validate(scenario::Scenario)
    for p in scenario.initial
        validate(p)
    end
    for t in scenario.transactions
        validate(t)
    end
end
