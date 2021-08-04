mutable struct DMDA{PetscLib} <: AbstractDM{PetscLib}
    ptr::CDM
    opts::Options{PetscLib}
end

"""
    DMDACreate1d(
        petsclib::PetscLib
        comm::MPI.Comm,
        boundary_type::NTuple{1, DMBoundaryType},
        global_dim::NTuple{1, Integer},
        dof_per_node::Integer,
        stencil_width::Integer;
        points_per_proc::Tuple = (nothing,),
        dmsetfromoptions = true,
        dmsetup = true,
        options...
    )

Creates a 1-D distributed array with the options specified using keyword
arguments.

If keyword argument `points_per_proc[1] isa Vector{petsclib.PetscInt}` then this
specifies the points per processor; `length(points_per_proc[1])` should equal
`MPI.Comm_size(comm)`.

If keyword argument `dmsetfromoptions == true` then `setfromoptions!` called.

If keyword argument `dmsetup == true` then `setup!` is called.

# External Links
$(_doc_external("DMDA/DMDACreate1d"))
"""
function DMDA(
    petsclib::PetscLib,
    comm::MPI.Comm,
    boundary_type::NTuple{1, DMBoundaryType},
    global_dim::NTuple{1, Integer},
    dof_per_node::Integer,
    stencil_width::Integer;
    points_per_proc::Tuple = (nothing,),
    dmsetfromoptions = true,
    dmsetup = true,
    options...,
) where {PetscLib}
    opts = Options(petsclib; options...)
    da = DMDA{PetscLib}(C_NULL, opts)

    @assert length(points_per_proc) == 1

    ref_points_per_proc =
        if isnothing(points_per_proc[1]) || points_per_proc[1] == PETSC_DECIDE
            C_NULL
        else
            @assert points_per_proc[1] isa Array{PetscLib.PetscInt}
            @assert length(points_per_proc[1]) == MPI.Comm_size(comm)
            points_per_proc[1]
        end

    with(da.opts) do
        LibPETSc.DMDACreate1d(
            PetscLib,
            comm,
            boundary_type[1],
            global_dim[1],
            dof_per_node,
            stencil_width,
            ref_points_per_proc,
            da,
        )
    end
    dmsetfromoptions && setfromoptions!(da)
    dmsetup && setup!(da)

    # We can only let the garbage collect finalize when we do not need to
    # worry about MPI (since garbage collection is asyncronous)
    if MPI.Comm_size(comm) == 1
        finalizer(destroy, da)
    end
    return da
end

"""
    getinfo(da::DMDA)

Get the info associated with the distributed array `da`. Returns `V` which has
fields

 - `dim`
 - `global_size` (`Tuple` of length 3)
 - `procs_per_dim` (`Tuple` of length 3)
 - `dof_per_node`
 - `boundary_type` (`Tuple` of length 3)
 - `stencil_width`
 - `stencil_type`

# External Links
$(_doc_external("DMDA/DMDAGetInfo"))
"""
function getinfo(da::DMDA{PetscLib}) where {PetscLib}
    PetscInt = PetscLib.PetscInt

    dim = [PetscInt(0)]
    glo_size = [PetscInt(0), PetscInt(0), PetscInt(0)]
    procs_per_dim = [PetscInt(0), PetscInt(0), PetscInt(0)]
    dof_per_node = [PetscInt(0)]
    stencil_width = [PetscInt(0)]
    boundary_type = [DM_BOUNDARY_NONE, DM_BOUNDARY_NONE, DM_BOUNDARY_NONE]
    stencil_type = [DMDA_STENCIL_STAR]

    LibPETSc.DMDAGetInfo(
        PetscLib,
        da,
        dim,
        Ref(glo_size, 1),
        Ref(glo_size, 2),
        Ref(glo_size, 3),
        Ref(procs_per_dim, 1),
        Ref(procs_per_dim, 2),
        Ref(procs_per_dim, 3),
        dof_per_node,
        stencil_width,
        Ref(boundary_type, 1),
        Ref(boundary_type, 2),
        Ref(boundary_type, 3),
        stencil_type,
    )

    return (
        dim = dim[1],
        global_size = (glo_size...,),
        procs_per_dim = (procs_per_dim...,),
        dof_per_node = dof_per_node[1],
        boundary_type = (boundary_type...,),
        stencil_width = stencil_width[1],
        stencil_type = stencil_type[1],
    )
