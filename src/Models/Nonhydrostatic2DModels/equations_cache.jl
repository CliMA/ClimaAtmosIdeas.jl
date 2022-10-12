const CM0M = CloudMicrophysics.Microphysics0M
const CM1M = CloudMicrophysics.Microphysics1M
const CMCT = CloudMicrophysics.CommonTypes

@inline function precompute_Microphysics0M(ρq_tot, ρ, e_int, Φ, params)

    thermo_params = CAP.thermodynamics_params(params)
    cm_params = CAP.microphysics_params(params)
    # saturation adjustment
    q_tot = ρq_tot / ρ
    ts = TD.PhaseEquil_ρeq(thermo_params, ρ, e_int, q_tot)
    q = TD.PhasePartition(thermo_params, ts)
    λ = TD.liquid_fraction(thermo_params, ts)
    I_l = TD.internal_energy_liquid(thermo_params, ts)
    I_i = TD.internal_energy_ice(thermo_params, ts)

    # precipitation removal source terms
    # (cached to avoid re-computing many times per time step)
    S_q_tot = CM0M.remove_precipitation(cm_params, q)
    S_e_tot = (λ * I_l + (1 - λ) * I_i + Φ) * S_q_tot

    # temporarily dumping q.liq and q.ice into cache
    # for a quick way to visualise them in tests
    q_liq = q.liq
    q_ice = q.ice

    return (; S_q_tot, S_e_tot, q_liq, q_ice)
end

@inline function precompute_Microphysics1M(
    ρq_tot,
    ρq_rai,
    ρq_sno,
    ρ,
    e_int,
    Φ,
    params,
)
    thermo_params = CAP.thermodynamics_params(params)
    cm_params = CAP.microphysics_params(params)

    FT = eltype(ρ)

    q_rai = ρq_rai / ρ
    q_sno = ρq_sno / ρ

    # saturation adjustment
    q_tot = ρq_tot / ρ
    ts = TD.PhaseEquil_ρeq(thermo_params, ρ, e_int, q_tot)

    q = TD.PhasePartition(thermo_params, ts)
    T = TD.air_temperature(thermo_params, ts)
    λ = TD.liquid_fraction(thermo_params, ts)
    I_d = TD.internal_energy_dry(thermo_params, ts)
    I_v = TD.internal_energy_vapor(thermo_params, ts)
    I_l = TD.internal_energy_liquid(thermo_params, ts)
    I_i = TD.internal_energy_ice(thermo_params, ts)
    L_f = TD.latent_heat_fusion(thermo_params, ts)

    _T_freeze = CAP.T_freeze(params)
    _cv_l = CAP.cv_l(params)

    # temporary vars for summimng different microphysics source terms
    S_q_rai::FT = FT(0)
    S_q_sno::FT = FT(0)
    S_q_tot::FT = FT(0)
    S_e_tot::FT = FT(0)

    # source of rain via autoconversion
    tmp = CM1M.conv_q_liq_to_q_rai(cm_params, q.liq)
    S_q_rai += tmp
    #S_ql -= tmp
    S_e_tot -= tmp * (I_l + Φ)

    # source of snow via autoconversion
    tmp = CM1M.conv_q_ice_to_q_sno_no_supersat(cm_params, q.ice)
    S_q_sno += tmp
    #S_qi -= tmp
    S_e_tot -= tmp * (I_i + Φ)

    # source of rain water via accretion cloud water - rain
    tmp = CM1M.accretion(
        cm_params,
        CMCT.LiquidType(),
        CMCT.RainType(),
        q.liq,
        q_rai,
        ρ,
    )
    S_q_rai += tmp
    #S_ql -= tmp
    S_e_tot -= tmp * (I_l + Φ)

    # source of snow via accretion cloud ice - snow
    tmp = CM1M.accretion(
        cm_params,
        CMCT.IceType(),
        CMCT.SnowType(),
        q.ice,
        q_sno,
        ρ,
    )
    S_q_sno += tmp
    #S_qi -= tmp
    S_e_tot -= tmp * (I_i + Φ)

    # sink of cloud water via accretion cloud water - snow
    tmp = CM1M.accretion(
        cm_params,
        CMCT.LiquidType(),
        CMCT.SnowType(),
        q.liq,
        q_sno,
        ρ,
    )
    if T < _T_freeze # cloud droplets freeze to become snow)
        S_q_sno += tmp
        #S_ql -= tmp
        S_e_tot -= tmp * (I_i + Φ)
    else # snow melts, both cloud water and snow become rain
        α = _cv_l / L_f * (T - _T_freeze)
        #S_ql -= tmp
        S_q_sno -= tmp * α
        S_q_rai += tmp * (1 + α)
        S_e_tot -= tmp * ((1 + α) * I_l - α * I_i + Φ)
    end

    # sink of cloud ice via accretion cloud ice - rain
    tmp1 = CM1M.accretion(
        cm_params,
        CMCT.IceType(),
        CMCT.RainType(),
        q.ice,
        q_rai,
        ρ,
    )
    # sink of rain via accretion cloud ice - rain
    tmp2 = CM1M.accretion_rain_sink(cm_params, q.ice, q_rai, ρ)
    #S_qi -= tmp1
    S_e_tot -= tmp1 * (I_i + Φ)
    S_q_rai -= tmp2
    S_e_tot += tmp2 * L_f
    S_q_sno += tmp1 + tmp2

    # accretion rain - snow
    if T < _T_freeze
        tmp = CM1M.accretion_snow_rain(
            cm_params,
            CMCT.SnowType(),
            CMCT.RainType(),
            q_sno,
            q_rai,
            ρ,
        )
        S_q_sno += tmp
        S_q_rai -= tmp
        S_e_tot += tmp * L_f
    else
        tmp = CM1M.accretion_snow_rain(
            cm_params,
            CMCT.RainType(),
            CMCT.SnowType(),
            q_rai,
            q_sno,
            ρ,
        )
        S_q_sno -= tmp
        S_q_rai += tmp
        S_e_tot -= tmp * L_f
    end

    # rain evaporation sink (it already has negative sign for evaporation)
    tmp =
        CM1M.evaporation_sublimation(cm_params, CMCT.RainType(), q, q_rai, ρ, T)
    S_q_rai += tmp
    S_e_tot -= tmp * (I_l + Φ)

    # snow sublimation/deposition source/sink
    tmp =
        CM1M.evaporation_sublimation(cm_params, CMCT.SnowType(), q, q_sno, ρ, T)
    S_q_sno += tmp
    S_e_tot -= tmp * (I_i + Φ)

    # snow melt
    tmp = CM1M.snow_melt(cm_params, q_sno, ρ, T)
    S_q_sno -= tmp
    S_q_rai += tmp
    S_e_tot -= tmp * L_f

    # total qt sink is the sum of precip sources
    S_q_tot = -S_q_rai - S_q_sno

    # temporarily dumping q.liq and q.ice into cache
    # for a quick way to visualise them in tests
    q_liq = q.liq
    q_ice = q.ice

    return (; S_q_tot, S_e_tot, S_q_rai, S_q_sno, q_liq, q_ice)
