
add_verbose_scope(:BrauerObst)

###############################################################################
#
#  Brauer obstruction: interface
#
###############################################################################

function check_Brauer_obstruction(list::Vector{FieldsTower}, L::Main.ForeignGAP.MPtr, i::Int, invariants::Vector{Int})
  d = degree(list[1])
  common_degree = ppio(invariants[end], d)[1]
  if isone(common_degree)
    return list
  end
  fac = factor(common_degree)
  for (p, v) in fac
    if length(invariants) == 1 || iscoprime(invariants[end-1], p)
      if v > 1
        list = check_Brauer_obstruction_pp(list, L, i, Int(p), v)
      else
        list = _Brauer_prime_case(list, L, i, Int(p))
      end
    else
      #The extension is not cyclic. I need to search for a normal cyclic subextension.
      #I list the subgroup of the derived subgroup, sieve for the one that are normal in the entire group
      #and then take the maximal ones. I need to check all of them.
      @show "here!"
      subs, target_grp = find_subgroups_cyclic_in_derived(L, i, p)
      @show subs, target_grp
      for i = 1:length(subs)
        new_target = GAP.Globals.FactorGroup(target_grp, subs[i])
        L1 = GAP.Globals.DerivedSeries(new_target)
        order = divexact(prod(invariants), GAP.gap_to_julia(Int, GAP.Globals.Size(subs[i])))
        if order == p
          list =  _Brauer_prime_case(list, L1, length(L)-1, Int(p))
        else
          list = check_Brauer_obstruction_pp(list, L1, length(L)-1, Int(p), Int(valuation(order, p)))
        end
      end
    end
  end
  if length(invariants) == 1 && isprime_power(invariants[1])
    for el in list
      el.has_info = true
    end
  end
  return list
end

function find_subgroups_cyclic_in_derived(L::Main.ForeignGAP.MPtr, i::Int, p::fmpz)
  proj = GAP.Globals.NaturalHomomorphismByNormalSubgroup(L[1], L[i+1])
  target_grp = GAP.Globals.ImagesSource(proj)
  normal_subgroups = GAP.Globals.NormalSubgroups(target_grp)
  mH1 = GAP.Globals.NaturalHomomorphismByNormalSubgroup(target_grp, GAP.Globals.Image(proj, L[i]))
  G = GAP.Globals.ImagesSource(mH1)
  K = GAP.Globals.Kernel(mH1)
  normal_cyclic_and_contained = Main.ForeignGAP.MPtr[]
  for i = 1:length(normal_subgroups)
    g = normal_subgroups[i]
    if !GAP.Globals.IsSubgroup(K, g)
      continue
    end
    fg = GAP.Globals.FactorGroup(K, g)
    order = fmpz(GAP.gap_to_julia(Int, GAP.Globals.Size(fg)))
    np = remove(order, p)[2]
    if isone(np) && GAP.Globals.IsCyclic(fg)
      push!(normal_cyclic_and_contained, g)
    end  
  end
  #Almost done. I only want the minimal ones, so I need to sieve.
  res = Main.ForeignGAP.MPtr[]
  for i = 1:length(normal_cyclic_and_contained)
    g = normal_cyclic_and_contained[i]
    found = false
    for j = 1:length(normal_cyclic_and_contained)
      if j != i && GAP.Globals.IsSubgroup(g, normal_cyclic_and_contained[j])
        found = true
        break
      end
    end
    if !found
      push!(res, g)
    end
  end
  return res, target_grp
end
###############################################################################
#
#  Function to check the cocycle condition
#
###############################################################################

function check_cocycle(G::Array{NfToNfMor, 1}, Coc::Function, d::Int)
  
  K = domain(G[1])
  O = maximal_order(K)
  T, mT = torsion_unit_group(O)
  zeta = mT(divexact(order(T), d)*T[1])
  @assert zeta^d == 1
  for g1 in G
    zeta1 = O(g1(K(zeta)))
    # I need the discrete logarithm with respect to zeta
    i = 1
    a = zeta
    while a != zeta1
      a *= zeta
      i += 1
    end
    expzeta1 = i
    @assert zeta^i == zeta1
    for g2 in G
      for g3 in G
        lhs = mod(Coc(g1, g2*g3) + expzeta1*Coc(g2, g3), d)
        rhs = mod(Coc(g1*g2, g3) + Coc(g1, g2), d)
        @assert lhs == rhs
      end
    end
  end
  return true

end

###############################################################################
#
#  P-Sylow subgroup
#
###############################################################################

function pSylow(Gperm::Main.ForeignGAP.MPtr, permGAP::Vector{Main.ForeignGAP.MPtr}, G::Vector{NfToNfMor}, p::Int)
  p2 = ispower(length(G))[2]
  if p == p2
    return G
  end
  H = GAP.Globals.SylowSubgroup(Gperm, p)
  lGp = GAP.Globals.Size(H)
  Gp = Array{Hecke.NfToNfMor,1}(undef, lGp)
  j = 1
  for ind = 1:length(G)
    if j > lGp
      break
    end
    if GAP.Globals.IN(permGAP[ind], H)
      Gp[j] = G[ind]
      j += 1
    end
  end
  return Gp  
end

function pSylow(G::Vector{NfToNfMor}, p::Int)
  com, uncom = ppio(length(G), p)
  if uncom == 1
    return G
  end
  permGC = _from_autos_to_perm(G) 
  Gperm = _perm_to_gap_grp(permGC)
  PermGAP = Vector{Main.ForeignGAP.MPtr}(undef, length(permGC))
  for w = 1:length(permGC)
    PermGAP[w] = _perm_to_gap_perm(permGC[w])
  end
  return pSylow(Gperm, PermGAP, G, p)
end

###############################################################################
#
#  Cocycle computation: prime case
#
###############################################################################

function _find_exp(x::Main.ForeignGAP.MPtr, y::Main.ForeignGAP.MPtr)
  # I want to find i such that x^i = y
  i = 1
  z = GAP.Globals.ShallowCopy(x)
  while z != y
    z = z*x
    i += 1
  end 
  #@assert x^i == y
  return i
