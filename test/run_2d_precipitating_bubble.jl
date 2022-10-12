using Test

using OrdinaryDiffEq: SSPRK33, CallbackSet
using ClimaCorePlots, Plots
using UnPack
using DiffEqCallbacks

using ClimaAtmos.Experimental.Utils.InitialConditions:
    init_2d_precipitating_bubble
using ClimaAtmos.Experimental.Domains
using ClimaAtmos.Experimental.BoundaryConditions
using ClimaAtmos.Experimental.Models
using ClimaAtmos.Experimental.Models.Nonhydrostatic2DModels
using ClimaAtmos.Experimental.Callbacks
using ClimaAtmos.Experimental.Simulations

# Set up parameters
import ClimaAtmos
include(joinpath(pkgdir(ClimaAtmos), "parameters", "create_parameters.jl"))


"""
    PNGOutput{M, I} <: AbstractCallback

Specifies a `DiffEqCallbacks.PeriodicCallback` that
plots some of the state variables from the integrator
into a `.png` file.
"""
struct PNGOutput{M <: AbstractModel, I <: Number} <: AbstractCallback
    model::M
    filedir::String
    filename::String
    interval::I
end

function (F::PNGOutput)(integrator)
    state = integrator.u
    cache = integrator.p

    # Create directory
    mkpath(F.filedir)

    ENV["GKSwstype"] = "nul"
    Plots.GRBackend()

    foi = Plots.plot(state.base.ρ)
    Plots.png(
        foi,
        joinpath(F.filedir, F.filename * "_rho" * "_$(integrator.t)" * ".png"),
    )

    foi = Plots.plot(state.base.ρw)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_rho_w" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(state.base.ρuh)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_rho_uh" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(cache.microphysics_cache.q_liq)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_q_liq" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(cache.microphysics_cache.q_ice)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_q_ice" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(state.precipitation.ρq_rai)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_rho_q_rai" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(state.precipitation.ρq_sno)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_rho_q_sno" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(cache.Φ)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_e_pot" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(cache.K)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_e_kin" * "_$(integrator.t)" * ".png",
        ),
    )

    foi = Plots.plot(cache.e_int)
    Plots.png(
        foi,
        joinpath(
            F.filedir,
            F.filename * "_e_int" * "_$(integrator.t)" * ".png",
        ),
    )

    return nothing
end

