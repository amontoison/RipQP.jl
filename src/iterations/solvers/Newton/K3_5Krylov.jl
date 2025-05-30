# K3.5 = D K3 D⁻¹ , 
#      [ I   0   0       0  ]
# D² = [ 0   I   0       0  ] 
#      [ 0   0  S_l⁻¹    0  ]
#      [ 0   0   0     S_u⁻¹]
#
# [-Q - ρI    Aᵀ   √S_l  -√S_u ][ Δx  ]     [    -rc        ]
# [   A       δI    0      0   ][ Δy  ]     [    -rb        ]
# [  √S_l     0    X-L     0   ][Δs_l2] = D [σμe - (X-L)S_le]
# [ -√S_u     0     0     U-X  ][Δs_u2]     [σμe + (U-X)S_ue]
export K3_5KrylovParams

"""
Type to use the K3.5 formulation with a Krylov method, using the package 
[`Krylov.jl`](https://github.com/JuliaSmoothOptimizers/Krylov.jl). 
The outer constructor 

    K3_5KrylovParams(; uplo = :L, kmethod = :minres, preconditioner = Identity(),
                     rhs_scale = true,
                     atol0 = 1.0e-4, rtol0 = 1.0e-4,
                     atol_min = 1.0e-10, rtol_min = 1.0e-10,
                     ρ0 = sqrt(eps()) * 1e5, δ0 = sqrt(eps()) * 1e5,
                     ρ_min = 1e3 * sqrt(eps()), δ_min = 1e4 * sqrt(eps()),
                     itmax = 0, mem = 20)

creates a [`RipQP.SolverParams`](@ref).
The available methods are:
- `:minres`
- `:minres_qlp`
- `:symmlq`

"""
mutable struct K3_5KrylovParams{T, PT} <: NewtonKrylovParams{T, PT}
  uplo::Symbol
  kmethod::Symbol
  preconditioner::PT
  rhs_scale::Bool
  atol0::T
  rtol0::T
  atol_min::T
  rtol_min::T
  ρ0::T
  δ0::T
  ρ_min::T
  δ_min::T
  itmax::Int
  mem::Int
end

function K3_5KrylovParams{T}(;
  uplo::Symbol = :L,
  kmethod::Symbol = :minres,
  preconditioner::AbstractPreconditioner = Identity(),
  rhs_scale::Bool = true,
  atol0::T = eps(T)^(1 / 4),
  rtol0::T = eps(T)^(1 / 4),
  atol_min::T = sqrt(eps(T)),
  rtol_min::T = sqrt(eps(T)),
  ρ0::T = eps(T)^(1 / 8),
  δ0::T = eps(T)^(1 / 8),
  ρ_min::T = T(1e3 * sqrt(eps())),
  δ_min::T = T(1e4 * sqrt(eps())),
  itmax::Int = 0,
  mem::Int = 20,
) where {T <: Real}
  return K3_5KrylovParams(
    uplo,
    kmethod,
    preconditioner,
    rhs_scale,
    atol0,
    rtol0,
    atol_min,
    rtol_min,
    ρ0,
    δ0,
    ρ_min,
    δ_min,
    itmax,
    mem,
  )
end

K3_5KrylovParams(; kwargs...) = K3_5KrylovParams{Float64}(; kwargs...)

mutable struct PreallocatedDataK3_5Krylov{
  T <: Real,
  S,
  L <: LinearOperator,
  Pr <: PreconditionerData,
  Ksol <: KrylovWorkspace,
} <: PreallocatedDataNewtonKrylov{T, S}
  pdat::Pr
  rhs::S
  rhs_scale::Bool
  regu::Regularization{T}
  ρv::Vector{T}
  δv::Vector{T}
  K::L # augmented matrix (LinearOperator)         
  KS::Ksol
  kiter::Int
  atol::T
  rtol::T
  atol_min::T
  rtol_min::T
  itmax::Int
end