end

function _autos_to_check(G::Main.ForeignGAP.MPtr, E::Main.ForeignGAP.MPtr, mG::Main.ForeignGAP.MPtr)
  AutG = GAP.Globals.AutomorphismGroup(G)
  AutE = GAP.Globals.AutomorphismGroup(E)
  #I want to construct the map between the automorphism groups. The kernel is charachteristic!
  gens = GAP.Globals.GeneratorsOfGroup(AutE)
  ind_auts = Array{Main.ForeignGAP.MPtr, 1}(undef, length(gens))
  for s = 1:length(gens)
    ind_auts[s] = GAP.Globals.InducedAutomorphism(mG, gens[s])
  end
  S = GAP.Globals.Subgroup(AutG, GAP.julia_to_gap(ind_auts))
  T = GAP.Globals.List(GAP.Globals.RightTransversal(AutG, S))
  return GAP.gap_to_julia(T)
end

function cocycle_computation(L::Main.ForeignGAP.MPtr, i::Int)

  proj = GAP.Globals.NaturalHomomorphismByNormalSubgroup(L[1], L[i+1])
  target_grp = GAP.Globals.ImagesSource(proj)
  mH1 = GAP.Globals.NaturalHomomorphismByNormalSubgroup(target_grp, GAP.Globals.Image(proj, L[i]))
  H1 = GAP.Globals.ImagesSource(mH1)
  K = GAP.Globals.Kernel(mH1)
  #@assert (GAP.Globals.IsCyclic(K)).ptr == GAP.Globals.ReturnTrue().ptr
  # The kernel is cyclic by hypothesis, but Gap represent it as a pc group with more than one generator.
  # Brute force at the moment.
  gen = GAP.Globals.MinimalGeneratingSet(K)[1]
    
  Elems = GAP.Globals.Elements(H1)
  MatCoc = Array{Int, 2}(undef, length(Elems), length(Elems))
  Preimags = Vector{Main.ForeignGAP.MPtr}(undef, length(Elems))
  for i = 1:length(Elems)
    Preimags[i] = GAP.Globals.PreImagesRepresentative(mH1, Elems[i])
  end
  for i = 1:length(Elems)
    x1 = Preimags[i]
    for j = 1:length(Elems)
      y1 = Preimags[j]
      xy = Elems[i] * Elems[j]
      k = 1
      while Elems[k] != xy
        k += 1
      end
      xy1 = Preimags[k]
      MatCoc[i,j] = _find_exp(gen, x1*y1*GAP.Globals.Inverse(xy1))
    end
  end
  local cocycle
  let Elems = Elems, MatCoc = MatCoc
    function cocycle(x::Main.ForeignGAP.MPtr, y::Main.ForeignGAP.MPtr)  
      i = 1
      while Elems[i] != x
        i += 1
      end
      j = 1
      while Elems[j] != y
        j += 1
      end
      return MatCoc[i, j]
    end
  end
  
  autos = _autos_to_check(H1, target_grp, mH1)
  return mH1, autos, cocycle

end

function _reduce_to_prime(L::Main.ForeignGAP.MPtr, i::Int, d::Int)

  p = ispower(d)[2]
  G = GAP.Globals.FactorGroup(L[1], L[i+1]) 
  L1 = GAP.Globals.DerivedSeries(G)
  mH1 = GAP.Globals.NaturalHomomorphismByNormalSubgroup(G, L1[end-1])
  K = GAP.Globals.Kernel(mH1)
  gens = GAP.Globals.MinimalGeneratingSet(K)
  @assert length(gens) == 1
  gens[1] = gens[1]^divexact(d, p) 
  S = GAP.Globals.Subgroup(G, gens)
  Q = GAP.Globals.FactorGroup(G, S)
  return GAP.Globals.DerivedSeries(Q)
  
end

###############################################################################
#
#  Brauer obstruction using Crossed Product Algebras: degree 2 case
#
###############################################################################

function _Brauer_at_two(list::Vector{FieldsTower}, L::Main.ForeignGAP.MPtr, i::Int)
  mH, autos, _cocycle_values = cocycle_computation(L, i)
  domcoc = GAP.Globals.ImagesSource(mH)
  admit_ext = falses(length(list))
  for t = 1:length(list)
    @vprint :Fields 1 "$(Hecke.set_cursor_col())$(Hecke.clear_to_eol())Fields to test: $(length(list)-t+1)"
    admit_ext[t] = _Brauer_no_extend(list[t], mH, autos, _cocycle_values, domcoc, 2)
  end
  @vprint :Fields 1 "$(Hecke.set_cursor_col())$(Hecke.clear_to_eol())"
  return list[findall(admit_ext)]
end

###############################################################################
#
#  Brauer Obstruction: prime case
#
###############################################################################
function assure_automorphisms(T::FieldsTower)
  assure_automorphisms(T.field, T.generators_of_automorphisms)
end

function assure_automorphisms(K::AnticNumberField, gens::Vector{NfToNfMor})
  try
    _get_automorphisms_nf(K)::Vector{NfToNfMor}
  catch e
    if !isa(e, AccessorNotSetError)
      rethrow(e)
    end
    auts = closure(gens, degree(K))
    _set_automorphisms_nf(K, auts)
  end
  return nothing
end


