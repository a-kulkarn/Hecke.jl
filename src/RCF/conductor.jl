export conductor, isconductor, norm_group, maximal_abelian_subfield, genus_field, content_ideal, subfields, isnormal, iscentral, normal_closure

########################################################################################
#
#  Tools for conductor
#
########################################################################################

function _norm_group_gens_small(C::ClassField)

  mp=C.mq

  mR = C.rayclassgroupmap
  mS = C.quotientmap
  
  R=domain(mR)
  cond=mR.modulus_fin
  inf_plc1=mR.modulus_inf
  O=parent(cond).order
  E=order(domain(mp))
  expo=Int(exponent(domain(mp)))
  K=O.nf
  
  mS=pseudo_inv(mS)
  dom=domain(mS)
  M=zero_matrix(FlintZZ,ngens(dom), ngens(codomain(mS)))
  for i=1:ngens(dom)
    elem=mS(dom[i]).coeff
    for j=1:ngens(codomain(mS))
      M[i,j]=elem[1,j]
    end
  end
  S1=Hecke.GrpAbFinGenMap(domain(mS),codomain(mS),M)
  T,mT=Hecke.kernel(S1)

  Sgens=find_gens_sub(mR,mT)
  
  return Sgens
  
end

#
#  Find small primes generating a subgroup of the ray class group
#

function find_gens_sub(mR::MapRayClassGrp, mT::GrpAbFinGenMap)

  O = order(codomain(mR))
  R = domain(mR) 
  T = domain(mT)
  m = Hecke._modulus(mR)
  l = minimum(m)
  lp = NfOrdIdl[]
  sR = GrpAbFinGenElem[]
  
  if isdefined(mR, :prime_ideal_cache)
    S = mR.prime_ideal_cache
  else
    S = prime_ideals_up_to(O, 1000)
    mR.prime_ideal_cache = S
  end
  q, mq = quo(T, sR, false)
  for (i,P) in enumerate(S)
    if divisible(l,P.minimum)
      continue
    end
    if haskey(mR.prime_ideal_preimage_cache, P)
      f = mR.prime_ideal_preimage_cache[P]
    else
      f = mR\P
      mR.prime_ideal_preimage_cache[P] = f
    end
    bool, pre = haspreimage(mT, f)
    if !bool
      continue
    end
    if iszero(mq(pre))
      continue
    end
    push!(sR, pre)
    push!(lp, P)
    q, mq = quo(T, sR, false)
    if order(q) == 1 
      break
    end
  end
  if order(q) == 1
    return lp
  else
    error("Not enough primes")
  end
end

#
#  This functions constructs generators for 1+p^u/1+p^u+1
#

function _1pluspk_1pluspk1(K::AnticNumberField, p::NfOrdIdl, pk::NfOrdIdl, pv::NfOrdIdl, lp::Dict{NfOrdIdl, Int}, prime_power::Dict{NfOrdIdl, NfOrdIdl}, a::Union{Int, fmpz}, n::Int)
  
  O = maximal_order(K)
  b = basis(pk, copy = false)
  N = basis_matrix(pv, copy = false)*basis_mat_inv(pk, copy = false)
  G = AbelianGroup(N.num)
  S, mS = snf(G)
  #Generators
  gens = Array{NfOrdElem, 1}(undef, ngens(S))
  for i=1:ngens(S)
    gens[i] = O(1)
    for j = 1:ngens(G)
      add!(gens[i], gens[i], mod(mS.map[i,j], S.snf[end])*b[j])
    end
  end
  if length(lp) > 1
    i_without_p = ideal(O,1)
    for (p2,vp2) in lp
      (p != p2) && (i_without_p *= prime_power[p2])
    end

    alpha, beta = idempotents(prime_power[p], i_without_p)
    for i in 1:length(gens)
      mul!(gens[i], gens[i], beta)
      add!(gens[i], gens[i], alpha)
    end   
  end
  if mod(n,2)==0
    for i=1:length(gens)
      gens[i] = make_positive(gens[i], fmpz(a))
    end
  end
  return gens
end



#######################################################################################
#
#  Conductor functions
#
#######################################################################################

@doc Markdown.doc"""
  conductor(C::Hecke.ClassField) -> NfOrdIdl, Array{InfPlc,1}

Return the conductor of the abelian extension corresponding to C
"""
function conductor(C::Hecke.ClassField)

  if isdefined(C,:conductor)
    return C.conductor
  end
  mR = C.rayclassgroupmap
  mS = C.quotientmap
  mp = pseudo_inv(mS)* mR
  G = domain(mp)
  #
  #  First, we need to find the subgroup
  #
  
  cond = mR.modulus_fin
  inf_plc = mR.modulus_inf
  O = parent(cond).order
  if isone(cond) && isempty(inf_plc)
    return ideal(O,1), InfPlc[]
  end
  E=order(G)
  expo=Int(exponent(G))
  K=O.nf
 
  #
  #  Some of the factors of the modulus are unnecessary for order reasons:
  #   
  L=deepcopy(mR.fact_mod)
  for (p,vp) in L
    if !divisible(E,p.minimum)
      if gcd(E, norm(p)-1)==1
        Base.delete!(L,p)
      else
        L[p]=1
      end  
    else
      if L[p]==1
        Base.delete!(L,p)
      end
    end
  end
  
  prime_power=Dict{NfOrdIdl, NfOrdIdl}()
  for (p,v) in mR.fact_mod
    prime_power[p]=p^v
  end
  
  if !isempty(inf_plc)
    totally_positive_generators(mR)
  end

  #Finite part of the modulus
  if !isempty(L)
    tmg=mR.tame_mult_grp
    wild=mR.wild_mult_grp
  end
  for (p,v) in L
    if v==1
      Q,mQ = quo(G,[preimage(mp, ideal(O,tmg[p].generators[1]))],false)
      if order(Q) == E
        Base.delete!(L,p)
      end  
    else
      k1=v-1
      k2=v
      gens=GrpAbFinGenElem[]
      Q=DiagonalGroup(Int[])
      while k1>=1
        multg=_1pluspk_1pluspk1(K, p, p^k1, p^k2, mR.fact_mod, prime_power, minimum(cond), Int(E))
        for i=1:length(multg)
          push!(gens, preimage(mp, ideal(O,multg[i])))
        end
        Q,mQ=quo(G,gens,false)
        if order(Q)!=E
          L[p]=k2
          break
        end
        k1-=1
        k2-=1
      end
      if order(Q)==E
        if haskey(tmg, p)
          push!(gens, mp\ideal(O,tmg[p].generators[1]))
          Q,mQ=quo(G,gens,false)
          if order(Q)==E
            delete!(L,p)
          end
        else
          delete!(L,p)
        end
      end
    end
  end
  cond=ideal(O,1)
  for (p,vp) in L
    cond*=p^vp
  end
  
  #Infinite part of the modulus
  cond_inf=InfPlc[]
  if !isempty(inf_plc)
    S, ex, lo = infinite_primes_map(O, inf_plc, mR.modulus_fin)
    for i=1:length(inf_plc)
      pl=inf_plc[i]
      j=1
      while true
        if !ispositive(ex(S[j]),pl)
          break
        end
        j+=1
      end
      delta=minimum(mR.modulus_fin)*ex(S[j])
      el=1+delta
      con=abs_upper_bound(1/real(conjugates_arb(delta))[j], fmpz)
      el+=con*delta
      Q,mQ=quo(G, [mp\ideal(O,el)], false)
      if order(Q)!=E
        push!(cond_inf, pl)
      end
    end
  end

  return cond, cond_inf
  
