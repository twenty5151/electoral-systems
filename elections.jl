module elections
using StatsBase
using Distributions
using ProgressMeter
using DataFrames
using Plots
gr()

export fptp, approval, sorter, approval_bullet, borda, irv, score, election, loop_elections, plotter

function fptp(distance_list)
    fptp_votes = argmin.(eachrow(distance_list))
    winner = StatsBase.countmap(fptp_votes)
    collectkeys = collect(keys(winner))
    collectvalues = collect(values(winner))
    return collectkeys[argmax(collectvalues)]
end

function approval(distance_list, a=0, b=1)
    approval_radii = rand(Distributions.LogNormal(0,0.5), size(distance_list)[1])
    approval_list = distance_list .<= approval_radii
    winner = argmax(count.(eachcol(approval_list)))
    return winner
end

function sorter(distance_list)
    cols = size(distance_list)[1]
    rows = size(distance_list)[2]
    arr = zeros(Int64, (cols, rows))
    x = collect(eachrow(distance_list))
    for i in 1:size(arr)[1]
        arr[i, :] .= sortperm(x[i])
    end
    return arr
end

function approval_bullet(distance_list; a=0, b=1, probability=1/3)
    approval_radii = rand(Distributions.LogNormal(0,0.5), size(distance_list)[1])
    approval_list = distance_list .<= approval_radii
    if probability != 0
        list_size = size(approval_list)[1]
        unfolded = sorter(distance_list)
        indices = StatsBase.sample(1:list_size, floor(Int, probability*list_size), replace=false)
        for i in 1:list_size
            if i in indices
                current_row = approval_list[i, :]
                if sum(current_row) > 1
                    approval_list[i, :] = BitArray([0, 0, 0])
                    approval_list[i, argmin(unfolded[i, :])] = true
                end
            end
        end
    end

    winner = argmax(count.(eachcol(approval_list)))
    return winner
end

function borda(distance_list, candidate_x_coord)
    unfolded = sorter(distance_list)
    borda_count = StatsBase.countmap.(eachcol(unfolded))
    # columns are candidates, rows are their borda scores to be summed
    res = fill(0, size(candidate_x_coord)[2], size(borda_count)[1])

    for i in 1:size(borda_count)[1]
        for (k,v) in borda_count[i]
            # res[row][column]
            res[i, k] = v*i
        end
    end

    borda_sum = sum(res,dims=1)
    borda_winner = argmin(borda_sum)[2]
    return borda_winner
end

function score(distance_list)
    # TODO: variable score radii -- why not use Approval's LogNormal?
    # each 'bin' gets a higher mean? but some values might be lower than the prev bin
    # rand(Distributions.LogNormal(0,0.5), 1)
    distlst = replace!(x -> x<=0.5 ? 10 : x, distance_list)
    distlst = replace!(x -> x>3 && x!=10 ? 0 : x, distance_list)
    distlst = replace!(x -> 0.5<x<=1 ? 8 : x, distance_list)
    distlst = replace!(x -> 1<x<=2 ? 7 : x, distance_list)
    distlst = replace!(x -> 2<x<=3 ? 5 : x, distance_list)
    score_sum = sum(distlst, dims=1)
    score_winner_pos = argmax(score_sum)[2]
    return score_winner_pos
end

function irv(distance_list)
    unfolded = sorter(distance_list)
    first_pref = unfolded[:,1]

    while true
        bincount = StatsBase.countmap(first_pref)
        collectkeys = collect(keys(bincount))
        collectvalues = collect(values(bincount))
        pos_of_max = collectkeys[argmax(collectvalues)]

        if bincount[pos_of_max] >= sum(collectvalues)/2
            return pos_of_max
        else
            lowest_cand = collectkeys[argmin(collectvalues)][1]
            @inbounds for i in 1:size(findall(first_pref.==lowest_cand))[1]
                row_num = findnext(first_pref.==lowest_cand, i)
                first_pref[row_num] = unfolded[row_num, 2]
            end
        end
    end
end

