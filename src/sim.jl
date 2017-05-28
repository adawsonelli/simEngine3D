#includes

"""
the system contains all the bodies, constraints and forces required to perform
spacial kinematics and dynamics on a time grid.
"""
type Sim
  #counters
  nb::Int                   #number of bodies in the system
  nc::Int                   #number of constraint equations in the system
  nc_k::Int                 #number of kinematic and driving contraints in the system
  nc_p::Int                 #number of euler parameter normalization constraints == nb
  t::Float64                #current time of the system

  #state
  q::Array{Float64}         #[7nb x 1] array of system generalized coordinates = [r;p]
  qdot::Array{Float64}      #[7nb x 1] array of system generalized coordinates = [rdot;pdot]
  qddot::Array{Float64}     #[7nb x 1] array of system generalized coordinates = [rdot;pdot]

  #objects
  bodies::Any               #[nb    x 1] array of body objects in the system
  cons::Any                 #[nCons x 1] array of constraint objects in system
  pCons::Any                #[nb    x 1] array of euler parameter constraint objects

  #constraint equations
  ɸk::Array{Float64}        #[nc_k x 1]  array of system non-linear equations of constraint
  ɸp::Array{Float64}        #[nc_p x 1]  array of system euler param normalization constraints
  ɸF::Array{Float64}        #[nc   x 1]  array of system constraint equations, Full

  νk::Array{Float64}        #[nc_k x 1] system velocity equations for kinematic and driving constraints
  νp::Array{Float64}        #[nc_p x 1] system velocity equations euler parameters
  νF::Array{Float64}        #[nc   x 1] system velocity equations, Full

  𝛾k::Array{Float64}        #[nc_k x 1] system acceleration equations for kinematic and driving constraints
  𝛾p::Array{Float64}        #[nc_p x 1] system acceleration equations for euler parameters
  𝛾F::Array{Float64}        #[nc   x 1] system acceleration equations, Full

  #constraint matricies
  ɸk_r::Array{Float64}      #[nc_k x 3nb] partial derivative of the kinematic constraint equations WRT positional GC's
  ɸk_p::Array{Float64}      #[nc_k x 4nb] partial derivative of the kinematic constraint equations WRT orientational GC's
  ɸF_q::Array{Float64}      #[nc   x 7nb] partial derivative of system constraints (ɸF) WRT system Generalized coordinates

  #dynamics quantities
  M                         #[3nb x 3nb] System Mass Matrix  (static)
  Jᵖ                        #[4nb x 4nb] System Inertia matrix
  λk                        #[nc_k  x 1] System kinematic and driving constraint lagrange multiplier
  λp                        #[nc_p  x 1] System euler parameters lagrange multipliers
  λF                        #[nc    x 1] System lagrange multier, Full



  function Sim(nbodies = 2)  #total number of bodies to be added to the system , apriori
    #make a blank simulation
    nb = nbodies; nc = 0 ; nc_k = 0 ; nc_p = 0 ; t= 0.0
    q = zeros(7*nb,1); qdot = zeros(7*nb,1); qddot = zeros(7*nb,1)
    bodies = Array{Any}(0); cons =Array{Any}(0); pCons = Array{Any}(0)

    new(nb,nc,nc_k,nc_p,t, q,qdot,qddot, bodies,cons,pCons)

  end


end

#-------------------------Sim Initialization fxns ------------------------------

"""
adds a body object to the current simulation. body object should be initialized
with points.
"""
function addBody!(sim::Sim, body::Any, r = [0 0 0]', p = [1 0 0 0]')
  push!(sim.bodies, body) #add the body to the simulation
  set_r!(body,r)  #update body GC's
  set_p!(body,p)
end

"""add a constraint object to the current simulation"""
function addConstraint!(sim::Sim, con::Any) #inheritance could solve this
  push!(sim.cons, con)
  sim.nc += con.rDOF
  sim.nc_k += con.rDOF
end