end 

###############################################################################
#
#  isconductor function
#
###############################################################################

@doc Markdown.doc"""
  isconductor(C::Hecke.ClassField, m::NfOrdIdl, inf_plc::Array{InfPlc,1}=InfPlc[]; check) -> NfOrdIdl, Array{InfPlc,1}

Checks if m, inf_plc is the conductor of the abelian extension corresponding to C. If check is false, it assumes that the 
given modulus is a multiple of the conductor.
This is generically faster than computing the conductor.
"""
function isconductor(C::Hecke.ClassField, m::NfOrdIdl, inf_plc::Array{InfPlc,1}=InfPlc[]; check::Bool=true)
  #
  #  First, we need to find the subgroup
  #
  
  mR = C.rayclassgroupmap
  mS = C.quotientmap
  G = codomain(mS)
  mp = pseudo_inv(mS) * mR
  
  R = domain(mR)
  cond = mR.modulus_fin
  inf_plc2 = mR.modulus_inf
  O=parent(cond).order
  E=order(G)
  expo=Int(exponent(G))
  K=O.nf
  tmg=mR.tame_mult_grp
  wild=mR.wild_mult_grp
  
  if check 
    mS=pseudo_inv(mS)
    dom=domain(mS)
    M=zero_matrix(FlintZZ,ngens(dom), ngens(codomain(mS)))
    for i=1:ngens(dom)
      elem=mS(dom[i]).coeff
      for j=1:ngens(codomain(mS))
        M[i,j]=elem[1,j]
      end
    end
    S1=Hecke.GrpAbFinGenMap(domain(mS),codomain(mS),M)
    T,mT=Hecke.kernel(S1)

    Sgens=find_gens_sub(mR,mT)
    
    r,mr=ray_class_group(m,inf_plc, n_quo= expo)
    quot=GrpAbFinGenElem[mr\s for s in Sgens]
    s,ms=quo(r, quot, false)
    if order(s)!=E
      return false
    end
  end

  #
  #  Some of the factors of the modulus are unnecessary for order reasons:
  #
  
  L=factor(m)
  for (p,vp) in L
    if !haskey(mR.fact_mod, p) || vp>mR.fact_mod[p]
      return false
    end
    if !divisible(E,minimum(p))
      if gcd(E, norm(p)-1)==1
        return false
      elseif vp>1
        return false
      end 
    elseif vp==1
      return false
    end
  end
  
  if isodd(E) && !isempty(inf_plc)
    return false
  end
  for pl in inf_plc
    if !(pl in inf_plc2)
      return false
    end
  end
  
  prime_power=Dict{NfOrdIdl, NfOrdIdl}()
  for (p,v) in L
    prime_power[p]=p^v
  end
  
  if !isempty(inf_plc2)
    totally_positive_generators(mR, cond.gen_one)
  end
  
  #Finite part of the modulus
  for (p,v) in L
    if v==1
      Q,mQ=quo(G,[preimage(mp, ideal(O,tmg[p].generators[1]))], false)
      if order(Q)==E
        return false
      end  
    else     
      multg=_1pluspk_1pluspk1(K, p, p^(v-1), p^v, mR.fact_mod, prime_power, cond.gen_one, Int(E))
      gens=Array{GrpAbFinGenElem,1}(undef, length(multg))
      for i=1:length(multg)
        gens[i]= preimage(mp, ideal(O,multg[i]))
      end
      Q,mQ=quo(G,gens, false)
      if order(Q)==E
        return false
      end
    end
  end

  #Infinite part of the modulus
  if !isempty(inf_plc2)
    S, ex, lo = infinite_primes_map(O, inf_plc, mR.modulus_fin)
    for i=1:length(inf_plc)
      i=1
      while true
        if !ispositive(ex(S[i]),pl)
          break
        end
        i+=1
      end
      el=1+minimum(cond)*ex(S[i])
      while !ispositive(el, pl)
        el+=minimum(cond)*ex(S[i])
      end
      Q,mQ=quo(G,preimage(mp, ideal(O,el)), false)
      if order(Q)==E
        return false
      end
    end
  end
  
  return true
  
end

####################################################################################
#
#  Discriminant function
#
####################################################################################

