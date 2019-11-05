

#export

################################################################################
#
#  Basic interface
#
################################################################################

@doc Markdown.doc"""
    var(a::EisensteinField)
> Returns the identifier (as a symbol, not a string), that is used for printing
> the generator of the given Eisenstein field.
"""
var(a::EisensteinField) = a.S

@doc Markdown.doc"""
    gen(a::EisensteinField)
> Return the generator of the given EisensteinField.
"""
function gen(a::EisensteinField)
    r = eisf_elem(a)
    r.data_ring_elt = gen(a.data_ring)
   return r
end

@doc Markdown.doc"""
    one(a::EisensteinField)
> Return the multiplicative identity, i.e. one, in the given Eisenstein field.
"""
function one(a::EisensteinField)
    return a(1)
end

@doc Markdown.doc"""
    zero(a::EisensteinField)
> Return the multiplicative identity, i.e. one, in the given Eisenstein field.
"""
function zero(a::EisensteinField)
    return a(0)
end

function prime(a::EisensteinField)
    return prime(base_field(a))
end

################################################################################
#
#  Base field, basic base field functions, and uniformizer
#
################################################################################

@doc Markdown.doc"""
    base_ring(a::EisensteinField)
> Returns the base ring of `a`.
"""
base_ring(a::EisensteinField) = a.base_ring

@doc Markdown.doc"""
    base_field(a::EisensteinField)
> Returns the base ring of `a`.
"""
base_field(a::EisensteinField) = base_ring(a)


# TODO: Decide whether this is a "relative" or absolute method.
@doc Markdown.doc"""
    degree(a::EisensteinField)
> Return the degree of the given Eisenstein field over it's base. i.e. the degree of its
> defining polynomial.
"""
degree(a::EisensteinField) = degree(a.pol)

@doc Markdown.doc"""
    absolute_degree(a::NALocalField)
> Return the absolute degree of the given Eisenstein field over the ground padic field.
"""
absolute_degree(a::PadicField) = 1
absolute_degree(a::QadicField) = degree(a)

function absolute_degree(a::NALocalField)
    return degree(a)*absolute_degree(base_ring(a))
end
    
# By our definition, the generator of a field of eisenstein type is the uniformizer.
uniformizer(a::EisensteinField) = gen(a)

@doc Markdown.doc"""
    basis(K::EisensteinField) -> Array{eisf_elem,1}

Returns a basis for $K$ over its base ring.
"""
function basis(K::EisensteinField)
    n = degree(K)
    g = gen(K);
    d = Array{typeof(g)}(undef, n)
    b = K(1)
    for i = 1:n-1
        d[i] = b
        b *= g
    end
    d[n] = b
    return d
end


################################################################################
#
#  Predicates
#
################################################################################

issimple(::Type{EisensteinField}) = true

issimple(::EisensteinField) = true


###############################################################################
#
#   AbstractString I/O
#
###############################################################################

function show(io::IO, a::EisensteinField{T}) where T
   print(io, "Eisenstein extension over local field of type $T")
   print(io, " with defining polynomial ", a.pol)
end

################################################################################
#
#  Field constructions
#
################################################################################

@doc Markdown.doc"""
    EisenteinField(f::AbstractAlgebra.Generic.Poly{<:NALocalFieldElem}, 
                   s::AbstractString; cached::Bool = true, check::Bool = true)
> Return a tuple $R, x$ consisting of the parent object $R$ and generator $x$
> of the local field $\mathbb{Q}_p/(f)$ where $f$ is the supplied polynomial.
> The supplied string `s` specifies how the generator of the field extension
> should be printed.

> WARNING: Defaults are actually cached::Bool = false, check::Bool = true
"""
function EisensteinField(f::AbstractAlgebra.Generic.Poly{<:NALocalFieldElem},
                         s::AbstractString;
                         cached::Bool = false, check::Bool = true)
    return EisensteinField(f, Symbol(s), cached, check)
end


################################################################################
#
#  Characteristic
#
################################################################################

characteristic(::EisensteinField) = 0

################################################################################
#
#  Class group
#
################################################################################

