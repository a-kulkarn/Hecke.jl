export qAdicConj


#########################################################################################
#
#   qAdic Conj structure
#
#########################################################################################

# Honestly the thing that is needed here is a pure Julia implementation of the HenselCtx.
# Field definitions should use a "Krasner criteria" to detect if the extensions are distinct.

################################################################################
# Root contexts for lifting algorithms
################################################################################

mutable struct qAdicRootCtx
  f::fmpz_poly
  p::Int
  n::Int
  Q::Array{FlintQadicField, 1}
  H::Hecke.HenselCtx
  R::Array{qadic, 1} # These are the cached roots.
  function qAdicRootCtx(f::fmpz_poly, p::Int)
    r = new()
    r.f = f
    r.p = p
    r.H = H = Hecke.factor_mod_pk_init(f, p)
    lf = Hecke.factor_mod_pk(H, 1)
    #TODO:XXX: Careful: QadicField ONLY works, currently, in Conway range
    Q = [QadicField(p, x, 1) for x = Set(degree(y) for y = keys(lf))]
    @assert all(isone, values(lf))
    r.Q = Q

    #NOTE: Roots are not computed when initialized, as no precision has been determined.
    return r
  end
end



@doc Markdown.doc"""
    qAdicConj(K::AnticNumberField, p::Int)

Creates a data structure to compute the conjugates in a unramified splitting field
over $Q_p$.
"""
# This structure doesn't compute anything really.

# It mostly just explicitly associates a number field to a Qadic field.

# The work in the initialization is hidden in the HenselCtx step.
# It would make more sense to have some computation precomputed.

# This object doesn't know very much right now.
mutable struct qAdicConj
  K::AnticNumberField
  C::qAdicRootCtx
  cache::Dict{nf_elem, Any}

  function qAdicConj(K::AnticNumberField, p::Int)
    isindex_divisor(maximal_order(K), p) && error("cannot deal with index divisors yet")
    isramified(maximal_order(K), p) && error("cannot deal with ramification yet")

    # Check for cached data. If none, update the reference in K to set
    # `D` as the local conjugate data.
    D = _get_nf_conjugate_data_qAdic(K, false)
    if D !== nothing
      if haskey(D, p)
        Dp = D[p]
        return new(K, Dp[1], Dp[2])
      end
    else
      D = Dict{Int, Tuple{qAdicRootCtx, Dict{nf_elem, Any}}}()
      _set_nf_conjugate_data_qAdic(K, D)
    end

    # Initialize the new structure.  
    Zx = PolynomialRing(FlintZZ, cached = false)[1]
    C = qAdicRootCtx(Zx(K.pol), p)
    r = new()
    r.C = C
    r.K = K

    # cache for conjugates of a given number field element??
    r.cache = Dict{nf_elem, Any}()
    D[p] = (C, r.cache)
    return r
  end
end

# Display for conjugates data.
function Base.show(io::IO, C::qAdicConj)
  println(io, "data for the $(C.C.p)-adic completions of $(C.K)")
end



#########################################################################################
#
#   Newton lifting and root finding
#
#########################################################################################


@doc Markdown.doc"""
    roots(f::fmpz_poly, Q::FlintQadicField; max_roots::Int = degree(f)) -> Array{qadic, 1}
The roots of $f$ in $Q$, $f$ has to be square-free (at least the roots have to be simple roots).    
"""

# NOTE: Both a Hensel factorization and a newton iteration are required to refine the roots,
#       since the Hensel context only works for polynomials over ZZ.
function roots(f::fmpz_poly, Q::FlintQadicField; max_roots::Int = degree(f))
    k, mk = ResidueField(Q)
    rt = roots(f, k)
    RT = qadic[]
    for r = rt
        new_rt, cond = newton_lift(f, preimage(mk, r))
        push!(RT, new_rt)
        if length(RT) >= max_roots
            return RT
        end
    end
    return RT
end

function roots(C::qAdicRootCtx, n::Int = 10)
  if isdefined(C, :R) && all(x -> x.N >= n, C.R)
    return [setprecision(x, n) for x = C.R]
  end
  lf = factor_mod_pk(C.H, n)
  rt = qadic[]
  for Q = C.Q
    Q.prec_max = n
    for x = keys(lf)
      if degree(x) == degree(Q)
        append!(rt, roots(x, Q, max_roots = 1))
      end
    end
  end
  if isdefined(C, :R)
    st = qadic[]
    for r = C.R
      p = findfirst(x -> degree(parent(r)) == degree(parent(x)) && iszero(x-r), rt)
      push!(st, rt[p])
    end
    rt = st
  end
  C.R = rt
  return rt