@doc Markdown.doc"""
    discriminant(C::ClassField) -> NfOrdIdl
Using the conductor-discriminant formula, compute the (relative) discriminant of $C$.
This does not use the defining equations.
"""
function discriminant(C::ClassField)
  
  if isdefined(C,:conductor)
    m=C.conductor[1]
    inf_plc=C.conductor[2]
  else
    C.conductor=conductor(C)
    m=C.conductor[1]
    inf_plc=C.conductor[2]  
  end
  @assert typeof(m)==NfOrdIdl
  
  mp = pseudo_inv(C.quotientmap) * C.rayclassgroupmap
  R = domain(mp)
  n = order(R)
  
  mR = C.rayclassgroupmap

  cond=mR.modulus_fin
  inf_plc=mR.modulus_inf
  O=parent(cond).order
  E=order(R)
  expo=Int(exponent(R))
  K=O.nf
  a=Int(minimum(m))
  relative_disc=Dict{NfOrdIdl,Int}()
  abs_disc=Dict{fmpz,fmpz}()
  lp=mR.fact_mod
  if isempty(lp)
    C.relative_discriminant=relative_disc
    return relative_disc
  end
  tmg=mR.tame_mult_grp
  wldg=mR.wild_mult_grp
  prime_power=Dict{NfOrdIdl, NfOrdIdl}()
  for (p,v) in lp
    prime_power[p]=p^v
  end
  fact=factor(m)

  for (p,v) in fact
    if v==1
      ap=n
      if isprime(n)
        ap-=1
      else
        el=mp\ideal(O,tmg[p].generators[1]) #The generator is totally positive, we modified it before
        q,mq=quo(R,GrpAbFinGenElem[el], false)
        ap-= order(q)
      end
      qw=divexact(degree(O), prime_decomposition_type(O,Int(p.minimum))[1][2])*ap
      abs_disc[p.minimum] = qw
      relative_disc[p] = ap
    else
      ap=n*v
      if isprime(n)
        ap-=v
      else
        if length(lp) > 1
          i_without_p = ideal(O,1)
          for (p2,vp2) in lp
            (p != p2) && (i_without_p *= prime_power[p2])
          end
          alpha, beta = idempotents(prime_power[p],i_without_p)
        end
        s=v
        @hassert :AbExt 1 s>=2
        els=GrpAbFinGenElem[]
        for k=2:v      
          s=s-1
          pk=p^s
          pv=pk*p
          gens=_1pluspk_1pluspk1(K, p, pk, pv, lp, prime_power, a,Int(n))
          for i=1:length(gens)
            push!(els,mp\ideal(O,gens[i]))
          end
          ap-=order(quo(R,els, false)[1])
          @hassert :AbExt 1 ap>0
        end
        if haskey(tmg, p)
          push!(els, mp\ideal(O,tmg[p].generators[1]))
        end
        ap-=order(quo(R, els, false)[1])
        @hassert :AbExt 1 ap>0
      end
      td=prime_decomposition_type(O,Int(p.minimum))
      np=fmpz(p.minimum)^(td[1][1]*length(td)*ap)
      abs_disc[p.minimum]=td[1][1]*length(td)*ap
      relative_disc[p]=ap
    end
  end
  C.relative_discriminant=relative_disc
  C.absolute_discriminant=abs_disc
  return C.relative_discriminant
  
end

##############################################################################
#
#  Is Abelian function
#
##############################################################################

@doc Markdown.doc"""
  isabelian(K::NfRel) -> Bool

Check if the extension is abelian over the coefficient ring.
The function is probabilistic.
"""
function isabelian(K::NfRel)
  return isabelian(K.pol, base_ring(K))
end

#TODO: consolidate with norm_group!!!!
@doc Markdown.doc"""
  isabelian(f::Nemo.Generic.Poly, K::Nemo.AnticNumberField) -> Bool

 > Check if the extension generated by a root of the irreducible polynomial $f$ over a number field $K$ is abelian
 > The function is probabilistic.

"""
function isabelian(f::Nemo.PolyElem, K::Nemo.AnticNumberField)
  
  O=maximal_order(K)
  d=discriminant(f)
  N=num(norm(K(d)))
  n=degree(f)
  
  inf_plc=real_places(K)
  m=ideal(O,O(d))
  lp=collect(keys(factor(n)))
  M=zero_matrix(FlintZZ,0,0)
  Grps=Any[]
  R=AbelianGroup(fmpz[])
  for i=1:length(lp)
    T,mT=ray_class_group_p_part(Int(lp[i]),m,inf_plc)
    if valuation(order(T),lp[i])<valuation(n,lp[i])
      return false
    end
    push!(Grps, [T,mT])
  end
  for i=1:length(lp)
    R=direct_product(R,Grps[i][1])
  end
  function mR(J::NfOrdIdl)
    x=(Grps[1][2]\J).coeff
    for i=2:length(lp)
      hcat!(x,((Grps[i][2])\J).coeff)
    end
    return R(x)
  end
 
  
  S,mS=snf(R)
  M=rels(S)
  
  p=1
  Ox,x=PolynomialRing(O,"y", cached=false)
  f1=Ox([O(coeff(f,i)) for i=0:n])
  
  determinant=order(S)
  new_mat=M

  B=log(abs(discriminant(O)))*degree(f)+log(N)
  B=4*B+2.5*degree(f)*degree(O)+5
  B=B^2
  
  #
  # Adding small primes until they generate the norm group
  #
  
  while determinant > n 
    p=next_prime(p)
    if p>B
      return false #Bach bound says that the norm group must be generated by primes $\leq B$
    end
    if !divisible(N,p)
      L=prime_decomposition(O,p)
      for i=1:length(L)
        F,mF=ResidueField(O,L[i][1])
        Fz,z= PolynomialRing(F,"z", cached=false)
        g=mF(f1)
        D=factor_shape(g)
        if length(D)>1
          return false
        end
        candidate=mR(((L[i][1])^first(keys(D))))
        new_mat=vcat(new_mat,(mS(candidate)).coeff)
        new_mat=hnf(new_mat)
        new_mat=sub(new_mat,1:ngens(S), 1:ngens(S))  
        determinant=abs(det(new_mat))
      end
    end
  end
  if determinant==n
    return true
  else 
    return false
  end

end

################################################################################
#
#  Norm group function
#
################################################################################

@doc Markdown.doc"""
    norm_group(K::NfRel{nf_elem}, mR::Hecke.MapRayClassGrp) -> Hecke.FinGenGrpAb, Hecke.FinGenGrpAbMap

    norm_group(K::NfRelNS{nf_elem}, mR::Hecke.MapRayClassGrp) -> Hecke.FinGenGrpAb, Hecke.FinGenGrpAbMap

Computes the subgroup of the Ray Class Group $R$ given by the norm of the extension.
"""
function norm_group(K::NfRel{nf_elem}, mR::Hecke.MapRayClassGrp, isabelian::Bool = true; of_closure::Bool = false)
  base_ring(K) == nf(mR.modulus_fin.order) || error("field has to be over the same field as the ray class group")
  return norm_group(K.pol, mR, isabelian, of_closure = of_closure)