@doc Markdown.doc"""
    class_group(K::EisensteinField) -> GrpAbFinGen, Map

Returns the class group as an abelian group and a map from this group to the set
of ideals of the maximal order. 

NOTE: This function is not implemented.
"""
function class_group(K::EisensteinField)
  error("Not implemented.")
end

################################################################################
#
#  Residue Field
#
################################################################################

function ResidueField(K::EisensteinField)
    k, mp_struct = ResidueField(base_ring(K))

    # Unpack the map structure to get the maps to/from the residue field.
    base_res  = mp_struct.f
    base_lift = mp_struct.g

    T = elem_type(k)
    
    _residue = function(x::eisf_elem)
        v = valuation(x)
        v < 0 && error("element $x is not integral.")
        return base_res(coeff(x,0))
    end

    #TODO: See if the residue field elem type can be declared dynamically.
    function _lift(x)
        return K(base_lift(x))
    end
    
    return k, MapFromFunc(_residue, _lift, K, k)
end

################################################################################
#
#  Squash extension
#
################################################################################

@doc Markdown.doc"""
    squash(L::NALocalField)
Given a Non-archimedean local field `L`, which is defined as an extension of the form $L/K/F$,
construct the new field extension of the form $L/F$.
"""
function squash(L::NALocalField)

    if typeof(L) <: FlintLocalField
        error("Cannot squash Flint Fields")
    end

    if typeof(base_ring(L)) <: FlintLocalField
        error("Base field is of type FlintLocalField, which has no base field.")
    end

    K = base_ring(L)
    F = base_ring(K)

    # Treat defining polynomials as multivariate polynomials.
    Ry, y = PolynomialRing(F, "y")
    Rx, x = PolynomialRing(Ry, "x")    
    f = K.pol(x)
    g = sum(polynomial(coeff(L.pol,i))(x)*y^i for i=0:degree(L.pol))

    h = resultant(f,g)
    
    return EisensteinField(h, L.S)
end

@doc Markdown.doc"""
    polynomial(a::eisf_elem)
Converts an eisenstein element into a polynomial over the base ring of its parent.
"""
function polynomial(a::eisf_elem)
    return a.data_ring_elt.data
end

# function resultant(f::AbstractAlgebra.Generic.MPolyElem, g::AbstractAlgebra.Generic.MPolyElem, m)

#     check_parent(f,g)
    
#     # Create a new polynomial ring over a polynomial ring with the variable "m" isolated
#     R = parent(f)
#     vars = gens(R)
#     mind = findfirst(x->x==m, vars)

#     A, new_vars = PolynomialRing(base_ring(R), length(vars)-1)
#     Rnew, M = PolynomialRing(A, "M")


#     any_new_vars = convert(Array{Any,1}, new_vars)
    
#     splice!(any_new_vars, mind:mind-1, [M])
#     splice!(vars, mind:mind)

#     display(vars)
#     display(any_new_vars)
    
#     return resultant(f(any_new_vars...), g(any_new_vars...))(vars)
# end

@doc Markdown.doc"""
    coeffs(f::AbstractAlgebra.Generic.MPolyElem, i::Integer)
Return the coefficients of the polynomial with respect to the $i$-th variable.
"""
function coeffs(f::AbstractAlgebra.Generic.MPolyElem, i::Integer)
    e_vecs = collect(exponent_vectors(f))
    t_list = collect(terms(f))

    m = gens(parent(f))[i]
    D = Dict(e=>t for (e,t) in zip(e_vecs, t_list))
    
    max_j = maximum(e[i] for e in e_vecs)

    output = AbstractAlgebra.Generic.MPolyElem[]
    for j = 0:max_j
        j_term_exps = filter(e-> e[i] == j, e_vecs)
        push!(output, sum(divexact(D[e], m^j)  for e in j_term_exps))
    end
    return output
end

@docs Markdown.doc"""
    coeffs(f::AbstractAlgebra.Generic.MPolyElem, m::AbstractAlgebra.Generic.MPolyElem)
Return the coefficients of the polynomial with respect to the variable $m$.
"""
function coeffs(f::AbstractAlgebra.Generic.MPolyElem, m::AbstractAlgebra.Generic.MPolyElem)
    i = findfirst(a->a==m, gens(parent(f)))
    return coeffs(f, i)
end

################################################################################
#
#  Unramified extension
#
################################################################################