end

#########################################################################################
#
#   Completion from prime ideal
#
#########################################################################################

function gens(P::NfOrdIdl)
    @assert has_2_elem(P)
    (P.gen_one, P.gen_two)
end

# TODO: make the coeffs methods more consistent.
function coeffs(a::FinFieldElem)
    k = parent(a)
    coeff_field = GF(k.p)
    if degree(k) == 1
        return [one(coeff_field)]
    else
        return [coeff_field(coeff(a,j)) for j=0:degree(k)-1]
    end
end

function coeffs(a::qadic)
    k = parent(a)
    return [coeff(a,j) for j=0:degree(k)-1]
end

function mod_sym(a,b)
    c = mod(a,b)
    return c < b/2 ? c : c-b
end

function sym_lift(a::padic)
    u = unit_part(a)
    p = prime(a.parent)
    N = precision(a)
    v = valuation(a)
    return mod_sym(u, p^(N-v))*FlintQQ(p)^v
end

@doc Markdown.doc"""
    underdetermined_solve(A,b)
Solves the equation `Ax=b`. Return the first index of the column where the last entry is non-zero.
"""
function underdetermined_solve(A,b)

    M = hcat(A,-b)
    nu,N = nullspace(M)

    display(N)

    ind = 0
    for j=1:size(N,2)
        if isone(N[size(N,1),j])
            ind=j
            break
        end
    end
    @assert !iszero(ind)

    return nu,N,ind
end

@doc Markdown.doc"""
    underdetermined_solve_first(A,b)
Return the first basis column of the solutions to Ax=b, if it exists.
"""
function underdetermined_solve_first(A,b)
    nu,N,ind = underdetermined_solve(A,b)
    return N[1:size(N,1)-1,ind]
end


## Temporary structure to record data cached so that a completion can be sharpened.
## This should somehow be remembered by the maps to/from the completion instead.

mutable struct CompletionMapData
    dixon_bn
    dixon_mat_inv_modpn
    residue_field_map
end

#########################################################################################
#
#   Embedding classes (up to equivalence) interface
#
#########################################################################################

# Return the embeddings, up to local Galois automorphisms, of a number field element `a`.
# Treatment is different in ramified versus unramified cases due to the extra structure.
# i.e, a factorization method is present in the unramified case.

function embedding_classes(a, p)    
    K = parent(a)

    if any(isramified(maximal_order(K), p))
        return embedding_classes_ramified(a,p)
    else
        return embedding_classes_unramified(a,p)
    end
end

function embedding_classes_ramified(a,p)
    K = parent(a)
    lp = prime_decomposition(maximal_order(K), p)
    prime_ideals = [P[1] for P in lp]

    completions = [Hecke.completion(K,P) for P in prime_ideals]
    embeddings_up_to_equiv = [mp(a) for (field,mp) in completions]
    return embeddings_up_to_equiv
end

# function _conjugates(a::nf_elem, C::qAdicConj, n::Int, op::Function)
function embedding_classes_unramified(a, C, precision=10)
    K = parent(a)
    #C = qAdicConj(K, Int(p))
    #TODO: implement a proper Frobenius - with caching of the frobenius_a element

    R = roots(C.C, precision)   # This seems to be the line where the roots are actually computed.
    @assert parent(a) == C.K
    Zx = PolynomialRing(FlintZZ, cached = false)[1]
    d = denominator(a)

    # The element `a` is replaced by a polynomial. It is assumed that the variable
    # in the polynomial is identified with the generator of the number field.
    f = Zx(d*a)
    res = qadic[]
    for alpha in R
        b = inv(parent(alpha)(d))*f(alpha)
        push!(res, b)
    end
    return res
end

#########################################################################################
#
#   Conjugates interface
#
#########################################################################################