end

"""
    getcorners(da::DMDA)

Returns a `NamedTuple` with the global indices (excluding ghost points) of the
`lower` and `upper` corners as well as the `size`.

# External Links
$(_doc_external("DMDA/DMDAGetCorners"))
"""
function getcorners(da::DMDA{PetscLib}) where {PetscLib}
    PetscInt = PetscLib.PetscInt
    corners = [PetscInt(0), PetscInt(0), PetscInt(0)]
    local_size = [PetscInt(0), PetscInt(0), PetscInt(0)]
    LibPETSc.DMDAGetCorners(
        PetscLib,
        da,
        Ref(corners, 1),
        Ref(corners, 2),
        Ref(corners, 3),
        Ref(local_size, 1),
        Ref(local_size, 2),
        Ref(local_size, 3),
    )
    corners .+= 1
    upper = corners .+ local_size .- PetscInt(1)
    return (lower = (corners...,), upper = (upper...,), size = (local_size...,))
end

"""
    getghostcorners(da::DMDA)

Returns a `NamedTuple` with the global indices (including ghost points) of the
`lower` and `upper` corners as well as the `size`.

# External Links
$(_doc_external("DMDA/DMDAGetGhostCorners"))
"""
function getghostcorners(da::DMDA{PetscLib}) where {PetscLib}
    PetscInt = PetscLib.PetscInt
    corners = [PetscInt(0), PetscInt(0), PetscInt(0)]
    local_size = [PetscInt(0), PetscInt(0), PetscInt(0)]
    LibPETSc.DMDAGetGhostCorners(
        PetscLib,
        da,
        Ref(corners, 1),
        Ref(corners, 2),
        Ref(corners, 3),
        Ref(local_size, 1),
        Ref(local_size, 2),
        Ref(local_size, 3),
    )
    corners .+= 1
    upper = corners .+ local_size .- PetscInt(1)
    return (lower = (corners...,), upper = (upper...,), size = (local_size...,))
end

#=
#
# OLD WRAPPERS
#
mutable struct DMDALocalInfo{IT}
    dim::IT
    dof_per_node::IT
    stencil_width::IT
    global_size::NTuple{3, IT}
    local_start::NTuple{3, IT}
    local_size::NTuple{3, IT}
    ghosted_local_start::NTuple{3, IT}
    ghosted_local_size::NTuple{3, IT}
    boundary_type::NTuple{3, DMBoundaryType}
    stencil_type::DMDAStencilType
    ___padding___::NTuple{5, IT}
    DMDALocalInfo{IT}() where {IT} = new{IT}()
end

mutable struct DMDA{PetscLib} <: AbstractDM{PetscLib}
    ptr::CDM
    opts::Options{PetscLib}
    DMDA{PetscLib}(ptr, opts = Options(PetscLib)) where {PetscLib} =
        new{PetscLib}(ptr, opts)
end

"""
    empty(da::DMDA)

return an uninitialized `DMDA` struct.
"""
Base.empty(::DMDA{PetscLib}) where {PetscLib} = DMDA{PetscLib}(C_NULL)