end
function norm_group(K::NfRelNS{nf_elem}, mR::Hecke.MapRayClassGrp, isabelian::Bool = true; of_closure::Bool = false)
  base_ring(K) == nf(mR.modulus_fin.order) || error("field has to be over the same field as the ray class group")
  return norm_group([isunivariate(x)[2] for x = K.pol], mR, isabelian, of_closure = of_closure)
end
 
@doc Markdown.doc"""
    norm_group(f::Nemo.PolyElem, mR::Hecke.MapRayClassGrp, isabelian::Bool = true; of_closure::Bool = false) -> Hecke.FinGenGrpAb, Hecke.FinGenGrpAbMap

    norm_group(f::Array{PolyElem{nf_elem}, mR::Hecke.MapRayClassGrp, isabelian::Bool = true; of_closure::Bool = false) -> Hecke.FinGenGrpAb, Hecke.FinGenGrpAbMap

Computes the subgroup of the Ray Class Group $R$ given by the norm of the extension generated by a/the roots of $f$. If {{{isabelian}}} is set to true, then the code assumes the field to be
abelian, hence the algorithm stops when the quotient by the norm group has the correct order.
Even though the algorithm is probabilistic by nature, in this case the result is guaranteed.
If {{{of\_closure}}} is given, then the norm group of the splitting field of the polynomial(s)
is computed.
It is the callers responsibility to ensure that the ray class group passed in is large enough.
"""
function norm_group(f::Nemo.PolyElem, mR::Hecke.MapRayClassGrp, isabelian::Bool = true; of_closure::Bool = false)
  return norm_group([f], mR, isabelian, of_closure = of_closure)
end

function norm_group(f::Array{T, 1}, mR::Hecke.MapRayClassGrp, isabelian::Bool = true; of_closure::Bool = false) where T <: PolyElem{nf_elem}
  
  R = mR.header.domain
  O = mR.modulus_fin.order
  K = O.nf
  N = lcm([numerator(norm(K(discriminant(x)))) for x = f])
  N1 = fmpz(minimum(mR.modulus_fin))

  @assert all(x->base_ring(x) == K, f)

  n = lcm([degree(x) for x = f])
 
  if of_closure  
    #we cannot work in the quotient, it "could" be lcm(factorial(degree(x)) for x = f)
    Q,mQ=quo(R, elem_type(R)[])
  else
    Q,mQ=quo(R, n, false)
  end
  
  p = maximum(degree(x)+1 for x = f)
  
  listprimes = typeof(R[1])[]  
  
  #
  # Adding small primes until it stabilizes
  #
  
  max_stable = 2*n
  stable = max_stable
  denom = lcm([denominator(coeff(x, i)) for x in f for i = 1:degree(x) ])
  while true
    if isabelian && order(Q) == n
      break
    end
    if !isabelian && order(Q) <= n && stable <= 0
      break
    end
    p = next_prime(p)
    if !divisible(N,p) && !divisible(N1,p) && !divisible(denom, p)
      L = prime_decomposition(O,p,1)
      for i=1:length(L)
        candidate = mR\L[i][1]
        if iszero(mQ(candidate))
          stable -= 1
          continue
        end
        F,mF = ResidueFieldSmall(O, L[i][1])
        mFp = extend_easy(mF, K)  
        Fz, z = PolynomialRing(GF(Int(p), cached = false), "z", cached = false)
        all_deg = []
        #= the idea, taking 2 polys:
          f splits in d_i
          g splits in e_i
        Then, over an extensions of degree d_i an irreducible of degree e_i
        splits into factors of degree e_i/gcd(d_i, e_i) so there are gcd() many
        (but this is not used). The total degree over base field is then 
        d_i * e_i/gcd() = lcm(d_i, e_i)
        This can be iterated...
        =#
        for x = f
          g=Fz([coeff(mFp(coeff(x, i)), 0) for i = 0:degree(x)]) 
          D = factor_shape(g)
          push!(all_deg, [x[1] for x = D])
        end
        all_f = Set{Int}()
        for d = Iterators.product(all_deg...)
          push!(all_f, lcm(collect(d)))
        end
        if of_closure
          all_f = Set(lcm([x for x = all_f]))
        end
        for E = all_f
          candidate=E*candidate
          if !iszero(mQ(candidate) )
            Q, nQ = quo(Q, [mQ(candidate)])
            mQ = mQ*nQ
            push!(listprimes, candidate)
            stable = max_stable
          else
            stable -= 1
          end
        end  
      end
    end
  end
  
  #
  # Computing the Hermite normal form of the subgroup
  #
  subgrp=[el for el in listprimes]
  if !of_closure
    for i=1:ngens(R)
      push!(subgrp, n*R[i])
    end
  end
  return sub(R, subgrp, true)
end



function norm_group(mL::NfToNfMor, mR::Hecke.MapRayClassGrp, expected_degree::Int = 1)
  
  K = domain(mL)
  L = codomain(mL)
  R = domain(mR)
  O = maximal_order(K)
  N = minimum(mR.modulus_fin)

  els = GrpAbFinGenElem[]  

  #
  #  Adding small primes until it stabilizes
  #
  n = divexact(degree(L), degree(K))
  max_stable = 2*n
  stable = max_stable
  p = 2^10
  Q, mQ = quo(R, els, false)
  while true
    if order(Q) == expected_degree
      break
    end
    if order(Q) <= n && stable <= 0
      break
    end
    p = next_prime(p)
    while N % p == 0
      p = next_prime(p)
    end
    lP = prime_decomposition(O, p)
    for (P, e) in lP
      lQ = prime_decomposition_type(mL, P)
      s = gcd([x[1] for x in lQ])
      candidate = s*(mR\P) 
      if !iszero(mQ(candidate))
        push!(els, candidate)
        Q, mQ = quo(R, els, false)
        stable = max_stable
      else
        stable -= 1
      end
    end
  end
  return sub(R, els, !false)
end

