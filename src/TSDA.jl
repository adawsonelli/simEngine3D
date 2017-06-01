type TSDA    #10.7 slide 18
  """
  A Translational Spring-Damper-Actuator is a force generating component which
  acts between a point P on  bodyi and a point Q on bodyj.
  """
  sim::Sim      #reference to the simulation data structures
  bodyi::Body   #bodyi
  bodyj::Body   #bodyj
  Pi::Int       #index of point P on body i
  Qj::Int       #index of point Q on body j
  k             #stiffness of the spring
  l₀            #resting length of the spring
  c             #damping coefficient
  h             #function handle for the actuator


  #constructor function
  function TSDA(sim::Sim,bodyi::Body,bodyj::Body,Qi::Int,Qj::Int,k=0,l₀ = 0,c = 0,h = (lij,lijdot,t)->0 )
    new(sim,bodyi,bodyj,Pi,Pj,Qj,k,l₀,c,h)
  end
end

#----------------begin functions associated with TSDA---------------------------
dij(tsda::TSDA)    =    dij(tsda.bodyi,tsda.bodyj, pt(tsda.bodyi,tsda.Pi), pt(tsda.bodyj,tsda.Qj))
dijdot(tsda::TSDA) = dijdot(tsda.bodyi,tsda.bodyj, pt(tsda.bodyi,tsda.Pi), pt(tsda.bodyj,tsda.Qj))
lij(tsda::TSDA)    = norm(dij(tsda))
eij(tsda::TSDA)    = dij(tsda) / lij(tsda)
lijdot(tsda::TSDA) = eij(tsda)'*dijdot(tsda) #11.4.3 haug


"""
scalar force generated by the tsda element as a function of position, velocity, time
"""
function f(tsda::TSDA)
  f_tsda = tsda.k(lij(tsda) - tsda.l₀) + tsda.c*lijdot(tsda) + tsda.h(lij(tsda),lijdot(tsda),tsda.sim.t)
end

"""[3x1] force vectors acting on each body i and j"""
Fi(tsda::TSDA) = f(tsda)*eij(tsda)
Fj(tsda::TSDA) = f(tsda)*-eij(tsda)

"""[3x1] torques generated by the forces acting at points Pi and Qi WRT body COM"""
nbari(tsda::TSDA) = tilde(pt(tsda.bodyi,tsda.Pi))*A(tsda.bodyi)*Fi(tsda)
nbarj(tsda::TSDA) = tilde(pt(tsda.bodyi,tsda.Pi))*A(tsda.bodyi)*Fi(tsda)