"""Ground is the first body added to the system, and is index 1"""
function addGround!(sim::Sim)
  gnd = Body(sim,1)
  addBody!(sim,gnd)
  addPoint(gnd , [1 0 0]') #need a point to form rotational constraints
  con = ground(sim,gnd,2)
  addConstraint!(sim,con)
end

  """add euler parameter constraints to system"""
  function addEulerParamConstraints(sim::Sim)
    for body in sim.bodies
      push!(sim.pCons,ep(sim,body))
      sim.nc += 1; sim.nc_p += 1
    end

  end

"""after finished adding bodies and constraints, run this"""
function initForAnalysis(sim::Sim)
  #run this function to set up sim @ t0, after all bodies and constraints have
  #been added

  #add euler parameter constraints
  addEulerParamConstraints(sim)

  #init simulation data structures so they can be indexed into and motified
  sim.ɸk = zeros(sim.nc_k,1);  sim.νk = zeros(sim.nc_k,1);  sim.𝛾k = zeros(sim.nc_k,1)
  sim.ɸp = zeros(sim.nc_p,1);  sim.νp = zeros(sim.nc_p,1);  sim.𝛾p = zeros(sim.nc_p,1)
  sim.ɸF = zeros(sim.nc, 1 );  sim.νF = zeros(sim.nc,  1);  sim.𝛾F = zeros(sim.nc,  1)

  sim.ɸk_r = zeros(sim.nc_k,3*sim.nb)
  sim.ɸk_p = zeros(sim.nc_k,4*sim.nb)
  sim.ɸF_q = zeros(sim.nc,7*sim.nb)
end


#---------------------------matrix builders-------------------------------------
#
#matrix builder functions construct simulation / system level matricies used in
#kinematic and dynamic analysis from the state information of the bodies within
#the simulation. and by evaluating the functions of each geometric constraint.

#position equation matrix builders
"""position equations for the kinematic and driving constraints"""
function buildɸk(sim::Sim) #[nc_k x 1]
  row = 1;
  for con in sim.cons
    sim.ɸk[row:row+con.rDOF - 1] = ϕ(con)
    row = row + con.rDOF
  end
end
"""euler position constraint equations"""
function buildɸp(sim::Sim)
  row = 1;
  for pCon in sim.pCons
    sim.ɸp[row:row+pCon.rDOF - 1] = ϕ(pCon)
    row = row + pCon.rDOF
  end
end
"""combined position equations"""
function buildɸF(sim::Sim)
  buildɸk(sim)
  buildɸp(sim)
  sim.ɸF = [sim.ɸk ; sim.ɸp]
end

#velocity equation matrix builders
"""velocity equations for the kinematic and driving constraints"""
function buildνk(sim::Sim)
  row = 1;
  for con in sim.cons
    sim.νk[row:row+con.rDOF - 1] = ν(con)
    row = row + con.rDOF
  end
end
"""velocity equations for the euler parameters"""
function buildνp(sim::Sim)
  row = 1;
  for pCon in sim.pCons
    sim.νp[row:row+pCon.rDOF - 1] = ν(pCon)
    row = row + pCon.rDOF
  end
end
"""combined velocity equations"""
function buildνF(sim::Sim)
  buildνk(sim)
  buildνp(sim)
  sim.νF = [sim.νk ; sim.νp]

end

#acceleration equation matrix builders
"""acceleration equations for the kinematic and driving constraints"""
function build𝛾k(sim::Sim)
  row = 1;
  for con in sim.cons
    sim.𝛾k[row:row+con.rDOF - 1] = 𝛾(con)
    row = row + con.rDOF
  end
end
"""acceleration equations for the euler parameters"""
function build𝛾p(sim::Sim)
  row = 1;
  for pCon in sim.pCons
    sim.𝛾p[row:row+pCon.rDOF - 1] = 𝛾(pCon)
    row = row + pCon.rDOF
  end
end
"""combined velocity equations"""
function build𝛾F(sim::Sim)
  build𝛾k(sim)
  build𝛾p(sim)
  sim.𝛾F = [sim.𝛾k ; sim.𝛾p]
end

#constraint equations partial derivatives WRT system GC's
"""partial of the kinematic and driving constraint equations WRT position GC's"""
function buildɸk_r(sim::Sim)
  #insert calculated partial derivative into sim.ɸk_r matrix
  row = 1
  for con in sim.cons
    phi_r = ϕ_r(con)  #(phi_ri ,phi_rj) if rj exists
    col = 3*(con.bodyi.ID - 1) + 1
    insertUL!(sim.ɸk_r, phi_r[1],(row,col))  #inset phi_ri
    if phi_r[2] != 0 #phi_rj exists!
      col = 3*(con.bodyj.ID - 1) + 1
      insertUL!(sim.ɸk_r, phi_r[2],(row,col))  #inset phi_ri
    end
    row += con.rDOF
  end
end
"""partial of the kinematic and driving constraint equations WRT orientation GC's"""
function buildɸk_p(sim::Sim)
  #insert calculated partial derivative into sim.ɸk_p matrix
  row = 1
  for con in sim.cons
    phi_p = ϕ_p(con)  #(phi_ri ,phi_rj) if rj exists
    col = 4*(con.bodyi.ID-1) + 1
    insertUL!(sim.ɸk_p, phi_p[1],(row,col))  #inset phi_ri
    if phi_p[2] != 0 #phi_rj exists!
      col = 4*(con.bodyj.ID-1) + 1
      insertUL!(sim.ɸk_p, phi_p[2],(row,col))  #inset phi_ri
    end
    row += con.rDOF
  end
end
"""full constraint jacobian WRT the system GC's"""
function buildɸF_q(sim::Sim)
  #add ɸᵖ_q  to [ɸk_r ; ɸk_p]  to get full jacobian.
  buildɸk_r(sim)
  buildɸk_p(sim)

  #calc #add ɸᵖ_q for con in sim.cons
  ɸp_q = zeros(sim.nb, 7*sim.nb)
  row = 1
  for pCon in sim.pCons
    #insert ϕ_p  components (no need to insert ϕ_r as it's zero)
    phi_p = ϕ_p(pCon)
    col = 3*sim.nb + 4*(pCon.bodyi.ID-1) + 1
    insertUL!(ɸp_q ,phi_p[1] ,(row,col))  #inset phi_ri
    row += pCon.rDOF
  end

  #combine to make full jacobian
  sim.ɸF_q = [sim.ɸk_r sim.ɸk_p ; ɸp_q]  #[nc x 7nb]

end

#-----------------------dynamics matrix builders--------------------------------
"""system mass matrix (static)"""
function buildM(sim::Sim)    #10.5  slide 27
  for body in sim.bodies
    Ind = 3*(body.ID - 1) + 1;
    insertUL!(sim.M, body.m*eye(3),(Ind, Ind))
  end
end

"""system Inertia Matrix"""
function buildJᵖ(sim::Sim)    #10.5  slide 27
  for body in sim.bodies
    Ind = 4*(body.ID - 1) + 1
    jᵖ = 4*G(p(body))'*body.j*G(p(body))
    insertUL!(sim.Jᵖ, jᵖ, (Ind, Ind))
  end
end

"""system euler parameter matrix"""
function buildP(sim::Sim)    #10.5  slide 27
  for body in sim.bodies
    rInd = body.ID ; cInd = 4*(body.ID - 1) + 1
    insertUL!(sim.P, p(body), (rInd, cInd))
  end
end


"""system applied forces vector"""
function buildF(sim::Sim)    #10.5  slide 27
  for body in sim.bodies
    Ind = 3*(body.ID - 1) + 1;
    insertUL!(sim.M, body.m*eye(3),(Ind, Ind))
  end
end

"""system applied torques vector"""
function buildτ(sim::Sim)    #10.5  slide 27
  for body in sim.bodies
    Ind = 3*(body.ID - 1) + 1;
    insertUL!(sim.M, body.m*eye(3),(Ind, Ind))
  end
end











#---------------------------calculated states-----------------------------------
nDOF(sim::Sim) = sim.nb*7 - sim.nc