function _Brauer_prime_case(list::Vector{FieldsTower}, L::Main.ForeignGAP.MPtr, i::Int, p::Int)
  
  if p == 2
    return _Brauer_at_two(list, L, i)
  end
  list1 = falses(length(list))  
  mH, autos, coc = cocycle_computation(L, i)
  H = GAP.Globals.ImagesSource(mH)
  for t = 1:length(list)
    @vprint :Fields 1 "$(Hecke.set_cursor_col())$(Hecke.clear_to_eol())Fields to test: $(length(list)-t+1)"
    assure_automorphisms(list[t])
    K = list[t].field
    lp = ramified_primes(list[t])
    if all(x -> (isone(mod(x, p)) || x == p), lp)
      #no need to extend the field with the roots of unity!
      list1[t] = _Brauer_no_extend(list[t], mH, autos, coc, H, p)
      continue
    end 
    Kc = _ext_cycl(list[t].generators_of_automorphisms, p)
    K1 = Kc.Ka
    autsK = automorphisms(K, copy = false)
    autsK1 = automorphisms(K1, copy = false)
    restr = restriction(autsK1, autsK, Kc.mp[2])
    #I construct the group and the isomorphisms between the automorphisms and the gap group.
    permGC = _from_autos_to_perm(autsK) 
    Gperm = _perm_to_gap_grp(permGC)
    d = discriminant(K.pol)
    d1 = discriminant(K1.pol)
    Pcomp = 2
    while iszero(mod(numerator(d), Pcomp)) || iszero(mod(numerator(d1), Pcomp)) || iszero(mod(p, Pcomp))
      Pcomp = next_prime(Pcomp)
    end
    R = GF(Pcomp, cached = false)
    Rx = PolynomialRing(R, "x", cached = false)[1]
    fmod = Rx(K.pol)
    dautsK1 = Dict{gfp_poly, Int}()
    for w = 1:length(autsK1)
      dautsK1[Rx(autsK1[w].prim_img)] = w
    end 
    iso = GAP.Globals.IsomorphismGroups(Gperm, H)
    ElemGAP = Vector{Main.ForeignGAP.MPtr}(undef, length(permGC))
    for w = 1:length(permGC)
      ElemGAP[w] = GAP.Globals.Image(iso, _perm_to_gap_perm(permGC[w]))
    end
    list[t].imgs_autos = ElemGAP
    #Restrict to the p-Sylow
    #Unfortunately, I need to compute the group structure.
    Gp = pSylow(autsK1, p)
    obstruction = false
    auts_for_conductor = Vector{Main.ForeignGAP.MPtr}()
    for g in autos
      #I create the cocycle
      local cocycle
      let restr = restr, dautsK1 = dautsK1, g = g, ElemGAP = ElemGAP, coc = coc, p = p, Rx = Rx
        function cocycle(aut1::gfp_poly, aut2::gfp_poly)
          s1 = restr[dautsK1[aut1]]
          a1 = GAP.Globals.Image(g, ElemGAP[s1])
          s2 = restr[dautsK1[aut2]]
          b1 = GAP.Globals.Image(g, ElemGAP[s2])
          rescoc = coc(a1, b1)
          return mod(rescoc, p)::Int
        end
      end
      
      if cpa_issplit(K1, Gp, cocycle, p, Rx)
        obstruction = true
        push!(auts_for_conductor, g)
      end
    
    end
    #If I am here, all the algebras don't split. I return false
    if obstruction
      list[t].auts_for_conductors = auts_for_conductor
      list[t].proj_ext = mH
      list1[t] = true
    end
  end
  @vprint :Fields 1 "$(Hecke.set_cursor_col())$(Hecke.clear_to_eol())"
  return list[findall(list1)]

end

function _Brauer_no_extend(x::FieldsTower, mH, autos, _cocycle_values, domcoc, p)
  K = x.field
  OK = maximal_order(K)
  GC = automorphisms(K, copy = false)
  d = discriminant(K.pol)
  Pcomp = 2
  while iszero(mod(numerator(d), Pcomp)) || iszero(mod(p, Pcomp))
    Pcomp = next_prime(Pcomp)
  end
  R = GF(Pcomp, cached = false)
  Rx = PolynomialRing(R, "x", cached = false)[1]
  DGCvect = Vector{Tuple{gfp_poly, Int}}(undef, length(GC))
  for i = 1:length(GC)
    DGCvect[i] = (Rx(GC[i].prim_img), i)
  end
  DGC = Dict{gfp_poly, Int}(DGCvect)
  permGC = _from_autos_to_perm(GC) #TODO: Improve a little.
  Gperm = _perm_to_gap_grp(permGC)
  PermGAP = Vector{Main.ForeignGAP.MPtr}(undef, length(permGC))
  for w = 1:length(permGC)
    PermGAP[w] = _perm_to_gap_perm(permGC[w])
  end
  #Restrict to the p-Sylow
  Gp = pSylow(Gperm, PermGAP, GC, p)
  iso = GAP.Globals.IsomorphismGroups(Gperm, domcoc)
  ElemGAP = Vector{Main.ForeignGAP.MPtr}(undef, length(permGC))
  for w = 1:length(permGC)
    ElemGAP[w] = GAP.Globals.Image(iso, PermGAP[w])
  end
  x.imgs_autos = ElemGAP
  obstruction = false
  auts_for_conductors = Vector{Main.ForeignGAP.MPtr}()
  for g in autos
    #I create the cocycle
    local cocycle
    let DGC = DGC, g = g, ElemGAP = ElemGAP
      function cocycle(aut1::gfp_poly, aut2::gfp_poly)
        s1 = DGC[aut1]
        a1 = GAP.Globals.Image(g, ElemGAP[s1])
        s2 = DGC[aut2]
        b1 = GAP.Globals.Image(g, ElemGAP[s2])
        return mod(_cocycle_values(a1, b1), p)::Int
      end
    end
  
    #Now, we have to see if it splits
    fl = cpa_issplit(K, Gp, cocycle, p, Rx)
    if fl
      obstruction = true
      push!(auts_for_conductors, g)
    end
     
  end
  if obstruction
    x.proj_ext = mH
    x.auts_for_conductors = auts_for_conductors
    return true
  else
    return false
  end
end

###############################################################################
#
#  Cocycle computation: prime power case
#
###############################################################################