#to compare to the classical conjugates
#  all = true/ false: only on of a pair of complex conjugates is returned
#  flat = true/ false: return (Re, Im) or the complex number
#TODO: not sure how this would work in the ramified, not-normal case.
@doc Markdown.doc"""
    conjugates(a::nf_elem, C::qAdicConj, n::Int = 10; flat::Bool = false, all:Bool = true) -> []

Returns an array of the q-adic conjugates of $a$: Let $p Z_K = \prod P_i$ for the maximal order
$Z_K$ of the parent of $a$. Then $K \otimes Q_p = \prod K_{P_i}$. For each of the $P_i$
a $q$-adic (unramifed) extension $K_{P_i}$ of $Q_p$ is computed, sth. $a$ has $\deg P_i = \deg K_{P_i}$
many cojugates in $K_{P_i}$.
If {{{all = true}}} and {{{ flat = false}}}, the default, then all $n$ conjugates are returned.
If {{{all = false}}}, then for each $P_i$ only one conjugate is returned, the others could be 
xomputed using automorphisms (the Frobenius).
If {{{flat = true}}}, then instead of the conjugates, only the $p$-adic coefficients are returned.
"""
function conjugates(a::nf_elem, C::qAdicConj, precision=10; flat::Bool = false, all::Bool = true)
  return expand(embedding_classes_unramified(a, C, precision), flat = flat, all = all)
end

# Expansion logic to apply frobenius to the partial result.
function expand(a::Array{qadic, 1}; all::Bool, flat::Bool)
  re = qadic[]
  if all
    for x = a
      push!(re, x)
      y = x
      for i=2:degree(parent(x))
        y = frobenius(y)
        push!(re, y)
      end
    end
  else
    re = a
  end
  if flat
    r = padic[]
    for x = re
      for i=1:degree(parent(x))
        push!(r, coeff(x, i-1))
      end
    end
    return r
  else
    return re
  end
end


#########################################################################################
#
#   Galois closures
#
#########################################################################################

@doc Markdown.doc"""
    field_of_definition(a::padic)
    field_of_definition(a::qadic)
Returns the degree of the extension defining `a`.
"""
function degree_of_field_of_definition(a::qadic)
    for d in filter(x->x>0, divisors(degree(parent(a))))
        if a == frobenius(a,d)
            return d
        end
    end
    error("No power of frobenius of $a equals $a.")
end

function degree_of_field_of_definition(a::padic)
    return 1
end


@doc Markdown.doc"""
    galois_closure(K::EisensteinField)
Returns an Eisenstein field `L` such that `L/Qp` is Galois. Also return a map.
Note that the Eisenstein Field will be over a Qadic base, which might be an extension of
the base field of $K$.
"""
function galois_closure(K::EisensteinField)
    !is_tamely_ramified(K) && error("Wild ramification still not possible.")
    is_tamely_ramified(K) && return _galois_closure_tamely_ramified(K)
end

function galois_closure(K::FlintLocalField)
    return K, x->x
end

function _galois_closure_tamely_ramified(K::EisensteinField)
    L, mp_to_squash = simple_extension(K)

    # TODO: Add reference.
    # The size of the Galois closure of a tamely ramified extension is given by
    # the classification of tamely ramified extensions. (given by a poly of the form `X^e-u*p`.)
    # 
    frob_orbit_size = lcm(map(degree_of_field_of_definition, coeffs(L.pol)))

    g = change_base_ring(L, L.pol)
    X = gen(parent(g))
    h = fprimpart(g(uniformizer(L)*X))

    # Note that $h$ is guarenteed to be squarefree over the residue field by the
    # tameness assumption, since the degree of `h` is coprime to `p`.

    k,res = ResidueField(L)
    ext_degrees = map(x->degree(x[1]), factor(map_coeffs(res, h)))

    Lgal, _, mp_to_gal = unramified_extension(L, frob_orbit_size*lcm(ext_degrees))
    
    return Lgal, x->mp_to_gal(mp_to_squash(x))

end

@doc Markdown.doc"""
    is_tamely_ramified(K::NALocalField)
"""
function is_tamely_ramified(K::NALocalField)
    return gcd(prime(K), ramification_degree(K)) == 1
end

#########################################################################################
#
#   Conjugates in ramified completions.
#
#########################################################################################


#=
#1. Need to construct the ramified completion.

#2. Need to determine the unramified sub-extension of the splitting field 
#   (possible in stupid cases, but in general requires factorizations.)

# For now, give up if the splitting field is not just an unramified extension.

#3. Compute the roots in the local splitting field.

Generally, this will work so long as there is no wild ramification. The wild case is easy
to detect.
=#