@doc Markdown.doc"""
    maximal_abelian_subfield(::Type{ClassField}, K::AnticNumberField) -> ClassField

The maximal abelian subfield of $K$ as a class field, ie. the norm group
is computed and the corresponding {{{ray_class_field}}} created.
"""
function maximal_abelian_subfield(::Type{ClassField}, K::AnticNumberField)
  Zx, x = PolynomialRing(FlintZZ, cached = false)
  QQ = number_field(x-1)[1]
  R, mR = ray_class_group(discriminant(maximal_order(K))*maximal_order(QQ), infinite_places(QQ), n_quo = degree(K))
  f = NfToNfMor(QQ, K, K(1))
  N, mN = norm_group(f, mR)
  return ray_class_field(mR, quo(R, N)[2])
end

@doc Markdown.doc"""
    cyclotomic_field(::Type{ClassField}, n::Int) -> ClassField

The $n$-th cyclotomic field as a {{{ray_class_field}}}
"""
function cyclotomic_field(::Type{ClassField}, n::Int)
  Zx, x = PolynomialRing(FlintZZ, cached = false)
  QQ = number_field(x-1)[1]
  return ray_class_field(n*maximal_order(QQ), infinite_places(QQ))
end

function norm_group_map(R::ClassField{S, T}, r::Vector{<:ClassField}, map = false) where {S, T}
  @assert map != false || all(x -> base_ring(R) == base_ring(x), r)
#  @assert map == false && all(x -> base_ring(R) == base_ring(x), r)

  mR = defining_modulus(R)[1]
  @assert map != false || all(x->mR+defining_modulus(x)[1] == defining_modulus(x)[1], r)

  fR = compose(pseudo_inv(R.quotientmap), R.rayclassgroupmap)
  lp, sR = find_gens(MapFromFunc(x->preimage(fR, x), IdealSet(base_ring(R)), domain(fR)),
                             PrimesSet(100, -1), minimum(mR))
  if map == false                           
    h = [hom(sR, [preimage(compose(pseudo_inv(x.quotientmap), x.rayclassgroupmap), p) for p = lp]) for x = r]
  else
    h = [hom(sR, [preimage(compose(pseudo_inv(x.quotientmap), x.rayclassgroupmap), map(p)) for p = lp]) for x = r]
  end
  return h
end

function norm_group_map(R::ClassField, r::ClassField, map = false)
  return norm_group_map(R, [r], map)[1]
end

@doc Markdown.doc"""
    maximal_abelian_subfield(K::NfRel{nf_elem}; of_closure::Bool = false) -> ClassField
Using a probabilistic algorithm for the norm group computation, determine tha maximal
abelian subfield in $K$ over its base field. If {{{of_closure}}} is set to true, then
the algorithm is applied to the normal closure if $K$ (without computing it).
"""
function maximal_abelian_subfield(K::NfRel{nf_elem}; of_closure::Bool = false)
  zk = maximal_order(base_ring(K))
  d = ideal(zk, discriminant(K))
  try
    ZK = _get_maximal_order_of_nf_rel(K)
    d = ideal(zk, discriminant(ZK))
  catch e
    if !isa(e, AccessorNotSetError)
      rethrow(e)
    end
  end

  r1, r2 = signature(base_ring(K))
  C, mC = ray_class_group(d.num, infinite_places(base_ring(K))[1:r1], n_quo = degree(K))
  N, iN = norm_group(K, mC, of_closure = of_closure)
  return ray_class_field(mC, quo(C, N)[2])
end

@doc Markdown.doc"""
    maximal_abelian_subfield(A::ClassField, k::AnticNumberField) -> ClassField
The maximal abelian extension of $k$ contained in $A$. $k$ must be a subfield of
the base field of $A$.
"""
function maximal_abelian_subfield(A::ClassField, k::AnticNumberField)
  K = base_field(A)
  fl, mp = issubfield(k, K)
  @assert fl
  ZK = maximal_order(K)
  zk = maximal_order(k)
  # disc(ZK/Q) = N(disc(ZK/zk)) * disc(zk)^deg
  # we need the disc ZK/k, well a conductor.
  # I think for now, I cheat
  d = div(discriminant(ZK), discriminant(zk)^div(degree(K), degree(k)))
  mR1 = A.rayclassgroupmap
  mC = pseudo_inv(A.quotientmap)*mR1
  f_M0 = mR1.fact_mod
  # want m0 meet zk:
  f_m0 = typeof(f_M0)()
  for (P,e) = f_M0
    lp = prime_decomposition(zk, P.gen_one)
    p = first([x[1] for x = lp if valuation(mp(k(x[1].gen_two)), P) > 0])
    if haskey(f_m0, p)
      f_m0[p] += e
    else
      f_m0[p] = e
    end
  end
  
  expo = Int(exponent(codomain(A.quotientmap)))
  R, mR = Hecke.ray_class_group_quo(ZK, expo, f_M0, real_places(K))
  r, mr = Hecke.ray_class_group_quo(zk, expo * div(degree(K), degree(k)), f_m0, real_places(k))
  lP, gS = Hecke.find_gens(mR, coprime_to = minimum(mR1.modulus_fin))
  listn = [norm(mp, x) for x in lP]
  # Create the map between R and r by taking norms
  proj = hom(gS, [mr\x for x in listn])
  #compute the norm group of A in R
  proj1 = hom(gS, [mC\x for x in lP])
  S, mS = kernel(proj1)
  mS1 = Hecke.compose(mS, proj)
  G, mG = Hecke.cokernel(mS1)
  return ray_class_field(mr, mG)
  
end

@doc Markdown.doc"""
    ray_class_field(K::NfRel{nf_elem}) -> ClassField
For a (relative) abelian extension, compute an abstract representation
as a class field. 
"""
function ray_class_field(K::NfRel{nf_elem})
  C = maximal_abelian_subfield(K)
  @assert degree(C) <= degree(K)
  if degree(C) != degree(K)
    error("field is not abelian")
  end
  return C
end

@doc Markdown.doc"""
    genus_field(A::ClassField, k::AnticNumberField) -> ClassField
The maximal extension contained in $A$ that is the compositum of $K$
with an abelian extension of $k$.
"""
function genus_field(A::ClassField, k::AnticNumberField)
  B = maximal_abelian_subfield(A, k)
  K = base_field(A)
  fl, mp = issubfield(k, K)
  @assert fl
  h = norm_group_map(A, B, x -> norm(mp, x))
  return ray_class_field(A.rayclassgroupmap, GrpAbFinGenMap(A.quotientmap * quo(domain(h), kernel(h)[1])[2]))