"""
    DMDACreate2d(
        ::PetscLib
        comm::MPI.Comm,
        boundary_type_x::DMBoundaryType,
        boundary_type_y::DMBoundaryType,
        stencil_type::DMDAStencilType,
        global_dim_x,
        global_dim_y,
        procs_x,
        procs_y,
        dof_per_node,
        stencil_width,
        points_per_proc_x::Union{Nothing, Vector{PetscInt}};
        points_per_proc_y::Union{Nothing, Vector{PetscInt}};
        dmsetfromoptions=true,
        dmsetup=true,
        options...
    )

Creates a 2-D distributed array with the options specified using keyword
arguments.

If keyword argument `dmsetfromoptions == true` then `setfromoptions!` called.
If keyword argument `dmsetup == true` then `setup!` is called.

# External Links
$(_doc_external("DMDA/DMDACreate2d"))
"""
function DMDACreate2d end

@for_petsc function DMDACreate2d(
    ::$UnionPetscLib,
    comm::MPI.Comm,
    boundary_type_x::DMBoundaryType,
    boundary_type_y::DMBoundaryType,
    stencil_type::DMDAStencilType,
    global_dim_x,
    global_dim_y,
    procs_x,
    procs_y,
    dof_per_node,
    stencil_width,
    points_per_proc_x::Union{Nothing, Vector{$PetscInt}},
    points_per_proc_y::Union{Nothing, Vector{$PetscInt}};
    dmsetfromoptions = true,
    dmsetup = true,
    options...,
)
    opts = Options($petsclib, options...)
    ref_points_per_proc_x = if isnothing(points_per_proc_x)
        C_NULL
    else
        @assert length(points_per_proc_x) == procs_x
        points_per_proc_x
    end
    ref_points_per_proc_y = if isnothing(points_per_proc_y)
        C_NULL
    else
        @assert length(points_per_proc_y) == procs_y
        points_per_proc_y
    end
    da = DMDA{$PetscLib}(C_NULL, opts)
    with(da.opts) do
        @chk ccall(
            (:DMDACreate2d, $petsc_library),
            PetscErrorCode,
            (
                MPI.MPI_Comm,
                DMBoundaryType,
                DMBoundaryType,
                DMDAStencilType,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                Ptr{$PetscInt},
                Ptr{$PetscInt},
                Ptr{CDM},
            ),
            comm,
            boundary_type_x,
            boundary_type_y,
            stencil_type,
            global_dim_x,
            global_dim_y,
            procs_x,
            procs_y,
            dof_per_node,
            stencil_width,
            ref_points_per_proc_x,
            ref_points_per_proc_y,
            da,
        )
    end
    dmsetfromoptions && setfromoptions!(da)
    dmsetup && setup!(da)
    # We can only let the garbage collect finalize when we do not need to
    # worry about MPI (since garbage collection is asyncronous)
    if comm == MPI.COMM_SELF
        finalizer(destroy, da)
    end
    return da
end

"""
    DMDACreate3d(
        ::PetscLib
        comm::MPI.Comm,
        boundary_type_x::DMBoundaryType,
        boundary_type_y::DMBoundaryType,
        boundary_type_z::DMBoundaryType,
        stencil_type::DMDAStencilType,
        global_dim_x,
        global_dim_y,
        global_dim_z,
        procs_x,
        procs_y,
        procs_z,
        global_dim_z,
        dof_per_node,
        stencil_width,
        points_per_proc_x::Union{Nothing, Vector{PetscInt}};
        points_per_proc_y::Union{Nothing, Vector{PetscInt}};
        points_per_proc_z::Union{Nothing, Vector{PetscInt}};
        dmsetfromoptions=true,
        dmsetup=true,
        options...
    )

Creates a 3-D distributed array with the options specified using keyword
arguments.

If keyword argument `dmsetfromoptions == true` then `setfromoptions!` called.
If keyword argument `dmsetup == true` then `setup!` is called.

# External Links
$(_doc_external("DMDA/DMDACreate3d"))
"""
function DMDACreate3d end