function _autos_to_check(G::Main.ForeignGAP.MPtr, K::Main.ForeignGAP.MPtr, E::Main.ForeignGAP.MPtr, mG::Main.ForeignGAP.MPtr)
  AutG = GAP.Globals.AutomorphismGroup(G)
  AutK = GAP.Globals.AutomorphismGroup(K)
  AutE = GAP.Globals.AutomorphismGroup(E)
  #I want to construct the map between the automorphism groups. The kernel is characteristic!
  gens = GAP.Globals.GeneratorsOfGroup(AutE)
  ind_auts_quo = Array{Main.ForeignGAP.MPtr, 1}(undef, length(gens))
  ind_auts_sub = Array{Main.ForeignGAP.MPtr, 1}(undef, length(gens))
  for s = 1:length(gens)
    ind_auts_quo[s] = GAP.Globals.InducedAutomorphism(mG, gens[s])
    ind_auts_sub[s] = GAP.Globals.RestrictedMapping(gens[s], K)
  end
  GProd = GAP.Globals.DirectProduct(AutG, AutK)
  EmbAutG = GAP.Globals.Embedding(GProd, 1)
  EmbAutK = GAP.Globals.Embedding(GProd, 2)
  gensubs = Vector{Main.ForeignGAP.MPtr}(undef, length(gens))
  for s = 1:length(gens)
    gensubs[s] = GAP.Globals.Image(EmbAutG, ind_auts_quo[s]) * GAP.Globals.Image(EmbAutK, ind_auts_sub[s])
  end
  S = GAP.Globals.Subgroup(GProd, GAP.julia_to_gap(gensubs))
  T = GAP.Globals.List(GAP.Globals.RightTransversal(GProd, S))
  #Now, I have to recover the automorphisms in AutG and AutK
  ProjAutG = GAP.Globals.Projection(GProd, 1)
  ProjAutK = GAP.Globals.Projection(GProd, 2)
  res = Vector{Tuple{Main.ForeignGAP.MPtr, Main.ForeignGAP.MPtr}}(undef, length(T))
  for i = 1:length(T)
    res[i] = (GAP.Globals.Image(ProjAutG, T[i]), GAP.Globals.Image(ProjAutK, T[i]))
  end
  return res
end


function cocycle_computation_pp(L::Main.ForeignGAP.MPtr, i::Int)

  proj = GAP.Globals.NaturalHomomorphismByNormalSubgroup(L[1], L[i+1])
  target_grp = GAP.Globals.ImagesSource(proj)
  mH1 = GAP.Globals.NaturalHomomorphismByNormalSubgroup(target_grp, GAP.Globals.Image(proj, L[i]))
  H1 = GAP.Globals.ImagesSource(mH1)
  K = GAP.Globals.Kernel(mH1)
  # The kernel is cyclic by hypothesis, but Gap represent it as a pc group with more than one generator.
  # Brute force at the moment.
  gen = GAP.Globals.MinimalGeneratingSet(K)[1]
    

  Elems = GAP.Globals.Elements(H1)
  MatCoc = Array{Int, 2}(undef, length(Elems), length(Elems))
  Preimags = Vector{Main.ForeignGAP.MPtr}(undef, length(Elems))
  for i = 1:length(Elems)
    Preimags[i] = GAP.Globals.PreImagesRepresentative(mH1, Elems[i])
  end
  for i = 1:length(Elems)
    x1 = Preimags[i]
    for j = 1:length(Elems)
      y1 = Preimags[j]
      xy = Elems[i] * Elems[j]
      k = 1
      while Elems[k] != xy
        k += 1
      end
      xy1 = Preimags[k]
      MatCoc[i, j] = _find_exp(gen, x1*y1*GAP.Globals.Inverse(xy1))
    end
  end
  local cocycle
  let Elems = Elems, MatCoc = MatCoc
    function cocycle(x::Main.ForeignGAP.MPtr, y::Main.ForeignGAP.MPtr)  
      i = 1
      while Elems[i] != x
        i += 1
      end
      j = 1
      while Elems[j] != y
        j += 1
      end
      return MatCoc[i, j]
    end
  end
  
  autos = _autos_to_check(H1, K, target_grp, mH1)
  #For the automorphisms of K, since K is cyclic, I only need the image of 
  # 1 under the automorphism.
  autos_new = Vector{Tuple{Main.ForeignGAP.MPtr, Int}}(undef, length(autos))
  for i = 1:length(autos)
    ex = _find_exp(gen, GAP.Globals.Image(autos[i][2], gen))
    autos_new[i] = (autos[i][1], ex)
  end
  
  action = Vector{Int}(undef, length(Elems))
  for i = 1:length(Elems)
    x1 = Preimags[i]
    y = x1 * gen * GAP.Globals.Inverse(x1)
    action[i] = _find_exp(gen, y)
  end
  
  return mH1, autos_new, cocycle, action, Elems

end

function _ext_cycl(G::Array{Hecke.NfToNfMor, 1}, d::Int)

  K = domain(G[1])
  Kc = cyclotomic_extension(K, d, compute_maximal_order = true, compute_LLL_basis = false, cached = false)
  automorphisms(Kc; gens = G, copy = false)
  return Kc
end

###############################################################################
#
#  Brauer obstruction: prime power case
#
###############################################################################

function action_on_roots(G::Vector{NfToNfMor}, zeta::nf_elem, pv::Int)
  act_on_roots = Array{Int, 1}(undef, length(G))
  #@assert isone(zeta^pv)
  p = 11
  K = domain(G[1])
  Qx = parent(K.pol)
  d = discriminant(K.pol)
  while iszero(mod(numerator(d), p)) || iszero(mod(pv, p))
    p = next_prime(p)
  end
  R = GF(p, cached = false)
  Rx, x = PolynomialRing(R, "x", cached = false)
  fmod = Rx(K.pol)
  polsG = gfp_poly[Rx(g.prim_img) for g in G]
  zetaP = Rx(zeta)
  units = Vector{gfp_poly}(undef, pv-1)
  units[1] = zetaP
  for i = 2:pv-1
    units[i] = mod(units[i-1]*zetaP, fmod)
  end
  for w = 1:length(G)
    act = Hecke.compose_mod(zetaP, polsG[w], fmod)
    s = 1
    while act != units[s]
      s += 1
    end
    act_on_roots[w] = s
    #@assert G[w](zeta) == zeta^s
  end
  return act_on_roots