end

@doc Markdown.doc"""
    subfields(C::ClassField, d::Int) -> Array{ClassField, 1}
Find all subfields of $C$ of degree $d$ as class fields.    
Note: this will not find all subfields over $Q$, but only the ones
sharing the same base field.
"""
function subfields(C::ClassField, d::Int) 
  mR = C.rayclassgroupmap
  mQ = C.quotientmap

  return ClassField[ray_class_field(mR, GrpAbFinGenMap(mQ*x)) for x = subgroups(codomain(mQ), index = d, fun = (x,y) -> quo(x, y, false)[2])]
end

@doc Markdown.doc"""
    subfields(C::ClassField) -> Array{ClassField, 1}
Find all subfields of $C$ as class fields.    
Note: this will not find all subfields over $Q$, but only the ones
sharing the same base field.
"""
function subfields(C::ClassField)
  mR = C.rayclassgroupmap
  mQ = C.quotientmap

  return ClassField[ray_class_field(mR, GrpAbFinGenMap(mQ*x)) for x = subgroups(codomain(mQ), fun = (x,y) -> quo(x, y, false)[2])]
end

@doc Markdown.doc"""
    normal_closure(C::ClassField) -> ClassField
For a ray class field $C$ extending a normal base field $k$, compute the
normal closure over $Q$.
"""
function normal_closure(C::ClassField)
  c = defining_modulus(C)
  k = base_field(C)
  if length(c[2]) > 0
    inf = real_places(k)
  else
    inf = InfPlc[]
  end
  aut = automorphisms(k)
  @assert length(aut) == degree(k)
  fin = lcm([induce_image(x, c[1]) for x = aut])

  D = ray_class_field(fin, inf, n_quo = Int(exponent(codomain(C.quotientmap))))
  h = norm_group_map(D, C)
  aut1 = small_generating_set(aut)
  act = Hecke.induce_action(D, aut1)
  k = kernel(h, true)[1]

  k = intersect([x(k)[1] for x = act])

  q, mq = quo(domain(h), k)
  return ray_class_field(D.rayclassgroupmap, GrpAbFinGenMap(D.quotientmap * mq))
end

function rewrite_with_conductor(C::ClassField)
  c, inf = conductor(C)
  if defining_modulus(C) == (c, inf)
    return C
  end
  E = ray_class_field(C.rayclassgroupmap)
  D = ray_class_field(c, inf, n_quo = Int(exponent(codomain(C.quotientmap))))
  h = norm_group_map(E, D)
  q, mq = quo(codomain(h), h(GrpAbFinGenMap(E.quotientmap)(kernel(GrpAbFinGenMap(C.quotientmap), true)[1])[1])[1])
  C = ray_class_field(D.rayclassgroupmap, GrpAbFinGenMap(D.quotientmap*mq))
  return C
end

function induce_action(C::ClassField, Aut::Array{Hecke.NfToNfMor, 1} = Hecke.NfToNfMor[])
  return induce_action(C.rayclassgroupmap, Aut, C.quotientmap)
end

@doc Markdown.doc"""
    isnormal(C::ClassField) -> Bool
For a class field $C$ defined over a normal base field $k$, decide
if $C$ is normal over $Q$.
"""
function isnormal(C::ClassField)

  K = base_field(C)
  aut = automorphisms(K)
  if length(aut) == degree(K)
    return isnormal_easy(C)
  else 
    return isnormal_difficult(C)
  end
  
end

function isnormal_easy(C::ClassField)
  aut = automorphisms(base_field(C))
  c, inf = conductor(C)
  if any(x-> c != induce_image(x, c), aut)
    return false
  end
  s1 = Set(inf)
  if any(x -> s1 != Set(induce_image(x, y) for y = s1), aut)
    return false
  end
  C = rewrite_with_conductor(C)
  mR = C.rayclassgroupmap
  new_aut = small_generating_set(aut)
  act = induce_action(mR, new_aut)
  mk = kernel(GrpAbFinGenMap(C.quotientmap), true)[2]
  #normal iff kernel is invariant
  return isstable(act, mk)
end

function isnormal_difficult(C::ClassField)
  
  #First, I check that the norm group of the splitting field 
  #of the base field contains C
  
  K = base_field(C)
  nK = degree(K)
  O = maximal_order(K)
  f = K.pol
  I = ideal(O, discriminant(O))
  r, mr = ray_class_group(I, real_places(K))
  Kt, t = PolynomialRing(K, "t", cached = false)
  g = divexact(evaluate(f, t), t - gen(K))
  G, mG = norm_group(g, mr, of_closure = true)
  k, mk = cokernel(mG)
  C1 = ray_class_field(mr, mk)
  if rem(degree(C), degree(C1))!= 0 || !issubfield(C1, C)
    return false
  end
  if degree(C1) == degree(C)
    return true
  end
  
  # Claus's Idea: I don't want to compute the extension, I want to test the stability of the modulus under the action of the 
  # automorphisms, so only the totally split primes! 
  # In other words, I need to check that given a totally split prime p, all the primes lying
  # over p are either all zero or all non-zero in the ray class field 
  
  p = 1
  d = (discriminant(O)^degree(C1))*numerator(norm(evaluate(FacElem(discriminant(C1)))))
  ld = (ceil(fmpz, log(d)))
  n = degree(C1)*nK
  bound = (4*ld + 2*n +5)^2
  mp = pseudo_inv(C.quotientmap) * C.rayclassgroupmap
  while p < bound 
    p = next_prime(p)
    if divisible(discriminant(O), p)
      continue
    end
    lp = prime_decomposition(O, p)
    if !all([q[1].splitting_type[2] == 1 for q in lp])
      continue
    end
    q = lp[1][1]
    fl = iszero(mp\q)
    for i = 2:nK
      if fl != iszero(mp\lp[i][1])
        return false
      end  
    end
  end
  return true
end


