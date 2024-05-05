import GeoMakie.GeoJSON: AbstractFeatureCollection, features, bbox
import ArchGDAL as AG
using Graphs, GraphMakie, SimpleWeightedGraphs

# Temporary monkey-patch to support retrieval of multiple features
Base.getindex(fc::AbstractFeatureCollection, i::UnitRange) = features(fc)[i]
Base.getindex(fc::AbstractFeatureCollection, i::Vector) = features(fc)[i]

"""
    create_map!(
        f::Union{GridLayout,GridPosition},
        geodata::GeoMakie.GeoJSON.FeatureCollection,
        data::Observable,
        highlight::Union{Vector,Tuple,Nothing},
        show_colorbar::Bool=true,
        colorbar_label::String="",
        legend_params::Union{Tuple,Nothing}=nothing,
        axis_opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(),
    )

Create a spatial choropleth figure.

# Arguments
- `f` : Makie figure to create plot in
- `geodata` : FeatureCollection, Geospatial data to display
- `data` : Values to use for choropleth
- `highlight` : Stroke colors for each location
- `show_colorbar` : Whether to show a colorbar (true) or not (false)
- `colorbar_label` : Label to use for color bar
- `color_map` : Type of colormap to use,
    See: https://docs.makie.org/stable/documentation/colors/#colormaps
- `legend_params` : Legend parameters
- `axis_opts` : Additional options to pass to adjust Axis attributes
  See: https://docs.makie.org/v0.19/api/index.html#Axis
"""
function create_map!(
    f::Union{GridLayout,GridPosition},
    geodata::Vector{<:GeoMakie.GeometryBasics.Polygon},
    data::Observable,
    highlight::Union{Vector,Tuple,Nothing},
    show_colorbar::Bool=true,
    colorbar_label::String="",
    color_map::Union{Symbol,Vector{Symbol},RGBA{Float32},Vector{RGBA{Float32}}}=:grayC,
    legend_params::Union{Tuple,Nothing}=nothing,
    axis_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}()
)
    axis_opts[:title] = get(axis_opts, :title, "Study Area")
    axis_opts[:xlabel] = get(axis_opts, :xlabel, "Longitude")
    axis_opts[:ylabel] = get(axis_opts, :ylabel, "Latitude")
    axis_opts[:xgridwidth] = get(axis_opts, :xgridwidth, 0.5)
    axis_opts[:ygridwidth] = get(axis_opts, :ygridwidth, 0.5)

    spatial = GeoAxis(
        f[1, 1];
        dest="+proj=latlong +datum=WGS84",
        axis_opts...
    )

    spatial.xticklabelsize = 14
    spatial.yticklabelsize = 14

    max_val = @lift(maximum($data))

    # Plot geodata polygons using data as internal color
    color_range = (0.0, max_val[])

    poly!(
        spatial,
        geodata;
        color=data,
        colormap=color_map,
        colorrange=color_range,
        strokecolor=(:black, 0.05),
        strokewidth=1.0
    )

    if show_colorbar
        Colorbar(
            f[1, 2];
            colorrange=color_range,
            colormap=color_map,
            label=colorbar_label,
            height=Relative(0.65)
        )
    end

    # Overlay locations to be highlighted
    # `poly!()` cannot handle multiple strokecolors being specified at the moment
    # so we instead overlay each cluster.
    if !isnothing(highlight)
        if highlight isa Tuple
            poly!(
                spatial,
                geodata;
                color="transparent",
                strokecolor=highlight,
                strokewidth=0.5,
                linestyle=:solid,
                overdraw=true
            )
        else
            hl_groups = unique(highlight)

            for color in hl_groups
                m = findall(highlight .== [color])
                subset_feat = FC(; features=geodata[m])

                poly!(
                    spatial,
                    subset_feat;
                    color="transparent",
                    strokecolor=color,
                    strokewidth=0.5,
                    linestyle=:solid,
                    overdraw=true
                )
            end
        end

        if !isnothing(legend_params)
            # Plot Legend only if highlight colors are present
            Legend(f[1, 3], legend_params...; framevisible=false)
        end
    end

    return f
end

