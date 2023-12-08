#=
SingleSecurityAndCash.jl

This module implements a simple transaction settlement scenario with a single security
and cash transactions. I.e., there is only one type of security in the market and
the participants can only exchange it for cash.

Some of the participants have the ability to use an exchange facility,
where they can trade the security for cash at a fixed exchange rate.
The exchange rate is specific to each participant; not all participants
have access to the exchange facility.

The goal is to clear the market, i.e., enable transactions to happen without violating
cash or security balances of the participants. In other words, at the end, all the
cash and security balances shoule be positive or zero. If a cash balance is negative,
but the participant has access to the exchange facility and positive security balance,
then the participant can use the exchange facility to clear the cash balance.

The objective is to enable as many transactions as possible. An alternative objective
is to maximise the total value of the transactions.

=#

module SingleSecurityAndCash

using JuMP
using HiGHS
using Parameters
using SparseArrays
using Transducers
using Unzip

# Here we define the model that is used for parsing the input data
include("model.jl")
# Grammar and parser from the text file (typically CSV) to the model
include("parser.jl")
# Convert the parsed model to helper structures that can be used for
# defining optimization problems
include("market.jl")
# Modeling of the transaction settlement problem as a mathematical optimization problem,
include("mathopt.jl")

end # module