end

@inline function precompute_cache!(dY, Y, Ya, _...)
    error("not implemented for this model configuration.")
end

@inline function precompute_cache!(
    dY,
    Y,
    Ya,
    ::PotentialTemperature,
    ::Dry,
    ::NoPrecipitation,
    params,
    FT,
)
    thermo_params = CAP.thermodynamics_params(params)
    ρ = Y.base.ρ
    ρθ = Y.thermodynamics.ρθ

    z = Fields.coordinate_field(axes(ρ)).z
    g::FT = CAP.grav(params)

    # update cached gravitational potential (TODO - should be done only once)
    @. Ya.Φ = g * z
    # TODO: save ts into cache
    @. Ya.p =
        TD.air_pressure(thermo_params, TD.PhaseDry_ρθ(thermo_params, ρ, ρθ / ρ))
end

@inline function precompute_cache!(
    dY,
    Y,
    Ya,
    ::TotalEnergy,
    ::EquilibriumMoisture,
    ::PrecipitationRemoval,
    params,
    FT,
)
    # unpack state variables
    ρ = Y.base.ρ
    ρe_tot = Y.thermodynamics.ρe_tot
    ρq_tot = Y.moisture.ρq_tot
    thermo_params = CAP.thermodynamics_params(params)
    cm_params = CAP.microphysics_params(params)

    z = Fields.coordinate_field(axes(ρ)).z
    g::FT = CAP.grav(params)

    cρuₕ = Y.base.ρuh # Covariant12Vector on centers
    fρw = Y.base.ρw # Covariant3Vector on faces
    If2c = Operators.InterpolateF2C()
    cuvw =
        Geometry.Covariant123Vector.(cρuₕ ./ ρ) .+
        Geometry.Covariant123Vector.(If2c.(fρw) ./ ρ)

    # update cached gravitational potential (TODO - should be done only once)
    @. Ya.Φ = g * z
    # update cached kinetic energy
    @. Ya.K = norm_sqr(cuvw) / 2
    # update cached internal energy
    @. Ya.e_int = ρe_tot / ρ - Ya.Φ - Ya.K

    # update cached pressure
    @. Ya.p = TD.air_pressure(
        thermo_params,
        TD.PhaseEquil_ρeq(thermo_params, ρ, Ya.e_int, ρq_tot / ρ),
    )

    # update cached microphysics helper variables
    @. Ya.microphysics_cache =
        precompute_Microphysics0M(ρq_tot, ρ, Ya.e_int, Ya.Φ, params)
end

@inline function precompute_cache!(
    dY,
    Y,
    Ya,
    ::TotalEnergy,
    ::EquilibriumMoisture,
    ::OneMoment,
    params,
    FT,
)
    thermo_params = CAP.thermodynamics_params(params)
    # unpack state variables
    ρ = Y.base.ρ
    ρe_tot = Y.thermodynamics.ρe_tot
    ρq_tot = Y.moisture.ρq_tot
    ρq_rai = Y.precipitation.ρq_rai
    ρq_sno = Y.precipitation.ρq_sno

    z = Fields.coordinate_field(axes(ρ)).z
    g::FT = CAP.grav(params)

    cρuₕ = Y.base.ρuh # Covariant12Vector on centers
    fρw = Y.base.ρw # Covariant3Vector on faces
    If2c = Operators.InterpolateF2C()
    cuvw =
        Geometry.Covariant123Vector.(cρuₕ ./ ρ) .+
        Geometry.Covariant123Vector.(If2c.(fρw) ./ ρ)

    # update cached gravitational potential (TODO - should be done only once)
    @. Ya.Φ = g * z
    # update cached kinetic energy
    @. Ya.K = norm_sqr(cuvw) / 2
    # update cached internal energy
    @. Ya.e_int = ρe_tot / ρ - Ya.Φ - Ya.K

    # update cached pressure
    @. Ya.p = TD.air_pressure(
        thermo_params,
        TD.PhaseEquil_ρeq(thermo_params, ρ, Ya.e_int, ρq_tot / ρ),
    )

    # update cached microphysics helper variables
    @. Ya.microphysics_cache = precompute_Microphysics1M(
        ρq_tot,
        ρq_rai,
        ρq_sno,
        ρ,
        Ya.e_int,
        Ya.Φ,
        params,
    )
end