@for_petsc function DMDACreate3d(
    ::$UnionPetscLib,
    comm::MPI.Comm,
    boundary_type_x::DMBoundaryType,
    boundary_type_y::DMBoundaryType,
    boundary_type_z::DMBoundaryType,
    stencil_type::DMDAStencilType,
    global_dim_x,
    global_dim_y,
    global_dim_z,
    procs_x,
    procs_y,
    procs_z,
    dof_per_node,
    stencil_width,
    points_per_proc_x::Union{Nothing, Vector{$PetscInt}},
    points_per_proc_y::Union{Nothing, Vector{$PetscInt}},
    points_per_proc_z::Union{Nothing, Vector{$PetscInt}};
    dmsetfromoptions = true,
    dmsetup = true,
    options...,
)
    opts = Options($petsclib, options...)
    ref_points_per_proc_x = if isnothing(points_per_proc_x)
        C_NULL
    else
        @assert length(points_per_proc_x) == procs_x
        points_per_proc_x
    end
    ref_points_per_proc_y = if isnothing(points_per_proc_y)
        C_NULL
    else
        @assert length(points_per_proc_y) == procs_y
        points_per_proc_y
    end
    ref_points_per_proc_z = if isnothing(points_per_proc_z)
        C_NULL
    else
        @assert length(points_per_proc_z) == procs_z
        points_per_proc_z
    end
    da = DMDA{$PetscLib}(C_NULL, opts)
    with(da.opts) do
        @chk ccall(
            (:DMDACreate3d, $petsc_library),
            PetscErrorCode,
            (
                MPI.MPI_Comm,
                DMBoundaryType,
                DMBoundaryType,
                DMBoundaryType,
                DMDAStencilType,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                $PetscInt,
                Ptr{$PetscInt},
                Ptr{$PetscInt},
                Ptr{$PetscInt},
                Ptr{CDM},
            ),
            comm,
            boundary_type_x,
            boundary_type_y,
            boundary_type_z,
            stencil_type,
            global_dim_x,
            global_dim_y,
            global_dim_z,
            procs_x,
            procs_y,
            procs_z,
            dof_per_node,
            stencil_width,
            ref_points_per_proc_x,
            ref_points_per_proc_y,
            ref_points_per_proc_z,
            da,
        )
    end
    dmsetfromoptions && setfromoptions!(da)
    dmsetup && setup!(da)
    # We can only let the garbage collect finalize when we do not need to
    # worry about MPI (since garbage collection is asyncronous)
    if comm == MPI.COMM_SELF
        finalizer(destroy, da)
    end
    return da
end

"""
    setuniformcoordinates!(
        da::DMDA
        xyzmin::NTuple{N, Real},
        xyzmax::NTuple{N, Real},
    ) where {N}

Set uniform coordinates for the `da` using the lower and upper corners defined
by the `NTuple`s `xyzmin` and `xyzmax`. If `N` is less than the dimension of the
`da` then the value of the trailing coordinates is set to `0`.

# External Links
$(_doc_external("DMDA/DMDASetUniformCoordinates"))
"""
function setuniformcoordinates! end

@for_petsc function setuniformcoordinates!(
    da::DMDA{$PetscLib},
    xyzmin::NTuple{N, Real},
    xyzmax::NTuple{N, Real},
) where {N}
    xmin = $PetscReal(xyzmin[1])
    xmax = $PetscReal(xyzmax[1])

    ymin = (N > 1) ? $PetscReal(xyzmin[2]) : $PetscReal(0)
    ymax = (N > 1) ? $PetscReal(xyzmax[2]) : $PetscReal(0)

    zmin = (N > 2) ? $PetscReal(xyzmin[3]) : $PetscReal(0)
    zmax = (N > 2) ? $PetscReal(xyzmax[3]) : $PetscReal(0)

    @chk ccall(
        (:DMDASetUniformCoordinates, $petsc_library),
        PetscErrorCode,
        (
            CDM,
            $PetscReal,
            $PetscReal,
            $PetscReal,
            $PetscReal,
            $PetscReal,
            $PetscReal,
        ),
        da,
        xmin,
        xmax,
        ymin,
        ymax,
        zmin,
        zmax,
    )
    return nothing
end
=#
