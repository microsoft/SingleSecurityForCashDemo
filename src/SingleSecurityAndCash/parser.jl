#=
parser.jl

This is a parser for the new format of the transaction settlement scenario.
The input file is a text file (masquerading as a CSV file)
that contains two sections: the first section contains the party data and
the second section contains the transaction data. Each section is indeed
a CSV file, and the two sections are separated by blank lines.
=#

module ParseSingleCSV

using ParserCombinator
using ..SingleSecurityAndCash: PartyId, TransactionId, PartyInfo, ExchangeFactor, TransactionInfo, Scenario

const ws = ~p"[\s]+"
const space = ~p"[\s]*"
const id = p"\d+"
const sep = ~p"\s*,\s*"

parse_id = PUInt32
parse_val = PUInt32

parse_party_info_header = ~p"Party Id,Security Balance,Currency Balance,CCF Exchange Factor"
parse_party_id = E"P" + parse_id() |> (x -> PartyId(x[1]))

parse_exchange_factor = Opt(parse_party_id + ws +
                            E"converts" + ws +
                            parse_val() + E"S into" + ws +
                            parse_val() + E"C" + space) |> (
                                x -> length(x)>0 ? (x[1], ExchangeFactor(x[2], x[3])) : nothing
                            )

parse_party_initial = parse_party_id + sep + parse_val() + sep + parse_val() + sep + parse_exchange_factor |> (
    x -> begin
        if x[4] === nothing
            PartyInfo(x[1], x[2], x[3], nothing)
        else
            candidate = x[4][1]
            @assert candidate == x[1]
            exchange = PartyInfo(x[1], x[2], x[3], x[4][2])
        end

    end)

parse_party_section = parse_party_info_header + ws + Repeat(parse_party_initial) |> vec

parse_transaction_info_header = ~p"Transaction Id,From,To,Security Amount,From,To,Cash Amount"
parse_transaction_id = E"T" + parse_id() + space |> (x -> TransactionId(x[1]))

parse_transaction = parse_transaction_id + sep +
                    parse_party_id + sep + parse_party_id + sep + parse_val() + sep +
                    parse_party_id + sep + parse_party_id + sep + parse_val() + space |> (
                        x -> TransactionInfo(x[1], x[2], x[3], x[4], x[5], x[6], x[7])
                    )

parse_transaction_section = parse_transaction_info_header + ws + Repeat(parse_transaction + space) |> vec

parse_scenario = parse_party_section + space + parse_transaction_section |> (x -> Scenario(x[1], x[2]))

function parse_text(input::String)::Scenario
    return parse_one(input, parse_scenario)[1]
end

function parse_file(filename::String)::Scenario
    if isfile(filename) == false
        error("File $filename does not exist.")
    end

    input = read(filename, String)
    return parse_one(input, parse_scenario)[1]
end

end # module ParseSingleCSV
