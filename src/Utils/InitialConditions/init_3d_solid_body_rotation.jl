"""
    init_solid_body_rotation(FT, params)

    Hydrostatically balanced initial condition for 3D sphere benchmarking.
"""
function init_3d_solid_body_rotation(::Type{FT}, params) where {FT}
    # physics parameters
    p_0::FT = CAP.MSLP(params)
    cv_d::FT = CAP.cv_d(params)
    R_d::FT = CAP.R_d(params)
    T_tri::FT = CAP.T_triple(params)
    g::FT = CAP.grav(params)

    # initial condition specific parameters
    T_0::FT = 300.0
    H::FT = R_d * T_0 / g # scale height

    # auxiliary functions
    p(z) = p_0 * exp(-z / H)

    # density
    function ρ(local_geometry)
        @unpack z = local_geometry.coordinates
        return FT(p(z) / R_d / T_0)
    end

    # total energy density
    function ρe_tot(local_geometry)
        @unpack z = local_geometry.coordinates
        Φ(z) = g * z
        e_tot(z) = cv_d * (T_0 - T_tri) + Φ(z)
        return FT(ρ(local_geometry) * e_tot(z))
    end

    # horizontal velocity
    uh(local_geometry) = Geometry.Covariant12Vector(FT(0), FT(0))

    # vertical velocity
    w(local_geometry) = Geometry.Covariant3Vector(FT(0))

    return (ρ = ρ, ρe_tot = ρe_tot, uh = uh, w = w)
end