end

function restriction(autsK1::Vector{NfToNfMor}, autsK::Vector{NfToNfMor}, mp::NfToNfMor)
  K = domain(mp)
  K1 = codomain(mp)
  p = 11
  d1 = numerator(discriminant(K.pol))
  d2 = numerator(discriminant(K1.pol))
  while iszero(mod(d1, p)) || iszero(mod(d2, p))
    p = next_prime(p)
  end
  R = GF(p, cached = false)
  Rx, x = PolynomialRing(R, "x", cached = false)
  fmod = Rx(K1.pol)
  mp_pol = Rx(mp.prim_img)
  imgs = Vector{gfp_poly}(undef, length(autsK))
  for i = 1:length(imgs)
    imgs[i] = Hecke.compose_mod(Rx(autsK[i].prim_img), mp_pol, fmod)
  end
  res = Vector{Int}(undef, length(autsK1))
  for i = 1:length(res)
    img = Hecke.compose_mod(mp_pol, Rx(autsK1[i].prim_img), fmod)
    for j = 1:length(autsK)
      if img == imgs[j]
        res[i] = j
        break
      end
    end
    #@assert mp(autsK[res[i]].prim_img) == autsK1[i](mp.prim_img)
  end
  return res
end

function pSylow(G::Vector{NfToNfMor}, p::Int)
  com, uncom = ppio(length(G), p)
  if uncom == 1
    return G
  end
  permGC = _from_autos_to_perm(G) 
  Gperm = _perm_to_gap_grp(permGC)
  PermGAP = Vector{Main.ForeignGAP.MPtr}(undef, length(permGC))
  for w = 1:length(permGC)
    PermGAP[w] = _perm_to_gap_perm(permGC[w])
  end
  return pSylow(Gperm, PermGAP, G, p)
end

function check_Brauer_obstruction_pp(list::Vector{FieldsTower}, L::Main.ForeignGAP.MPtr, i::Int, p::Int, v::Int)
  list1 = falses(length(list))
  pv = p^v
  mH, autos, coc, action_grp, Elems = cocycle_computation_pp(L, i)
  H = GAP.Globals.ImagesSource(mH)
  for t = 1:length(list)
    @vprint :Fields 1 "$(Hecke.set_cursor_col())$(Hecke.clear_to_eol())Fields to test: $(length(list)-t+1)"
    lp = ramified_primes(list[t])
    assure_automorphisms(list[t])
    if all(x -> (isone(mod(x, pv)) || x == p), lp)
      list1[t] = _Brauer_no_extend_pp(list[t], mH, autos, coc, p, v, Elems, pv, action_grp)
      continue
    end
    Kc = _ext_cycl(list[t].generators_of_automorphisms, pv)
    K = list[t].field
    K1 = Kc.Ka
    autsK = automorphisms(K, copy = false)
    autsK1 = automorphisms(K1, copy = false)
    restr = restriction(autsK1, autsK, Kc.mp[2])
    #I construct the group and the isomorphisms between the automorphisms and the gap group.
    permGC = _from_autos_to_perm(autsK) 
    Gperm = _perm_to_gap_grp(permGC)
    d1 = numerator(discriminant(K.pol))
    d2 = numerator(discriminant(K1.pol))
    Pcomp = 7
    while iszero(mod(d1, Pcomp)) || iszero(mod(d2, Pcomp))
      Pcomp = next_prime(Pcomp)
    end
    R = GF(Pcomp, cached = false)
    Rx, x = PolynomialRing(R, "x", cached = false)
    dautsK1 = Dict{gfp_poly, Int}()
    for w = 1:length(autsK1)
      dautsK1[Rx(autsK1[w].prim_img)] = w
    end 
    iso = GAP.Globals.IsomorphismGroups(Gperm, H)
    ElemGAP = Vector{Main.ForeignGAP.MPtr}(undef, length(permGC))
    for w = 1:length(permGC)
      ElemGAP[w] = GAP.Globals.Image(iso, _perm_to_gap_perm(permGC[w]))
    end
    list[t].imgs_autos = ElemGAP
    #Restrict to the p-Sylow
    #Unfortunately, I need to compute the group structure.
    Gp = pSylow(autsK1, p)
    act_on_roots = action_on_roots(Gp, Kc.mp[1]\(gen(Kc.Kr)), pv)
    obstruction = false
    auts_for_conductors = Vector{Main.ForeignGAP.MPtr}()
    for (g1, g2) in autos
      #I create the cocycle
      local cocycle
      let restr = restr, ElemGAP = ElemGAP, dautsK1 = dautsK1, coc = coc, pv = pv, Rx = Rx, g2 = g2, g1 = g1
        function cocycle(aut1::gfp_poly, aut2::gfp_poly)
          s1 = restr[dautsK1[aut1]]
          a1 = GAP.Globals.PreImagesRepresentative(g1, ElemGAP[s1])
          s2 = restr[dautsK1[aut2]]
          b1 = GAP.Globals.PreImagesRepresentative(g1, ElemGAP[s2])
          rescoc = coc(a1, b1)*g2
          return mod(rescoc, pv)::Int
        end
      end
      #I have to find the subgroup of Gp such that the action of Gp on the roots of unity 
      #coincides with the action
      Stab = NfToNfMor[]
      for w = 1:length(Gp)
        if Gp[w].prim_img == gen(K1)
          push!(Stab, Gp[w])
          continue
        end
        s1 = restr[dautsK1[Rx(Gp[w].prim_img)]]
        img_el = GAP.Globals.PreImagesRepresentative(g1, ElemGAP[s1])
        ind = 1
        for s = 1:length(Elems)
          if img_el == Elems[s]
            ind = s
            break
          end
        end
        if action_grp[ind] == act_on_roots[w]
          push!(Stab, Gp[w])
        end
      end
      #@assert check_cocycle(Stab, cocycle, pv)

      #If the group acts as the roots of unity, we have a Brauer embedding problem, so
      # we only have to check one algebra.
      if length(Stab) == length(Gp)
        fl = cpa_issplit(K1, Gp, cocycle, pv, Rx)
        if fl
          obstruction = true
          push!(auts_for_conductors, g1)
          continue
        end
      end
      #Otherwise, I reduce the embedding problem to 2 different Brauer embedding problems.
      #One corresponds to the subextension of prime degree, the other one corresponds
      # the the embedding problem given by the subgroup of G having the same action on G and
      # on the roots of unity.
      fl = cpa_issplit(K1, Gp, cocycle, p, Rx) && cpa_issplit(K1, Gp, Stab, cocycle, p, v, Rx)
      
      if fl
        obstruction = true
        push!(auts_for_conductors, g1)
        continue
      end
    
    end
    #If I am here, all the algebras don't split. I return false
    if obstruction
      list[t].auts_for_conductors = auts_for_conductors
      list[t].proj_ext = mH
      list1[t] = true
    end
  end
  @vprint :Fields 1 "$(Hecke.set_cursor_col())$(Hecke.clear_to_eol())"
  it = findall(list1)
  return FieldsTower[list[t] for t in it]