"""
    ADRIA.viz.map(rs::Union{Domain,ResultSet}; opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(), fig_opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(), axis_opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(), series_opts=Dict())
    ADRIA.viz.map(rs::ResultSet, y::YAXArray; opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(), fig_opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(), axis_opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(), series_opts=Dict())
    ADRIA.viz.map!(f::Union{GridLayout,GridPosition}, rs::ADRIA.ResultSet, y::AbstractVector; opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}(), axis_opts::Dict{Symbol, <:Any}=Dict{Symbol, Any}())

Plot spatial choropleth of outcomes.

# Arguments
- `rs` : ResultSet
- `y` : results of scenario metric
- `opts` : Aviz options
    - `colorbar_label`, label for colorbar. Defaults to "Relative Cover"
    - `color_map`, preferred colormap for plotting heatmaps
- `axis_opts` : Additional options to pass to adjust Axis attributes
  See: https://docs.makie.org/v0.19/api/index.html#Axis

# Returns
GridPosition
"""
function ADRIA.viz.map(
    rs::Union{Domain,ResultSet},
    y::Union{YAXArray,AbstractVector{<:Real}};
    opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    fig_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    axis_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}()
)
    f = Figure(; fig_opts...)
    g = f[1, 1] = GridLayout()

    ADRIA.viz.map!(g, rs, collect(y); opts, axis_opts)

    return f
end
function ADRIA.viz.map(
    rs::Union{Domain,ResultSet};
    opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    fig_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    axis_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}()
)
    f = Figure(; fig_opts...)
    g = f[1, 1] = GridLayout()

    opts[:colorbar_label] = get(opts, :colorbar_label, "Coral Real Estate [%]")

    opts[:show_management_zones] = get(opts, :show_management_zones, false)
    if opts[:show_management_zones]
        local highlight
        try
            highlight = Symbol.(lowercase.(rs.site_data.zone_type))
        catch
            # Annoyingly, the case of the name may have changed...
            highlight = Symbol.(lowercase.(rs.site_data.ZONE_TYPE))
        end
        opts[:highlight] = highlight
    end

    ADRIA.viz.map!(g, rs, rs.site_data.k * 100.0; opts, axis_opts)

    return f
end
function ADRIA.viz.map!(
    g::Union{GridLayout,GridPosition},
    rs::Union{Domain,ResultSet},
    y::AbstractVector{<:Real};
    opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    axis_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}()
)
    geodata = _get_geoms(rs.site_data)
    data = Observable(collect(y))

    highlight = get(opts, :highlight, nothing)
    c_label = get(opts, :colorbar_label, "")
    legend_params = get(opts, :legend_params, nothing)
    show_colorbar = get(opts, :show_colorbar, true)
    color_map = get(opts, :color_map, :grayC)

    return create_map!(
        g,
        geodata,
        data,
        highlight,
        show_colorbar,
        c_label,
        color_map,
        legend_params,
        axis_opts
    )
end

"""
    ADRIA.viz.map(gdf::DataFrame; geom_col=:geometry, color=nothing)

Plot an arbitrary GeoDataFrame, optionally specifying a color for each feature.

# Arguments
- `gdf` : GeoDataFrame to plot
- `geom_col` : Column in GeoDataFrame that holds feature data
- `color` : Colors to use for each feature
"""
function ADRIA.viz.map(gdf::DataFrame; geom_col=:geometry, color=nothing)
    f = Figure(; size=(600, 900))
    ga = GeoAxis(
        f[1, 1];
        dest="+proj=latlong +datum=WGS84",
        xlabel="Longitude",
        ylabel="Latitude",
        xticklabelpad=15,
        yticklabelpad=40,
        xticklabelsize=10,
        yticklabelsize=10,
        aspect=AxisAspect(0.75),
        xgridwidth=0.5,
        ygridwidth=0.5
    )

    ADRIA.viz.map!(ga, gdf; geom_col=geom_col, color=color)

    display(f)

    return f
end

"""
    ADRIA.viz.map!(gdf::DataFrame; geom_col=:geometry, color=nothing)::Nothing
"""
function ADRIA.viz.map!(gdf::DataFrame; geom_col=:geometry, color=nothing)::Nothing
    ga = current_axis()
    ADRIA.viz.map!(ga, gdf; geom_col=geom_col, color=color)

    return nothing
end
function ADRIA.viz.map!(
    ga::GeoAxis, gdf::DataFrame; geom_col=:geometry, color=nothing
)::Nothing
    plottable = _get_geoms(dom.site_data, geom_col)

    if !isnothing(color)
        poly!(ga, plottable; color=color)
    else
        poly!(ga, plottable)
    end

    # Auto-determine x/y limits
    autolimits!(ga)
    xlims!(ga)
    ylims!(ga)

    return nothing
end