@doc Markdown.doc"""
    iscentral(C::ClassField) -> Bool
For a class field $C$ defined over a normal base field $k$, decide
if $C$ is central over $Q$.
"""
function iscentral(C::ClassField)
  aut = automorphisms(base_field(C))
  c, inf = conductor(C)

  if any(x-> c != induce_image(x, c), aut)
    return false
  end
  s1 = Set(inf)
  if any(x -> s1 != Set(induce_image(x, y) for y = s1), aut)
    return false
  end
  C = rewrite_with_conductor(C)
  mR = C.rayclassgroupmap
  act = induce_action(mR, aut)
  k = kernel(GrpAbFinGenMap(C.quotientmap), true)
  #central iff action is trivial on the kernel
  g = [k[2](k[1][i]) for i = 1:ngens(k[1])]

  return all(x -> all(y -> x(y) == y, g), act)
end

function lcm(A::AbstractArray{<:NfAbsOrdIdl})
  a = first(A)
  a = ideal(order(a), 1)
  for b = A
    a = lcm(a, b)
  end
  return a
end

@doc Markdown.doc"""
    isunivariate(f::Generic.MPoly{nf_elem}) -> Bool, PolyElem{nf_elem}
Tests if $f$ involves only one variable. If so, return a corresponding univariate polynomial.
"""
function isunivariate(f::Generic.MPoly{nf_elem})
  kx, x = PolynomialRing(base_ring(f), "x", cached = false)
  if ngens(parent(f)) == 1
    f1 = kx()
    for i = 1:f.length
      setcoeff!(f1, Int(f.exps[1, i]), f.coeffs[i])
    end
    return true, f1
  end
  if f.length == 0
    @assert iszero(f)
    return true, kx(0)
  end
  n = ngens(parent(f))
  i = 1
  while i <= n && iszero(f.exps[i, :])
    i += 1
  end
  j = n
  while j >= 1 && iszero(f.exps[j, :])
    j -= 1
  end
  if i != j
    return false, x
  end
  f1 = kx()
  for j = 1:f.length
    setcoeff!(f1, Int(f.exps[i, j]), f.coeffs[j])
  end
  return true, f1
end
#TODO: should be done in Nemo/AbstractAlgebra s.w.
#      needed by ^ (the generic power in Base using square and multiply)
Base.copy(f::Generic.MPoly) = deepcopy(f)
Base.copy(f::Generic.Poly) = deepcopy(f)


@doc Markdown.doc"""
    lorenz_module(k::AnticNumberField, n::Int) -> NfOrdIdl
Finds an ideal $A$ s.th. for all positive units $e = 1 \bmod A$ we have that 
$e$ is an $n$-th power. Uses Lorenz, number theory, 9.3.1.
If {{{containing}}} is set, it has to be an integral ideal. The resulting ideal will be
a multiple of this.
"""
function lorenz_module(k::AnticNumberField, n::Int; containing=false)
  lf = factor(n)
  return Base.reduce(lcm, [lorenz_module_pp(k, Int(p), l, containing = containing) for (p,l) = lf.fac])
end

#TODO: is this the right interface???
@doc Markdown.doc"""
    (::NfAbsOrdIdlSet)(m::Map, I::NfOrdIdl) -> NfOrdIdl
Given an embedding $m:k\to K$ of number fields and an ideal $I$ in $k$,
find the ideal above $I$ in $K$.
"""
function (I::NfAbsOrdIdlSet{Nemo.AnticNumberField,Nemo.nf_elem})(mp::Map, i::NfOrdIdl)
  assure_2_normal(i)
  return ideal(order(I), i.gen_one, order(I)(mp(i.gen_two.elem_in_nf)))
end

#TODO: write code (map?) to change polynomial rings other than evaluate

@doc Markdown.doc"""
    norm(m::T, a::nf_elem) where T <: Map{AnticNumberField, AnticNumberField} -> nf_elem
Given an embedding $m:k\to K$ of number fields and an element in $K$, find the norm
$N_{K/k}(a)$.
"""
function norm(m::T, a::nf_elem) where T <: Map{AnticNumberField, AnticNumberField}
  K = codomain(m)
  #= shamelessly from Trager:
           K  Then: K = Q(c) = k(c) = Q(b)(c)
           |        f(c) = 0 in Q[t]
      k    |        h(c) = 0 in k[t]. Trager: N(h) = f. eta in Q[t] s.th. m(b) = eta(c) 
      |    |        h = gcd(b - eta, f)
      Q    Q  so N_K/k(a) = res(h, a)
  =#    
  @assert K == parent(a)
  k = domain(m)
  kt, t = PolynomialRing(k, cached = false)
  Qt = parent(K.pol)
  h = gcd(gen(k) - evaluate(Qt(m(gen(k))), t), evaluate(K.pol, t))
  return resultant(h, mod(evaluate(Qt(a), t), h))
end

function norm(m::T, a::FacElem{nf_elem, AnticNumberField}) where T <: Map{AnticNumberField, AnticNumberField}
  K = codomain(m)
  @assert K == base_ring(a)
  k = domain(m)
  kt, t = PolynomialRing(k, cached = false)
  Qt = parent(K.pol)
  h = gcd(gen(k) - evaluate(Qt(m(gen(k))), t), evaluate(K.pol, t))
  d = Dict{nf_elem, fmpz}()
  for (e,v) = a.fac
    n = resultant(h, mod(evaluate(Qt(e), t), h))
    if haskey(d, n)
      d[n] += v
    else
      d[n] = v
    end
  end
  return FacElem(d)
end


@doc Markdown.doc"""
    norm(m::T, I::NfOrdIdl) where T <: Map{AnticNumberField, AnticNumberField} -> NfOrdIdl
Given an embedding $m:k\to K$ of number fields and an integral ideal in $K$, find the norm
$N_{K/k}(I)$.
"""
function norm(m::T, I::NfOrdIdl) where T <: Map{AnticNumberField, AnticNumberField}
  K = codomain(m)
  @assert K == nf(order(I))
  k = domain(m)
  zk = maximal_order(k)
  if I.is_principal == 1
    if isdefined(I, :princ_gen)
      return ideal(zk, zk(norm(m, (I.princ_gen).elem_in_nf)))
    elseif isdefined(J,:princ_gen_special)
      el = J.princ_gen_special[2] + J.princ_gen_special[3]
      return ideal(zk, zk(norm(m, el)))
    end
  end
  assure_2_normal(I)
  J = ideal(zk, I.gen_one^div(degree(K), degree(k)), zk(norm(m, I.gen_two.elem_in_nf)))
  J.gens_normal = I.gens_normal
  return J
