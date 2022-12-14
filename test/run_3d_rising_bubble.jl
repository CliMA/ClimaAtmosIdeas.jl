using Test

using OrdinaryDiffEq: SSPRK33
using ClimaCorePlots, Plots
using UnPack

using ClimaCoreVTK
using ClimaCore: Geometry
using ClimaAtmos.Experimental.Utils.InitialConditions: init_3d_rising_bubble
using ClimaAtmos.Experimental.Domains
using ClimaAtmos.Experimental.BoundaryConditions
using ClimaAtmos.Experimental.Models
using ClimaAtmos.Experimental.Models.Nonhydrostatic3DModels
using ClimaAtmos.Experimental.Simulations

# Set up parameters
import ClimaAtmos
include(joinpath(pkgdir(ClimaAtmos), "parameters", "create_parameters.jl"))


function run_3d_rising_bubble(
    ::Type{FT};
    stepper = SSPRK33(),
    nelements = (5, 5, 10),
    npolynomial = 5,
    dt = 0.02,
    callbacks = (),
    test_mode = :regression,
) where {FT}

    # Bubble isn't rotating
    params = create_climaatmos_parameter_set(FT, (; Omega = 0.0))

    domain = HybridBox(
        FT,
        xlim = (-5e2, 5e2),
        ylim = (-5e2, 5e2),
        zlim = (0.0, 1e3),
        nelements = nelements,
        npolynomial = npolynomial,
    )

    model = Nonhydrostatic3DModel(
        domain = domain,
        boundary_conditions = nothing,
        parameters = params,
        moisture = EquilibriumMoisture(),
        hyperdiffusivity = FT(100),
    )
    model_eint = Nonhydrostatic3DModel(
        domain = domain,
        boundary_conditions = nothing,
        thermodynamics = InternalEnergy(),
        moisture = Dry(),
        parameters = params,
        hyperdiffusivity = FT(100),
    )
    model_pottemp = Nonhydrostatic3DModel(
        domain = domain,
        boundary_conditions = nothing,
        thermodynamics = PotentialTemperature(),
        parameters = params,
        hyperdiffusivity = FT(100),
    )

    # execute differently depending on testing mode
    if test_mode == :regression
        # Compares variables against current reference results. 
        # Compares conservation properties of prognostic variables. 
        # TODO: Upon reasonable time-to-solution increase test time to 700s.
        @testset "Regression: Potential Temperature Model" begin
            simulation =
                Simulation(model_pottemp, stepper, dt = dt, tspan = (0.0, 1.0))
            @test simulation isa Simulation

            @unpack ??, uh, w, ???? = init_3d_rising_bubble(
                FT,
                params,
                thermo_style = model_pottemp.thermodynamics,
                moist_style = model_pottemp.moisture,
            )
            set!(simulation, :base, ?? = ??, uh = uh, w = w)
            set!(simulation, :thermodynamics, ???? = ????)
            u = simulation.integrator.u
            ?????_0 = sum(u.base.??)
            ???????_0 = sum(u.thermodynamics.????)
            step!(simulation)
            u = simulation.integrator.u

            # Current ??
            current_min = 299.9999999523305
            current_max = 300.468563373248
            ?? = u.thermodynamics.???? ./ u.base.??

            @test minimum(parent(u.thermodynamics.???? ./ u.base.??)) ??? current_min atol =
                1e-2
            @test maximum(parent(u.thermodynamics.???? ./ u.base.??)) ??? current_max atol =
                1e-2
            u_end = simulation.integrator.u
            ?????_e = sum(u_end.base.??)
            ???????_e = sum(u_end.thermodynamics.????)
            ???? = (?????_e - ?????_0) ./ ?????_0 * 100
            ?????? = (???????_e - ???????_0) ./ ???????_0 * 100
            @test abs(????) < 1e-12
            @test abs(??????) < 1e-5
        end
        @testset "Regression: Total Energy Model" begin
            simulation = Simulation(model, stepper, dt = dt, tspan = (0.0, 1.0))
            @unpack ??, uh, w, ??e_tot, ??q_tot = init_3d_rising_bubble(
                FT,
                params,
                thermo_style = model.thermodynamics,
                moist_style = model.moisture,
            )
            set!(simulation, :base, ?? = ??, uh = uh, w = w)
            set!(simulation, :thermodynamics, ??e_tot = ??e_tot)
            set!(simulation, :moisture, ??q_tot = ??q_tot)
            u = simulation.integrator.u
            ?????_0 = sum(u.base.??)
            ?????e_tot_0 = sum(u.thermodynamics.??e_tot)
            ?????q_tot_0 = sum(u.moisture.??q_tot)

            step!(simulation)

            # Current ??e_tot
            current_min = 237082.14581933746
            current_max = 252441.54599695574

            u = simulation.integrator.u

            @test minimum(parent(u.thermodynamics.??e_tot)) ??? current_min atol =
                0.05
            @test maximum(parent(u.thermodynamics.??e_tot)) ??? current_max atol =
                0.05
            # perform regression check
            u = simulation.integrator.u
            ?????_e = sum(u.base.??)
            ?????e_tot_e = sum(u.thermodynamics.??e_tot)
            ?????q_tot_e = sum(u.moisture.??q_tot)
            ???? = (?????_e - ?????_0) ./ ?????_0 * 100
            ????e_tot = (?????e_tot_e - ?????e_tot_0) ./ ?????e_tot_0 * 100
            ????q_tot = (?????q_tot_e - ?????q_tot_0) ./ ?????q_tot_0 * 100
            if FT == Float32
                @test abs(????) < 3e-5
                @test abs(????e_tot) < 5e-5
                @test abs(????q_tot) < 1e-3
            else
                @test abs(????) < 1e-12
                @test abs(????e_tot) < 1e-5
                @test abs(????q_tot) < 1e-3
            end
        end
        @testset "Regression: Internal Energy Model" begin
            simulation =
                Simulation(model_eint, stepper, dt = dt, tspan = (0.0, 1.0))
            @unpack ??, uh, w, ??e_int = init_3d_rising_bubble(
                FT,
                params,
                thermo_style = model_eint.thermodynamics,
                moist_style = model_eint.moisture,
            )
            set!(simulation, :base, ?? = ??, uh = uh, w = w)
            set!(simulation, :thermodynamics, ??e_int = ??e_int)
            u = simulation.integrator.u
            ?????_0 = sum(u.base.??)
            ?????e_int_0 = sum(u.thermodynamics.??e_int)

            step!(simulation)

            # Current ??e_tot
            current_min = 226937.6900729421
            current_max = 251872.3101244288

            u = simulation.integrator.u

            @test minimum(parent(u.thermodynamics.??e_int)) ??? current_min atol =
                1e-1
            @test maximum(parent(u.thermodynamics.??e_int)) ??? current_max atol =
                1e-1

            # perform regression check
            u = simulation.integrator.u
            ?????_e = sum(u.base.??)
            ?????e_int_e = sum(u.thermodynamics.??e_int)
            ???? = (?????_e - ?????_0) ./ ?????_0 * 100
            ????e_int = (?????e_int_e - ?????e_int_0) ./ ?????e_int_0 * 100
            if FT == Float32
                @test abs(????) < 3e-5
                @test abs(????e_int) < 1.5e-5
            else
                @test abs(????) < 1e-12
                @test abs(????e_int) < 1e-5
            end
        end
    elseif test_mode == :validation
        # Produces VTK output plots for visual inspection of results
        # Periodic Output related to saveat kwarg issue below.

        # 1. sort out saveat kwarg for Simulation
        @testset "Validation: Potential Temperature Model" begin
            simulation =
                Simulation(model_pottemp, stepper, dt = dt, tspan = (0.0, 1.0))
            @unpack ??, uh, w, ???? = init_3d_rising_bubble(
                FT,
                params,
                thermo_style = model_pottemp.thermodynamics,
                moist_style = model_pottemp.moisture,
            )
            set!(simulation, :base, ?? = ??, uh = uh, w = w)
            set!(simulation, :thermodynamics, ???? = ????)

            # Initial values. Get domain integrated quantity
            u_start = simulation.integrator.u
            ?????_0 = sum(u_start.base.??)
            ???????_0 = sum(u_start.thermodynamics.????)
            run!(simulation)

            u_end = simulation.integrator.u

            ?????_e = sum(u_end.base.??)
            ???????_e = sum(u_end.thermodynamics.????)
            ???? = (?????_e - ?????_0) ./ ?????_0 * 100
            ?????? = (???????_e - ???????_0) ./ ???????_0 * 100

            ?? = u_end.thermodynamics.???? ./ u_end.base.??

            # post-processing
            # ENV["GKSwstype"] = "nul"
            # Plots.GRBackend()
            # # make output directory
            # path = joinpath(@__DIR__, "output_validation")
            # mkpath(path)
            # ClimaCoreVTK.writevtk(joinpath(path, "test"), ??)
            @test true # check is visual
        end
        # Total Energy Prognostic
        @testset "Validation: Total Energy Model" begin
            simulation = Simulation(model, stepper, dt = dt, tspan = (0.0, 1.0))
            @unpack ??, uh, w, ??e_tot, ??q_tot = init_3d_rising_bubble(
                FT,
                params,
                thermo_style = model.thermodynamics,
                moist_style = model.moisture,
            )
            set!(simulation, :base, ?? = ??, uh = uh, w = w)
            set!(simulation, :thermodynamics, ??e_tot = ??e_tot)
            set!(simulation, :moisture, ??q_tot = ??q_tot)

            # Initial values. Get domain integrated quantity
            u_start = simulation.integrator.u
            ?????_0 = sum(u_start.base.??)
            ?????etot_0 = sum(u_start.thermodynamics.??e_tot)
            ?????qtot_0 = sum(u_start.moisture.??q_tot)
            run!(simulation)

            u_end = simulation.integrator.u
            ?????_e = sum(u_end.base.??)
            ?????etot_e = sum(u_end.thermodynamics.??e_tot)
            ?????qtot_e = sum(u_end.moisture.??q_tot)
            ???? = (?????_e - ?????_0) ./ ?????_0 * 100
            ????etot = (?????etot_e - ?????etot_0) ./ ?????etot_0 * 100
            ????qtot = (?????qtot_e - ?????qtot_0) ./ ?????qtot_0 * 100
            println("Relative error at end of simulation:")
            println("???? = $???? %")
            println("????e_tot = $????etot %")
            println("????q_tot = $????qtot %")

            e_tot = u_end.thermodynamics.??e_tot ./ u_end.base.??

            # post-processing
            # ENV["GKSwstype"] = "nul"
            # Plots.GRBackend()
            # # make output directory
            # path = joinpath(@__DIR__, "output_validation")
            # mkpath(path)
            # ClimaCoreVTK.writevtk(joinpath(path, "test"), e_tot)
            # #TODO: Additional thermodynamics diagnostic vars
            @test true # check is visual
        end
    else
        throw(ArgumentError("$test_mode incompatible with test case."))
    end

    nothing
end

@testset "3D rising bubble" begin
    for FT in (Float32, Float64)
        run_3d_rising_bubble(FT)
    end
end
