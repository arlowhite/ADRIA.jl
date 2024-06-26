# Loading a Domain

ADRIA is designed to work with `Domain` data packages.

At their core, data packages are a directory containing a `datapackage.json` file,
following the [spec](https://specs.frictionlessdata.io/data-package/) as
outlined by Frictionless Data. In short, these are pre-packaged data sets that hold all the
necessary data to run simulations for a given spatial domain.

See [Architectural overview](@ref) for more information.

A `Domain` may be loaded by calling the `load_domain` function with the path to the data
package. Note that the data package is the *directory*.

By convention we assign the `Domain` to `dom`, although this variable can be named anything.

```julia
dom = ADRIA.load_domain("path to domain data package")
```

ReefMod Engine datasets can also be used to run ADRIAmod simulations for the Great Barrier
Reef.

```julia
dom = ADRIA.load_domain(RMEDomain, "path to ReefModEngine dataset", "45")
```

Note that at the moment the target RCP has to be specified.

ReefMod Matlab datasets that have been converted to NetCDF files can also be used to run
ADRIAmod simulation for the Great Barrier Reef.
```julia
dom = ADRIA.load_domain(ReefModDomain, "path to ReefMod dataset", "45")
```

The target RCP must also be specified.