end

function norm(m::T, I::NfOrdFracIdl) where T <: Map{AnticNumberField, AnticNumberField}
  return norm(m, numerator(I))//denominator(I)^div(degree(codomain(m)), degree(domain(m)))
end

#TODO: intersect_nonindex uses a worse algo in a more special case. Combine.
#  for prime ideals, the gcd's can be done in F_p/ F_q hence might be faster
@doc Markdown.doc"""
    minimum(m::T, I::NfOrdIdl) where T <: Map{AnticNumberField, AnticNumberField} -> NfOrdIdl
Given an embedding $m:k\to K$ of number fields and an integral ideal in $K$, find the 
intersect $I \cap \Z_k$.
"""
function minimum(m::T, I::NfOrdIdl) where T <: Map{AnticNumberField, AnticNumberField}
  K = codomain(m)
  @assert K == nf(order(I))
  k = domain(m)
  zk = maximal_order(k)
  assure_2_normal(I) # basically implies order(I) is maximal
  if !isone(gcd(minimum(I), index(order(I))))
    bk = map(m, basis(maximal_order(k), k))
    bK = map(K, basis(I))
    d = lcm(lcm(map(denominator, bk)), lcm(map(denominator, bK)))
    F = FreeModule(FlintZZ, degree(K))
    sk = sub(F, [F(matrix(FlintZZ, 1, degree(K), coeffs(d*x))) for x = bk])
    sK = sub(F, [F(matrix(FlintZZ, 1, degree(K), coeffs(d*x))) for x = bK])
    m = intersect(sk[1], sK[1])
    return ideal(zk, [zk(collect(x.v)) for x = map(m[2], gens(m[1]))])
  end

  @assert K == nf(order(I))
  k = domain(m)
  kt, t = PolynomialRing(k, cached = false)
  Qt = parent(K.pol)
  h = gcd(gen(k) - evaluate(Qt(m(gen(k))), t), evaluate(K.pol, t))
  g, ai, _ = gcdx(evaluate(Qt(I.gen_two.elem_in_nf), t) % h, h)
  @assert g == 1
  #so ai * a = 1 in K/k
  c = content_ideal(ai, zk)
  n,d = integral_split(c)
  J = ideal(zk, I.gen_one) + d
  J.gens_normal = I.gens_normal
  return J
end

function minimum(m::T, I::NfOrdFracIdl) where T <: Map{AnticNumberField, AnticNumberField}
  return minimum(m, numerator(I))//denominator(I)
end

#TODO: change order!!! this only works for maximal orders
function Base.intersect(I::NfAbsOrdIdl, R::NfAbsOrd)
  @assert ismaximal(R)
  if number_field(R) == number_field(order(I))
    return I
  end
  fl, m = issubfield(number_field(R), number_field(order(I)))
  @assert fl
  return minimum(m, I)
end
Base.intersect(R::NfAbsOrd, I::NfAbsOrdIdl) = intersect(I, R)

function Base.intersect(I::NfOrdFracIdl, R::NfAbsOrd)
  @assert ismaximal(R)
  n, d = integral_split(I)
  return intersect(n, R)
end

Base.intersect(R::NfAbsOrd, I::NfOrdFracIdl) = intersect(I, R)

@doc Markdown.doc"""
    content_ideal(f::PolyElem{nf_elem}, R::NfAbsOrd) -> NfAbsOrdIdl
The fractional $R$-ideal generated by the coefficients of $f$.    
"""
function content_ideal(f::PolyElem{nf_elem}, R::NfAbsOrd)
  @assert number_field(R) == base_ring(f)
  i = sum(coeff(f, i)*R for i=0:degree(f) if !iszero(coeff(f, i)))
  return i    
end

@doc Markdown.doc"""
    content_ideal(f::PolyElem{NfAbsOrdElem}) -> NfAbsOrdIdl
The ideal generated by the coefficients of $f$.    
"""
function content_ideal(f::PolyElem{NfAbsOrdElem})
  R = base_ring(f)
  return sum(coeff(f, i)*R for i=0:degree(f) if !iszero(coeff(f, i)))
end

#TODO: check the math
# - I think in the p==2 l is too large in general
# - I probably only the p-part of c is needed
# - possibly even only the p-th cyclo field, although I really don't know
function lorenz_module_pp(k::AnticNumberField, p::Int, l::Int; containing=false)
  if p == 2
    l = max(l, lorenz_eta_level(k))
    l += 1
  end
  n = p^l
  C = cyclotomic_extension(k, n)
  Ka = C.Ka
  ZK = maximal_order(Ka)
  c, mc = class_group(Ka)
  lp = prime_decomposition(ZK, p)
  S = [P[1] for P = lp]
  s = [P[1] for P = prime_decomposition(maximal_order(k), p)]

  fc = false
  if containing != false
    @assert typeof(containing) == NfOrdIdl
    fc = factor(containing)
    s = union(s, collect(keys(fc)))
    fc = factor(parent(S[1])(C.mp[2], containing))
    S = union(S, collect(keys(fc)))
  end
  Q, mQ = quo(c, [mc\P for P = S])

  a, _ = find_gens(pseudo_inv(mc)*mQ, PrimesSet(degree(k), -1), p*numerator(discriminant(Ka)))
  S = Set(intersect_nonindex(C.mp[2], P) for P = a)
  union!(S, s)

  d = Dict{typeof(first(S)), Int}()
  for P = S
    # need x = 1 mod P^l -> x = y^n in k_P
    # Newton: x^n-1 has derivative nx^(n-1) and need l > 2*val(n, P)
    v = 2*valuation(p, P) + 1
    if containing != false
      v = max(v, valuation(containing, P))
    end
    d[P] = v
  end
  return numerator(evaluate(FacElem(d), coprime = true))  
end

function lorenz_eta_level(k::AnticNumberField)
  # find max r s.th. eta_r in k, eta_(r+1) not in k
  # where eta_r = (zeta_(2^r) + 1/zeta_(2^r))
  r = 2
  x = PolynomialRing(FlintZZ, cached = false)[2]
  while true
    @show f = cos_minpoly(2^r, x)
    if hasroot(f, k)[1]
      return r-1
    end
    @show r += 1
  end
end
