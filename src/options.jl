const CPetscOptions = Ptr{Cvoid}

"""
    AbstractOptions{PetscLib <: PetscLibType}

Abstract type of PETSc solver options.
"""
abstract type AbstractOptions{PetscLib <: PetscLibType} end

"""
    GlobalOptions{PetscLib <: PetscLibType}

The PETSc global options database.
"""
struct GlobalOptions{PetscLib} <: AbstractOptions{PetscLib} end
Base.cconvert(::Type{CPetscOptions}, obj::GlobalOptions) = C_NULL
GlobalOptions(::PetscLib) where PetscLib = GlobalOptions{PetscLib}()


"""
    Options{PetscLib <: PetscLibType}(kw -> arg, ...)
    Options(petsclib, kw -> arg, ...)

Create a PETSc options data structure for the `petsclib`.

For construction a set of keyword argment pairs should be given. If the option
has no value it should be set to `nothing` or `true`. Setting an option to
`false` will cause the option not to be set on the PETSc options table.

# Examples
```julia-repl
julia> using PETSc

julia> petsclib = PETSc.petsclibs[1];

julia> PETSc.initialize(petsclib)

julia> opt = PETSc.Options(
                         petsclib,
                         ksp_monitor = nothing,
                         ksp_view = true,
                         pc_type = "mg",
                         pc_mg_levels = 1,
                         false_opt = false,
                     )
#PETSc Option Table entries:
-ksp_monitor
-ksp_view
-pc_mg_levels 1
-pc_type mg
#End of PETSc Option Table entries


julia> opt["ksp_monitor"]
""

julia> opt["pc_type"]
"mg"

julia> opt["pc_type"] = "ilu"
"ilu"

julia> opt["pc_type"]
"ilu"

julia> opt["false_opt"]
ERROR: KeyError: key "bad_key" not found

julia> opt["bad_key"]
ERROR: KeyError: key "bad_key" not found
```

# External Links
$(_doc_external("Sys/PetscOptionsCreate"))
"""
mutable struct Options{T} <: AbstractOptions{T}
    ptr::CPetscOptions
end

function Options_(petsclib::PetscLibType)
  @assert initialized(petsclib)
  PetscLib = typeof(petsclib)
  opts = Options{PetscLib}(C_NULL)
  LibPETSc.PetscOptionsCreate(petsclib, opts)
  finalizer(x->LibPETSc.PetscOptionsDestroy(PetscLib, x), opts)
  return opts
end

Options(petsclib::PetscLibType; kwargs...) = Options_(petsclib, kwargs...)
Options(PetscLib::Type{<:PetscLibType}; kwargs...) = Options_(getlib(PetscLib), kwargs...)
function Options_(petsclib::PetscLibType, ps::Pair...)
    opts = Options_(petsclib)
    for (k, v) in ps
        opts[k] = v
    end
    return opts
end

function Base.push!(
    ::GlobalOptions{PetscLib},
    opts::Options{PetscLib},
) where PetscLib
    LibPETSc.PetscOptionsPush(PetscLib, opts)
    return nothing
end

function Base.pop!(::GlobalOptions{PetscLib}) where PetscLib
    LibPETSc.PetscOptionsPop(PetscLib)
    return nothing
end

function Base.setindex!(opts::AbstractOptions{PetscLib}, val, key) where PetscLib
    val === true && (val = nothing)
    val === false && (return val)

    LibPETSc.PetscOptionsSetValue(PetscLib,
                                  opts,
                                  string('-', key),
                                  isnothing(val) ? C_NULL : string(val))

    return val
end

function Base.getindex(opts::AbstractOptions{PetscLib}, key) where PetscLib
    val = Vector{UInt8}(undef, 256)
    set_ref = Ref{PetscBool}()
    LibPETSc.PetscOptionsGetString(PetscLib,
        opts,
        C_NULL,
        string('-', key),
        val,
        sizeof(val),
        set_ref,
    )
    val = GC.@preserve val unsafe_string(pointer(val))
    set_ref[] == PETSC_TRUE || throw(KeyError(key))
    return val
end

function view(
    opts::AbstractOptions{PetscLib},
    viewer = LibPETSc.PETSC_VIEWER_STDOUT_(PetscLib, MPI.COMM_SELF)
) where PetscLib
    LibPETSc.PetscOptionsView(PetscLib, opts, viewer)
    return nothing
end

Base.show(io::IO, opts::AbstractOptions) = _show(io, opts)

"""
    with(f, opts::Options)

Call `f()` with the [`Options`](@ref) `opts` set temporarily (in addition to any
global options).
"""
function with(f, opts::Options{PetscLib}) where {PetscLib}
    global_opts = GlobalOptions{PetscLib}()
    push!(global_opts, opts)
    try
        f()
    finally
        pop!(global_opts)
    end
end

"""
    parse_options(args::Vector{String})

Parse the `args` vector into a `NamedTuple` that can be used as the options for
the PETSc solvers.

```sh
julia --project file.jl -ksp_monitor -pc_type mg -ksp_view
```
"""
function parse_options(args::Vector{String})
    i = 1
    opts = Dict{Symbol, Union{String, Nothing}}()
    while i <= length(args)
        @assert args[i][1] == '-' && length(args[i]) > 1
        if i == length(args) || args[i + 1][1] == '-'
            opts[Symbol(args[i][2:end])] = nothing
            i = i + 1
        else
            opts[Symbol(args[i][2:end])] = args[i + 1]
            i = i + 2
        end
    end
    return NamedTuple(opts)
end