function run_2d_precipitating_bubble(
    ::Type{FT};
    stepper = SSPRK33(),
    nelements = (10, 50),
    npolynomial = 4,
    dt = 0.02,
    callbacks = (),
    test_mode = :regression,
) where {FT}
    params = create_climaatmos_parameter_set(FT)

    domain = HybridPlane(
        FT,
        xlim = (-5e2, 5e2),
        zlim = (0.0, 1e3),
        nelements = nelements,
        npolynomial = npolynomial,
    )

    model = Nonhydrostatic2DModel(
        domain = domain,
        thermodynamics = TotalEnergy(),
        moisture = EquilibriumMoisture(),
        precipitation = OneMoment(),
        hyperdiffusivity = FT(100),
        boundary_conditions = nothing,
        parameters = params,
        cache = CacheOneMomentMicro(),
    )

    # execute differently depending on testing mode
    if test_mode == :regression
        # TODO!: run with input callbacks = ...
        cb_cfl = CFLAdaptive(model, 0.01, 1.0, false)
        cb = CallbackSet(generate_callback(cb_cfl))
        simulation = Simulation(
            model,
            stepper,
            dt = dt,
            tspan = (0.0, 1.0),
            callbacks = cb,
        )
        @test simulation isa Simulation

        # test error handling
        @test_throws ArgumentError set!(simulation, quack = 0.0)
        @test_throws ArgumentError set!(simulation, ρ = "quack")

        # test sim
        @unpack ρ, ρuh, ρw, ρe_tot, ρq_tot, ρq_rai, ρq_sno =
            init_2d_precipitating_bubble(FT, params, thermovar = :ρe_tot)
        set!(simulation, :base, ρ = ρ, ρuh = ρuh, ρw = ρw)
        set!(simulation, :thermodynamics, ρe_tot = ρe_tot)
        set!(simulation, :moisture, ρq_tot = ρq_tot)
        set!(simulation, :precipitation, ρq_rai = ρq_rai, ρq_sno = ρq_sno)

        # initial state
        u = simulation.integrator.u
        ∫ρ_0 = sum(u.base.ρ)
        ∫ρe_tot_0 = sum(u.thermodynamics.ρe_tot)
        ∫ρq_tot_0 = sum(u.moisture.ρq_tot)
        ∫ρq_rai_0 = sum(u.precipitation.ρq_rai)
        ∫ρq_sno_0 = sum(u.precipitation.ρq_sno)

        # 1 step
        step!(simulation)
        u_end = simulation.integrator.u
        ∫ρ_e = sum(u.base.ρ)
        ∫ρe_tot_e = sum(u.thermodynamics.ρe_tot)
        ∫ρq_tot_e = sum(u.moisture.ρq_tot)
        ∫ρq_rai_e = sum(u.precipitation.ρq_rai)
        ∫ρq_sno_e = sum(u.precipitation.ρq_sno)

        # perform regression check
        if FT == Float32
            current_min = 236496.28f0
            current_max = 253218.2f0
        elseif FT == Float64
            current_min = 236496.25933551634
            current_max = 253218.21414129983
        else
            error("Float type $FT not tested.")
        end

        @test minimum(parent(u_end.thermodynamics.ρe_tot)) ≈ current_min atol =
            0.05
        @test maximum(parent(u_end.thermodynamics.ρe_tot)) ≈ current_max atol =
            0.05

        # conservation check
        Δρ = (∫ρ_e - ∫ρ_0) ./ ∫ρ_0 * 100
        Δρe_tot = (∫ρe_tot_e - ∫ρe_tot_0) ./ ∫ρe_tot_0 * 100
        Δρq_tot = (∫ρq_tot_e - ∫ρq_tot_0) ./ ∫ρq_tot_0 * 100

        if FT == Float32
            @test abs(Δρ) < 3e-5
            @test abs(Δρe_tot) < 4e-5
            @test abs(Δρq_tot) < 1e-3
        else
            @test abs(Δρ) < 1e-12
            @test abs(Δρe_tot) < 1e-5
            @test abs(Δρq_tot) < 1e-3
        end

        # don't expect any precip to be produced in a short run
        @test ∫ρq_rai_0 ≈ ∫ρq_rai_e
        @test ∫ρq_sno_0 ≈ ∫ρq_sno_e
        @test ∫ρq_rai_e ≈ FT(0)
        @test ∫ρq_sno_e ≈ FT(0)

    elseif test_mode == :validation
        path = joinpath(@__DIR__, first(split(basename(@__FILE__), ".jl")))
        mkpath(path)

        # cb_jld2 = JLD2Output(model, path, "moist_bubble", dt)
        # cb_set = CallbackSet(generate_callback(cb_jld2))
        cb_png = PNGOutput(model, path, "plots_precipitating_bubble", 100)
        cb_set = CallbackSet(
            DiffEqCallbacks.PeriodicCallback(
                cb_png,
                cb_png.interval;
                initial_affect = true,
            ),
        )

        simulation = Simulation(
            model,
            stepper,
            dt = dt,
            tspan = (0.0, 500.0),
            callbacks = cb_set,
        )
        @unpack ρ, ρuh, ρw, ρe_tot, ρq_tot, ρq_rai, ρq_sno =
            init_2d_precipitating_bubble(FT, params, thermovar = :ρe_tot)
        set!(simulation, :base, ρ = ρ, ρuh = ρuh, ρw = ρw)
        set!(simulation, :thermodynamics, ρe_tot = ρe_tot)
        set!(simulation, :moisture, ρq_tot = ρq_tot)
        set!(simulation, :precipitation, ρq_rai = ρq_rai, ρq_sno = ρq_sno)
        run!(simulation)

        @test true # check is visual
    else
        throw(ArgumentError("$test_mode incompatible with test case."))
    end

    nothing
end

@testset "2D precipitating bubble" begin
    for FT in (Float32, Float64)
        run_2d_precipitating_bubble(FT)
    end
end
#run_2d_precipitating_bubble(Float32, test_mode = :validation)