function election(voter_mean_x, voter_mean_y, stdev, number_of_voters, candidate_x_coord, candidate_y_coord)
    v_x = rand(Distributions.Normal(voter_mean_x, stdev), number_of_voters)
    v_y = rand(Distributions.Normal(voter_mean_y, stdev), number_of_voters)

    distance_list = hypot.(v_x .- candidate_x_coord, # diff_x
                           v_y .- candidate_y_coord) # diff_y

    fptp_winner::Integer = fptp(distance_list)
    approval_winner::Integer = approval(distance_list)
    borda_winner::Integer = borda(distance_list, candidate_x_coord)
    irv_winner::Integer = irv(distance_list) # There's a bizzare bug where calling score() first will mess up this function's order
    score_winner::Integer = score(distance_list)

    return (fptp_winner, approval_winner, borda_winner, irv_winner, score_winner)
end

function loop_elections(voter_grid, candidate_x_coord, candidate_y_coord, number_of_voters=1000, stdev=1)
    voter_grid_tup_arr = vec(collect(voter_grid))
    voter_grid_size = size(voter_grid_tup_arr)[1]
    a, b = zeros(Float64, voter_grid_size), zeros(Float64, voter_grid_size)

    fptp_winner, approval_winner,
    borda_winner, irv_winner, score_winner =
        zeros(Integer, voter_grid_size), zeros(Integer, voter_grid_size),
        zeros(Integer, voter_grid_size), zeros(Integer, voter_grid_size),
        zeros(Integer, voter_grid_size)

    @showprogress for i in 1:voter_grid_size
        fptp_winner[i]::Integer,
        approval_winner[i]::Integer,
        borda_winner[i]::Integer,
        irv_winner[i]::Integer,
        score_winner[i]::Integer =
            election(voter_grid_tup_arr[i][1], voter_grid_tup_arr[i][2], stdev, number_of_voters, candidate_x_coord, candidate_y_coord)

        a[i] = voter_grid_tup_arr[i][1]
        b[i] = voter_grid_tup_arr[i][2]
    end

    vdf = DataFrame()
    vdf.FPTP = fptp_winner
    vdf.Approval = approval_winner
    vdf.Borda = borda_winner
    vdf.IRV = irv_winner
    vdf.Score = score_winner
    vdf.x = a
    vdf.y = b
    return vdf
end

function plotter(df, candidate_x_coord, candidate_y_coord)
    p1 = plot(df.x, df.y, title="FPTP", seriestype=:scatter, color=df.FPTP, palette=[:red, :lightgreen, :blue], msw=0, markersize=2)
    plot!(candidate_x_coord, candidate_y_coord, seriestype=:scatter, palette=[:green, :blue, :red], msw=1, markersize=5, lims=(-2,2))
    p2 = plot(df.x, df.y, title="Approval", seriestype=:scatter, color=df.Approval, palette=[:red, :lightgreen, :blue], msw=0, markersize=2)
    plot!(candidate_x_coord, candidate_y_coord, seriestype=:scatter, palette=[:green, :blue, :red], msw=1, markersize=5, lims=(-2,2))
    p3 = plot(df.x, df.y, title="Borda", seriestype=:scatter, color=df.Borda, palette=[:red, :lightgreen, :blue], msw=0, markersize=2)
    plot!(candidate_x_coord, candidate_y_coord, seriestype=:scatter, palette=[:green, :blue, :red], msw=1, markersize=5, lims=(-2,2))
    p4 = plot(df.x, df.y, title="IRV", seriestype=:scatter, color=df.IRV, palette=[:red, :lightgreen, :blue], msw=0, markersize=2)
    plot!(candidate_x_coord, candidate_y_coord, seriestype=:scatter, palette=[:green, :blue, :red], msw=1, markersize=5, lims=(-2,2))
    p5 = plot(df.x, df.y, title="Score", seriestype=:scatter, color=df.Score, palette=[:red, :lightgreen, :blue], msw=0, markersize=2)
    plot!(candidate_x_coord, candidate_y_coord, seriestype=:scatter, palette=[:green, :blue, :red], msw=1, markersize=5, lims=(-2,2))
    final_plot = plot(p1, p2, p3, p4, p5, legend = false, size=((900,500)))
    return final_plot
end

end