"""
    ADRIA.viz.connectivity(dom::Domain, network::SimpleWeightedDiGraph, conn_weights::AbstractVector{<:Real}; opts::Dict{Symbol, <:Any}=Dict{Symbol, <:Any}(), fig_opts::Dict{Symbol, <:Any}=Dict{Symbol, <:Any}(), axis_opts::Dict{Symbol, <:Any}=Dict{Symbol, <:Any}())
    ADRIA.viz.connectivity!(g::Union{GridLayout, GridPosition}, dom::Domain,  network::SimpleWeightedDiGraph, conn_weights::AbstractVector{<:Real}; opts::Dict{Symbol, <:Any}=Dict{Symbol, <:Any}(), axis_opts::Dict{Symbol, <:Any}=Dict{Symbol, <:Any}())

Produce visualization of connectivity between reef sites with node size and edge visibility
weighted by the connectivity values and node weights.

# Examples

```julia
dom = ADRIA.load_domain("<Path to Domain>")

in_conn, out_conn, network = ADRIA.connectivity_strength(dom; out_method=eigenvector_centrality)

ADRIA.viz.connectivity(
    dom,
    network,
    out_conn;
    opts=opts,
    fig_opts=fig_opts,
    axis_opts=axis_opts
)
```

# Arguments
- `dom` : Domain
- `network` : SimpleWeightedDiGraph calculated from the connectivity matrix
- `conn_weights` : Connectivity weighted for each node
- `opts` : AvizOpts
    - `edge_color`, vector of colours for edges. Defaults to reasonable weighting
    - `node_color`, vector of colours for node. Defaults to `conn_weights`
    - `node_size`, size of nodes in the graph
- `fig_opts` : Figure options
- `axis_opts` : Axis options
"""
function ADRIA.viz.connectivity(
    dom::Domain,
    network::SimpleWeightedDiGraph,
    conn_weights::AbstractVector{<:Real};
    opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    fig_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    axis_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}()
)
    f = Figure(; fig_opts...)
    g = f[1, 1] = GridLayout()

    ADRIA.viz.connectivity!(g, dom, network, conn_weights; opts, axis_opts)

    return f
end
function ADRIA.viz.connectivity!(
    g::Union{GridLayout,GridPosition},
    dom::Domain,
    network::SimpleWeightedDiGraph,
    conn_weights::AbstractVector{<:Real};
    opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
    axis_opts::Dict{Symbol,<:Any}=Dict{Symbol,Any}()
)
    axis_opts[:title] = get(axis_opts, :title, "Study Area")
    axis_opts[:xlabel] = get(axis_opts, :xlabel, "Longitude")
    axis_opts[:ylabel] = get(axis_opts, :ylabel, "Latitude")

    spatial = GeoAxis(
        g[1, 1];
        dest="+proj=latlong +datum=WGS84",
        axis_opts...
    )

    geodata = _get_geoms(dom.site_data)

    spatial.xticklabelsize = 14
    spatial.yticklabelsize = 14
    spatial.yticklabelpad = 50
    spatial.ytickalign = 10

    # Calculate alpha values for edges based on connectivity strength and weighting
    edge_col = Vector{Tuple{Symbol,Float64}}(undef, ne(network))
    norm_coef = maximum(conn_weights)
    for (ind, e) in enumerate(edges(network))
        if (e.src == e.dst)
            edge_col[ind] = (:black, 0.0)
            continue
        end
        edge_col[ind] = (:black, conn_weights[e.src] * e.weight / norm_coef)
    end

    # Rescale node size to be visible
    node_size = conn_weights ./ maximum(conn_weights) .* 10.0

    # Extract graph kwargs and set defaults
    edge_col = get(opts, :edge_color, edge_col)
    node_size = get(opts, :node_size, node_size)
    node_color = get(opts, :node_color, node_size)

    # Plot geodata polygons
    poly!(
        spatial,
        geodata;
        color=:white,
        strokecolor=(:black, 0.25),
        strokewidth=1.0
    )
    # Plot the connectivity graph
    graphplot!(
        spatial,
        network;
        layout=ADRIA.centroids(dom),
        edge_color=edge_col,
        node_size=node_size,
        node_color=node_color,
        edge_plottype=:linesegments
    )

    return g
end

"""
    _get_plottable_geom(gdf::DataFrame)::Union{Symbol, Bool}

Retrieve first column found to hold plottable geometries.

# Returns
Symbol, indicating column name or `false` if no geometries found.
"""
function _get_geom_col(gdf::DataFrame)::Union{Symbol,Bool}
    col = findall(typeof.(eachcol(gdf)) .<: Vector{<:AG.IGeometry})
    if !isempty(col)
        return Symbol(names(gdf)[col[1]])
    end

    return false
end

function _get_geoms(gdf::DataFrame)
    geom_col = _get_geom_col(gdf)
    return _get_geoms(gdf, geom_col)
end
function _get_geoms(gdf::DataFrame, geom_col::Symbol)
    return GeoMakie.geo2basic(AG.forceto.(gdf[!, geom_col], AG.wkbPolygon))
end