end


function _Brauer_no_extend_pp(F, mH, autos, coc, p, v, Elems, pv, action_grp)
  K = F.field
  autsK = automorphisms(K, copy = false)
  #I construct the group and the isomorphisms between the automorphisms and the gap group.
  permGC = _from_autos_to_perm(autsK) 
  Gperm = _perm_to_gap_grp(permGC)
  d1 = numerator(discriminant(K.pol))
  Pcomp = 7
  while iszero(mod(d1, Pcomp))
    Pcomp = next_prime(Pcomp)
  end
  R = GF(Pcomp, cached = false)
  Rx, x = PolynomialRing(R, "x", cached = false)
  dautsK = Dict{gfp_poly, Int}()
  for w = 1:length(autsK)
    dautsK[Rx(autsK[w].prim_img)] = w
  end 
  H = GAP.Globals.ImagesSource(mH)
  iso = GAP.Globals.IsomorphismGroups(Gperm, H)
  ElemGAP = Vector{Main.ForeignGAP.MPtr}(undef, length(permGC))
  for w = 1:length(permGC)
    ElemGAP[w] = GAP.Globals.Image(iso, _perm_to_gap_perm(permGC[w]))
  end
  F.imgs_autos = ElemGAP
  #Restrict to the p-Sylow
  #Unfortunately, I need to compute the group structure.
  Gp = pSylow(autsK, p)
  obstruction = false
  auts_for_conductors = Vector{Main.ForeignGAP.MPtr}()
  for (g1, g2) in autos
    #I create the cocycle
    local cocycle
    let  ElemGAP = ElemGAP, dautsK = dautsK, coc = coc, pv = pv, Rx = Rx
      function cocycle(aut1::gfp_poly, aut2::gfp_poly)
        s1 = dautsK[aut1]
        a1 = GAP.Globals.PreImagesRepresentative(g1, ElemGAP[s1])
        s2 = dautsK[aut2]
        b1 = GAP.Globals.PreImagesRepresentative(g1, ElemGAP[s2])
        rescoc = coc(a1, b1)*g2
        return mod(rescoc, pv)::Int
      end
    end
    #I have to find the subgroup of Gp such that the action of Gp on the roots of unity 
    #coincides with the action
    Stab = NfToNfMor[]
    for w = 1:length(Gp)
      if Gp[w].prim_img == gen(K)
        push!(Stab, Gp[w])
        continue
      end
      s1 = dautsK[Rx(Gp[w].prim_img)]
      img_el = GAP.Globals.PreImagesRepresentative(g1, ElemGAP[s1])
      ind = 1
      for s = 1:length(Elems)
        if img_el == Elems[s]
          ind = s
          break
        end
      end
      if action_grp[ind] == 1
        push!(Stab, Gp[w])
      end
    end
    #@assert check_cocycle(Stab, cocycle, pv)

    #If the group acts as the roots of unity, we have a Brauer embedding problem, so
    # we only have to check one algebra.
    if length(Stab) == length(Gp)
      fl = cpa_issplit(K, Gp, cocycle, pv, Rx)
      if fl
        obstruction = true
        push!(auts_for_conductors, g1)
        continue
      end
    end
    #Otherwise, I reduce the embedding problem to 2 different Brauer embedding problems.
    #One corresponds to the subextension of prime degree, the other one corresponds
    # the the embedding problem given by the subgroup of G having the same action on G and
    # on the roots of unity.
    fl = cpa_issplit(K, Gp, cocycle, p, Rx) && cpa_issplit(K, Gp, Stab, cocycle, p, v, Rx)
    if fl
      obstruction = true
      push!(auts_for_conductors, g1)
      continue
    end
  end
  #If I am here, all the algebras don't split. I return false
  if obstruction
    F.auts_for_conductors = auts_for_conductors
    F.proj_ext = mH
    return true
  else
    return false
  end
  
end


###############################################################################
#
#  IsSplit for crossed product algebras: the action of G on the extension 
#  correspond to the action on the roots of unity
#
###############################################################################