function opK3_5prod!(
  res::AbstractVector{T},
  nvar::Int,
  ncon::Int,
  ilow::Vector{Int},
  iupp::Vector{Int},
  nlow::Int,
  x_m_lvar::AbstractVector{T},
  uvar_m_x::AbstractVector{T},
  s_l::AbstractVector{T},
  s_u::AbstractVector{T},
  Q::Union{AbstractMatrix{T}, AbstractLinearOperator{T}},
  A::Union{AbstractMatrix{T}, AbstractLinearOperator{T}},
  ρv::AbstractVector{T},
  δv::AbstractVector{T},
  v::AbstractVector{T},
  α::T,
  β::T,
  uplo::Symbol,
) where {T}
  @views mul!(res[1:nvar], Q, v[1:nvar], -α, β)
  res[1:nvar] .-= @views (α * ρv[1]) .* v[1:nvar]
  @. res[ilow] += @views α * sqrt(s_l) * v[(nvar + ncon + 1):(nvar + ncon + nlow)]
  @. res[iupp] -= @views α * sqrt(s_u) * v[(nvar + ncon + nlow + 1):end]
  if uplo == :U
    @views mul!(res[1:nvar], A, v[(nvar + 1):(nvar + ncon)], α, one(T))
    @views mul!(res[(nvar + 1):(nvar + ncon)], A', v[1:nvar], α, β)
  else
    @views mul!(res[1:nvar], A', v[(nvar + 1):(nvar + ncon)], α, one(T))
    @views mul!(res[(nvar + 1):(nvar + ncon)], A, v[1:nvar], α, β)
  end
  res[(nvar + 1):(nvar + ncon)] .+= @views (α * δv[1]) .* v[(nvar + 1):(nvar + ncon)]
  if β == 0
    @. res[(nvar + ncon + 1):(nvar + ncon + nlow)] =
      @views α * (sqrt(s_l) * v[ilow] + x_m_lvar * v[(nvar + ncon + 1):(nvar + ncon + nlow)])
    @. res[(nvar + ncon + nlow + 1):end] =
      @views α * (-sqrt(s_u) * v[iupp] + uvar_m_x * v[(nvar + ncon + nlow + 1):end])
  else
    @. res[(nvar + ncon + 1):(nvar + ncon + nlow)] =
      @views α * (sqrt(s_l) * v[ilow] + x_m_lvar * v[(nvar + ncon + 1):(nvar + ncon + nlow)]) +
             β * res[(nvar + ncon + 1):(nvar + ncon + nlow)]
    @. res[(nvar + ncon + nlow + 1):end] =
      @views α * (-sqrt(s_u) * v[iupp] + uvar_m_x * v[(nvar + ncon + nlow + 1):end]) +
             β * res[(nvar + ncon + nlow + 1):end]
  end
end

function PreallocatedData(
  sp::K3_5KrylovParams,
  fd::QM_FloatData{T},
  id::QM_IntData,
  itd::IterData{T},
  pt::Point{T},
  iconf::InputConfig{Tconf},
) where {T <: Real, Tconf <: Real}

  # init Regularization values
  if iconf.mode == :mono
    regu = Regularization(T(sp.ρ0), T(sp.δ0), T(sp.ρ_min), T(sp.δ_min), :classic)
  else
    regu =
      Regularization(T(sp.ρ0), T(sp.δ0), T(sqrt(eps(T)) * 1e0), T(sqrt(eps(T)) * 1e0), :classic)
  end
  ρv = [regu.ρ]
  δv = [regu.δ] # put it in a Vector so that we can modify it without modifying opK2prod!
  K = LinearOperator(
    T,
    id.nvar + id.ncon + id.nlow + id.nupp,
    id.nvar + id.ncon + id.nlow + id.nupp,
    true,
    true,
    (res, v, α, β) -> opK3_5prod!(
      res,
      id.nvar,
      id.ncon,
      id.ilow,
      id.iupp,
      id.nlow,
      itd.x_m_lvar,
      itd.uvar_m_x,
      pt.s_l,
      pt.s_u,
      fd.Q,
      fd.A,
      ρv,
      δv,
      v,
      α,
      β,
      fd.uplo,
    ),
  )

  rhs = similar(fd.c, id.nvar + id.ncon + id.nlow + id.nupp)

  KS = init_Ksolver(K, rhs, sp)
  pdat = PreconditionerData(sp, id, fd, regu, K)

  return PreallocatedDataK3_5Krylov(
    pdat,
    rhs,
    sp.rhs_scale,
    regu,
    ρv,
    δv,
    K, #K
    KS,
    0,
    T(sp.atol0),
    T(sp.rtol0),
    T(sp.atol_min),
    T(sp.rtol_min),
    sp.itmax,
  )
end

function solver!(
  dd::AbstractVector{T},
  pad::PreallocatedDataK3_5Krylov{T},
  dda::DescentDirectionAllocs{T},
  pt::Point{T},
  itd::IterData{T},
  fd::Abstract_QM_FloatData{T},
  id::QM_IntData,
  res::AbstractResiduals{T},
  cnts::Counters,
  step::Symbol,
) where {T <: Real}
  if step == :aff
    Δs_l = dda.Δs_l_aff
    Δs_u = dda.Δs_u_aff
  else
    Δs_l = itd.Δs_l
    Δs_u = itd.Δs_u
  end
  pad.rhs[1:(id.nvar + id.ncon)] .= dd
  @. pad.rhs[(id.nvar + id.ncon + 1):(id.nvar + id.ncon + id.nlow)] = Δs_l / sqrt(pt.s_l)
  @. pad.rhs[(id.nvar + id.ncon + id.nlow + 1):end] = Δs_u / sqrt(pt.s_u)
  if pad.rhs_scale
    rhsNorm = kscale!(pad.rhs)
  end
  (step !== :cc) && (pad.kiter = 0)
  ksolve!(
    pad.KS,
    pad.K,
    pad.rhs,
    pad.pdat.P,
    verbose = 0,
    atol = pad.atol,
    rtol = pad.rtol,
    itmax = pad.itmax,
  )
  update_kresiduals_history!(res, pad.K, pad.KS.x, pad.rhs)
  pad.kiter += Krylov.iteration_count(pad.KS)
  if pad.rhs_scale
    kunscale!(pad.KS.x, rhsNorm)
  end

  dd .= @views pad.KS.x[1:(id.nvar + id.ncon)]
  @. Δs_l = @views pad.KS.x[(id.nvar + id.ncon + 1):(id.nvar + id.ncon + id.nlow)] * sqrt(pt.s_l)
  @. Δs_u = @views pad.KS.x[(id.nvar + id.ncon + id.nlow + 1):end] * sqrt(pt.s_u)

  return 0
end

function update_pad!(
  pad::PreallocatedDataK3_5Krylov{T},
  dda::DescentDirectionAllocs{T},
  pt::Point{T},
  itd::IterData{T},
  fd::Abstract_QM_FloatData{T},
  id::QM_IntData,
  res::AbstractResiduals{T},
  cnts::Counters,
) where {T <: Real}
  if cnts.k != 0
    update_regu!(pad.regu)
  end

  update_krylov_tol!(pad)

  pad.ρv[1] = pad.regu.ρ
  pad.δv[1] = pad.regu.δ

  update_preconditioner!(pad.pdat, pad, itd, pt, id, fd, cnts)

  return 0
end
