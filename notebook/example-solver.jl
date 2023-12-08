#=
Read a CSV file containing a single commodity transaction settlement instance
and solve it.

=#

using Revise
using JuMP
using SingleSecurityAndCashDemo.SingleSecurityAndCash: parse_from_file, create_model, solve, GurobiBackend
using SingleSecurityAndCashDemo.SingleSecurityAndCash: validate_solution, number_of_transactions

directory = joinpath(@__DIR__, "data");
filename = joinpath(directory, "DVP_Chains_Scenarios_Output_Iteration_Count_P_1_T_1.csv");

market = parse_from_file(Float64, filename);
model = create_model(market);
@time solution = solve(model);
solution_summary(model)

check_admissible = number_of_transactions(market) < 200
validate_solution(solution, market; check_admissible=check_admissible)