#p must be a prime power 
function cpa_issplit(K::AnticNumberField, G::Vector{NfToNfMor}, Coc::Function, pv::Int, Rx::GFPPolyRing)
  p = ispower(pv)[2]
  O = maximal_order(K)
  r, s = signature(O)
  @vtime :BrauerObst 1 if p == 2 && r!= degree(O) && !is_split_at_infinity(K, Coc, Rx)
    return false    
  end
  # Now, the finite primes.
  # The crossed product algebra is ramified at the ramified primes of the field (and at the primes dividing the values
  # of the cocycle, but our cocycle has values in the roots of unity...
  # I only need to check the tame ramification.
  # The exact sequence on Brauer groups and completion tells me that I have one degree of freedom! :)
  lp = Hecke.ramified_primes(O)
  if !(p in lp) && divisible(discriminant(O), p)
    push!(lp, p)
  end 
  if p in lp
    for q in lp
      if q != p 
        @vtime :BrauerObst 1 fl = is_split_at_p(O, G, Coc, Int(q), pv, Rx)
        if !fl
          return false
        end
      end
    end
  else
    for i = 1:length(lp)-1
      @vtime :BrauerObst 1 fl = is_split_at_p(O, G, Coc, Int(lp[i]), pv, Rx)
      if !fl
        return false
      end
    end
  end
  return true
end


function is_split_at_infinity(K::AnticNumberField, Coc::Function, Rx::GFPPolyRing)
  aut = complex_conjugation(K)
  if Coc(Rx(aut.prim_img), Rx(aut.prim_img)) == 1
    @vprint :Fields 3 "Real places!\n"
    return false
  else
    return true
  end
end

function inertia_subgroup(F, mF, G::Array{NfToNfMor, 1})
  @assert !isempty(G)
  K = domain(G[1])
  O = maximal_order(K)
  gF = gen(F)
  igF = K(mF\gF)
  inertia_grp = NfToNfMor[]
  for g in G
    if g.prim_img == gen(K)
      push!(inertia_grp, g)
      continue
    end
    y = mF(O(g(igF), false))
    if y == gF
      push!(inertia_grp, g)
    end
  end
  return inertia_grp 
end



function decomposition_group(G::Array{NfToNfMor, 1}, P::NfOrdIdl, orderG::Int = length(G))
  @assert !isempty(G)
  O = order(P)
  K = nf(O)
  dec_group = NfToNfMor[]
  F, mF = Hecke.ResidueFieldSmall(O, P)
  for g in G
    if g.prim_img == gen(K)
      push!(dec_group, g)
      continue
    end
    y = O(g(K(P.gen_two)), false)
    if iszero(image(mF, y))
      push!(dec_group, g)
    end
    if length(dec_group) == orderG
      break
    end
  end
  return dec_group 
end

function _find_theta(G::Vector{NfToNfMor}, F::FqNmodFiniteField, mF::Hecke.NfOrdToFqNmodMor, e::Int)
  K = domain(G[1])
  O = maximal_order(K)
  p = ispower(e)[2]
  t = div(e, p)
  gF = gen(F)
  igF = K(mF\gF)
  gK = gen(K)
  theta = G[1]
  for i = 1:length(G)
    theta = G[i]
    #I make sure that the element is a generator of the inertia subgroup
    if mF(O(theta(igF), false)) == gF && (theta^t).prim_img != gK
      break
    end
  end
  return theta
end

function _find_frob(G::Vector{NfToNfMor}, F::FqNmodFiniteField, mF::Hecke.NfOrdToFqNmodMor, e::Int, f::Int, q::Int, theta::NfToNfMor)
  K = domain(G[1])
  O = maximal_order(K)
  gK = gen(K)
  p = ispower(e)[2]
  t = div(e, p)
  frob = G[1]
  expo = mod(q, e)
  gF = gen(F)
  igF = K(mF\gF)
  rhs = gF^q
  for i = 1:length(G)
    frob = G[i]
    if frob == theta
      continue
    end
    #I make sure that g1 is a Frobenius
    if mF(O(frob(igF), false)) != rhs
      continue
    end
    #Now, I check the relation
    gc = frob * theta 
    gq = (theta^expo) * frob
    if gc == gq
      break
    end
  end
  return frob
end

#See Gerald J. Janusz (1980) Crossed product orders and the schur index,
#Communications in Algebra, 8:7, 697-706

function is_split_at_p(O::NfOrd, GC::Array{NfToNfMor, 1}, Coc::Function, p::Int, n::Int, Rx::GFPPolyRing)

  lp = prime_decomposition(O, p, cached = true)
  e = gcd(length(GC), lp[1][2])
  if e == 1
    return true
  end
  P = lp[1][1]
  f = gcd(length(GC), degree(P))
  if f == 1 && iszero(mod(norm(P)-1, e*n))
    return true
  end
  if length(lp) != 1
    @vtime :BrauerObst 1  Gp = decomposition_group(GC, P, e*f) 
    #I don't really want the decomposition group of the p-sylow, but the p-sylow of the decomposition group.
    #Therefore, if the p-sylow is not normal, I have to try different primes.
    i = 1
    while length(Gp) != e*f
      i += 1
      P = lp[i][1]
      Gp = decomposition_group(GC, P, e*f)
    end
  else
    Gp = GC
  end
  f1 = divexact(degree(P), f)
  q = p^f1 #Cardinality of the residue field
  
  F, mF = Hecke.ResidueFieldSmall(O, P)
  theta1 = _find_theta(Gp, F, mF, e)
  theta = Rx(theta1.prim_img)
  
  K = nf(O)
  fmod = Rx(K.pol)
  #I have found my generators. Now, we find the elements to test if it splits.
  @assert divisible(norm(P)-1, e)
  c = divexact(norm(P)-1, e)
  if !iszero(mod(c, n))
    powtheta = theta
    zeta = 0
    for k = 1:e-1
      zeta += Coc(powtheta, theta)::Int
      powtheta = compose_mod(powtheta, theta, fmod)
    end
    zeta = mod(zeta * c, n)
    if !iszero(zeta)
      return false
    end
  end
  
    
  #The second element is a little more complicated. 
  if f == 1
    return true
  end
  frob = Rx(_find_frob(Gp, F, mF, e, f, q, theta1).prim_img)
  if iszero(mod(q-1, e*n))
    lambda = mod(Coc(frob, theta)- Coc(theta, frob), n)::Int
    return iszero(lambda)
  end
  lambda = Coc(frob, theta)::Int
  powtheta = theta
  s, t = divrem(q-1, e)
  if !iszero(mod(s+1, n))
    for k = 1:t
      lambda -= (s+1) * Coc(powtheta, theta)::Int
      powtheta = compose_mod(powtheta, theta, fmod)
    end
  else
    powtheta = _pow_as_comp(theta, t+1, fmod)
  end
  if !iszero(mod(s, n))
    for k = t+1:(e-1)
      lambda -= s * Coc(powtheta, theta)::Int
      powtheta = compose_mod(powtheta, theta, fmod)
    end
  end
  powtheta = _pow_as_comp(theta, mod(q, e), fmod)
  lambda = mod(lambda - Coc(powtheta, frob), n)::Int
  return iszero(lambda)
