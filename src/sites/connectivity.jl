"""
    site_connectivity(file_loc, site_order; con_cutoff=0.02, agg_func=mean, swap=false)::NamedTuple

Create transitional probability matrix indicating connectivity between
sites, level of centrality, and the strongest predecessor for each site.

NOTE: Transposes transitional probability matrix
      If multiple files are read in, this assumes all file rows/cols
      follow the same order as the first file read in.


Parameters
----------
file_loc   : str, path to data file (or datasets) to load.
                If a folder, searches subfolders as well.
site_order : string, array of recom connectivity IDs indicating order
                of TP values
con_cutoff : float, percent thresholds of max for weak connections in
                network (defined by user or defaults in simConstants)
agg_func   : function_handle, defaults to `mean`.
swap       : logical, whether to transpose data.


Returns
-------
NamedTuple:
    TP_data : DataFrame, containing the transition probability for all sites
    truncated : ID of sites removed
    site_ids : ID of sites kept


Examples
--------
    site_connectivity("MooreTPmean.csv", site_order)
    site_connectivity("MooreTPmean.csv", site_order; con_cutoff=0.01, agg_func=mean, swap=true)
"""
function site_connectivity(file_loc::String, site_order::Array; con_cutoff=0.02, agg_func=mean, swap=false)::NamedTuple
    if any(ismissing.(site_order))
        @warn "Removing entries marked as `missing` from provided list of sites (`site_order`)."
        site_order = skipmissing(site_order)
    end

    if isdir(file_loc)
        con_files = []
        for (root, _, files) in walkdir(file_loc)
            append!(con_files, map((x) -> joinpath(root, x), files))
        end
    elseif isfile(file_loc)
        con_files = [file_loc]
    else
        error("Could not find location: $(file_loc)")
    end

    # Get site ids from first file
    con_file1 = CSV.read(con_files[1], DataFrame, comment="#", missingstring=["NA"], transpose=swap)
    con_site_ids = names(con_file1)[2:end]

    # Get IDs missing in con_site_ids
    truncated = setdiff(con_site_ids, site_order)

    # Get IDs missing in site_order
    append!(truncated, setdiff(site_order, con_site_ids))

    # Identify IDs that appear in both datasets
    valid_ids = [x for x in con_site_ids if x ∉ truncated]

    if length(truncated) > 0
        if length(truncated) == length(con_site_ids)
            error("All sites appear to be missing from data set. Aborting.")
        end

        for missing_id in truncated
            @warn "$(missing_id) not found in site_ids! This site will be removed from runs."
        end
    end

    # Helper method to align/reorder data
    # Here, we use the column index to align the rows.
    # Columns should match order of rows, except that Julia DFs treats the
    # index column as the first data column. To account for this, we subtract 1
    # from the list of row indices to get things to line up properly.
    align_df = (target_df) -> target_df[indexin(valid_ids, names(target_df)) .- 1, valid_ids]

    # Reorder all data into expected form
    con_file1 = align_df(con_file1)  # con_file1[indexin(valid_ids, names(con_file1)) .- 1, valid_ids]
    if length(con_files) > 1
        # More than 1 file, so read all these in
        con_data = [con_file1]
        for cf in con_files[2:end]
            df = CSV.read(cf, DataFrame, comment="#", missingstring=["NA"], transpose=swap)
            push!(con_data, align_df(df))  # df[indexin(valid_ids, names(df)) .- 1, valid_ids]
        end

        # Fill missing values with 0.0
        TP_base = similar(con_file1)
        tmp = agg_func(cat(map(Matrix, con_data), dims=3))

        TP_base[:, :] .= coalesce.(tmp, 0.0)
    else
        if any(ismissing.(Matrix(con_file1)))
            tmp = Matrix(con_file1)
            tmp[ismissing.(tmp)] .= 0.0
            con_file1[:, :] = coalesce.(tmp, 0.0)
        end

        TP_base = con_file1
    end

    if con_cutoff > 0.0
        tmp = Matrix(TP_base)
        max_cutoff = maximum(tmp) * con_cutoff
        tmp[tmp .< max_cutoff] .= 0.0
        TP_base[:, :] = tmp
    end

    return (TP_base=TP_base, truncated=truncated, site_ids=valid_ids)
end


"""
    connectivity_strength(TP_base::DataFrame)::NamedTuple

Generate array of outdegree connectivity strength for each node and its
strongest predecessor.
"""
function connectivity_strength(TP_base::DataFrame)::NamedTuple

    g = SimpleDiGraph(Matrix(TP_base))

    # ew_base = weights(g)  # all equality weighted anyway...
    # Measure centrality based on number of incoming connections
    C1 = outdegree_centrality(g)

    # For each edge, find strongly connected predecessor (by number of connections)
    strongpred = similar(C1, Int64)
    for v_id in vertices(g)
        incoming = inneighbors(g, v_id)

        if length(incoming) > 0
            # For each incoming connection, find the one with most "in"
            # connections themselves
            in_conns = [length(inneighbors(g, in_id)) for in_id in incoming]

            # Find index of predecessor with most connections
            # (use `first` to get the first match in case of a tie)
            most_conns = maximum(in_conns)
            idx = first(findall(in_conns .== most_conns))
            strongpred[v_id] = incoming[idx]
        else
            strongpred[v_id] = 0
        end
    end

    return (site_ranks=C1, strongest_predecessor=strongpred)
end