end

function _pow_as_comp(f::gfp_poly, b::Int, fmod::gfp_poly)
  Rx = base_ring(f)
  if b == 0
    error("what is that?!")
  elseif b == 1
    return f
  else
    bit = ~((~UInt(0)) >> 1)
    while (UInt(bit) & b) == 0
      bit >>= 1
    end
    z = f
    bit >>= 1
    while bit != 0
      z = Hecke.compose_mod(z, z, fmod)
      if (UInt(bit) & b) != 0
        z = Hecke.compose_mod(f, z, fmod)
      end
      bit >>= 1
    end
    return z
  end
end

################################################################################
#
#  IsSplit for crossed product algebras: prime power case
#
################################################################################


function cpa_issplit(K::AnticNumberField, G::Vector{NfToNfMor}, Stab::Vector{NfToNfMor}, Coc::Function, p::Int, v::Int, Rx::GFPPolyRing)

  O = maximal_order(K)
  r, s = signature(O)
  @vtime :BrauerObst 1 if p == 2 && r != degree(K) && !is_split_at_infinity(K, Coc, Rx)
    return false    
  end
  # Now, the finite primes.
  # The crossed product algebra is ramified at the ramified primes of the field (and at the primes dividing the values
  # of the cocycle, but our cocycle has values in the roots of unity...
  # I only need to check the tame ramification.
  # The exact sequence on Brauer groups and completion tells me that I have one degree of freedom! :)
  
  lp = Hecke.ramified_primes(O)
  if p in lp
    for q in lp
      if q != p 
        @vtime :BrauerObst 1 fl = is_split_at_p(O, G, Stab, Coc, Int(q), p^v, Rx)
        if !fl
          return false
        end
      end
    end
  else
    for i = 1:length(lp)-1
      @vtime :BrauerObst 1 fl = is_split_at_p(O, G, Stab, Coc, Int(lp[i]), p^v, Rx)
      if !fl
        return false
      end
    end
  end
  return true
  
end


function is_split_at_p(O::NfOrd, GC::Vector{NfToNfMor}, Stab::Vector{NfToNfMor}, Coc::Function, p::Int, n::Int, Rx::GFPPolyRing)

  lp = prime_decomposition(O, p, cached = true)
  e = gcd(length(GC), lp[1][2])
  if e == 1
    return true
  end
  
  P = lp[1][1]
  @assert divisible(norm(P)-1, e)
  c = divexact(norm(P)-1, e)
  f = gcd(length(GC), degree(P))
  if f == 1 && iszero(mod(c, n))
    return true
  end 
  if length(lp) != 1
    @vtime :BrauerObst 1  Gp = decomposition_group(GC, P, e*f) 
    #I don't really want the decomposition group of the p-sylow, but the p-sylow of the decomposition group.
    #Therefore, if the p-sylow is not normal, I have to try different primes.
    i = 1
    while length(Gp) != e*f
      i += 1
      P = lp[i][1]
      Gp = decomposition_group(GC, P, e*f)
    end
  else
    Gp = GC
  end
  GpStab = NfToNfMor[]
  for i = 1:length(Gp)
    if Gp[i] in Stab
      push!(GpStab, Gp[i])
    end
  end
  #I need the inertia subgroup to determine e and f
  F, mF = Hecke.ResidueFieldSmall(O, P)
  InGrp = inertia_subgroup(F, mF, GpStab)
  e = length(InGrp)
  if e == 1
    return true
  end
  f = divexact(length(GpStab), e)
  c = divexact(norm(P)-1, e)
  if f == 1 && iszero(mod(c, n))
    return true
  end 
  f1 = divexact(degree(P), f)
  q = p^f1 #Cardinality of the residue field

  theta1 = _find_theta(GpStab, F, mF, e)
  theta = Rx(theta1.prim_img)
  fmod = Rx(nf(O).pol)
  #I have found my generators. Now, we find the elements to test if it splits.
  if !iszero(mod(c, n))
    powtheta = theta
    zeta = 0
    for k = 1:e-1
      zeta += Coc(powtheta, theta)
      powtheta = compose_mod(powtheta, theta, fmod)
    end
    zeta = mod(zeta * c, n)
    if !iszero(zeta)
      return false
    end
  end
    
  if f == 1
    return true
  end
  frob = Rx(_find_frob(GpStab, F, mF, e, f, q, theta1).prim_img)
  if iszero(mod(q-1, e*n))
    lambda = mod(Coc(frob, theta)- Coc(theta, frob), n)
    return iszero(lambda)
  end
  lambda = Coc(frob, theta)
  powtheta = theta
  s, t = divrem(q-1, e)
  if !iszero(mod(s+1, n))
    for k = 1:t
      lambda -= (s+1) * Coc(powtheta, theta)
      powtheta = compose_mod(powtheta, theta, fmod)
    end
  else
    powtheta = _pow_as_comp(theta, t+1, fmod)
  end
  lambda -= Coc(powtheta, frob)
  if !iszero(mod(s, n))
    for k = t+1:(e-1)
      lambda -= s * Coc(powtheta, theta)
      powtheta = compose_mod(powtheta, theta, fmod)
    end
  end
  powtheta = _pow_as_comp(theta, mod(q, e), fmod)
  lambda = mod(lambda - Coc(powtheta, frob), n)
  return iszero(lambda)

end
