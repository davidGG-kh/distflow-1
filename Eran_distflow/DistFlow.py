# -*- coding: utf-8 -*-
"""
Created on Sun Jul 22 20:08:01 2018
 
@author: shamm
"""


import numpy as np
import matplotlib.pyplot as plt

Smax = 40 #[kVA]
power_factor=0.9
#reactivepowercontribution=tan(acos(power_factor))
reactivepowercontribution=0.484
Pmax= Smax**2/(1+reactivepowercontribution**2)
Pmax=np.sqrt(Pmax)
#Pmax = 40  #[kW]

linear=np.array([0.95,0.98,1.02,1.05,1.02,1.05])
no_deadband=np.array([0.95,1.00,1.00,1.05,1.0,1.05])
curved=np.array([0.95,0.98,1.02,1.05,1.05,1.1])

### Change the setpoint variable if other options are needed to be seen according to the three arrays, change the array you want to simulate
setpoint=np.copy(no_deadband)
# setpoint=np.copy(linear)
setpoint=np.copy(curved)


##### VOLT-VAR POINTS
vminq = setpoint[0]
vdead1= setpoint[1]
vdead2= setpoint[2]
vmaxq = setpoint[3]

##### VOLT-WATT POINTS
vbreakp = setpoint[4]
vmaxp = setpoint[5]

Qmax = lambda Pout: np.sqrt(Smax**2 - Pout**2)

def Pcurve(v):
    ### defines the Pcurve at various voltage points v given user specified inputs
    
    v = np.array(v)
    P = np.zeros(v.shape)
    
    tmp = v <= vbreakp
    P[tmp] = Pmax
    
    tmp = (v > vbreakp) & (v <= vmaxp)
    P[tmp] = (vmaxp - v[tmp])/(vmaxp - vbreakp)*Pmax
    
    tmp = (v > vmaxp)
    P[tmp] = 0.0
    return P

def Qcurve(v):
    ### defines the Qcurve at various voltage points v given user specified inputs
    v = np.array(v)
    Q = np.zeros(v.shape)
    
    ## points below vminq,
    tmp = v <= vminq
    Q[tmp] = Qmax(Pmax)
    
    ## linearly decrease Qinj between vminq and vdead1
    tmp = (v > vminq) & (v <= vdead1)
    Q[tmp] = (vdead1 - v[tmp])/(vdead1-vminq)*Qmax(Pcurve(v[tmp]))
    
    ## zero in the dead-band
    if (vdead1==vdead2):
        tmp = (v >= vdead1) & (v <= vdead2)
        Q[tmp] = 0.0
    else:
        tmp = (v > vdead1) & (v <= vdead2)
        Q[tmp] = 0.0
    ## linearly decrease Qinj between vdead2 and vmaxq
    tmp = (v > vdead2) & (v <= vmaxq)
    Q[tmp] = (vdead2 - v[tmp])/(vmaxq - vdead2)*Qmax(Pcurve(v[tmp]))
    
   
    
    ## maintain the maximum (negative) injection given the watt injection at the given voltage
    tmp = v > vmaxq
    Q[tmp] = -Qmax(Pcurve(v[tmp]))
    return Q


# Network Information
lineinfo=[0]
networkset=set(lineinfo)
networklist=[networkset]
for i in range(1,6):
    lineinfo.append(i)
    networkset = set(lineinfo)
    networklist.append(networkset)

# lineinfo=[0,1,2,6]
# networkset = set(lineinfo)
# networklist.append(networkset)
# lineinfo=[0,1,2,6,7]
# networkset = set(lineinfo)
# networklist.append(networkset)

for i in range(1,6):
    print('i:' + str(i))
    for j in range(1,6):

        p=networklist[i] & networklist[j]
        print(p)
        print('\n')



ratio=1
r=0.01
#r=1
x=r*ratio

r=r*2
x=x*2
# First Node is the 0th node
nodes=np.linspace(0,5,6)
number_of_nodes=len(nodes)
vslack=1.03
#vslack=20

#  Creating the Dictionary
rarray={}
rarray['01']=r
rarray['12']=r
rarray['23']=r
rarray['34']=r
rarray['45']=r


xarray={}
xarray['01']=x
xarray['12']=x
xarray['23']=x
xarray['34']=x
xarray['45']=x




v=np.zeros(shape=(number_of_nodes))
pc=1*np.array([0,0.3,0.4,0.2,0.5,0.3])
# pc=np.array([0,0,0.0,0,0,4])
qc=1*np.array([0,0.8,0.2,0.3,0.1,0.2])
gen_control=np.array([0,1,0,1,0,1])
gen_control=0*gen_control

tol=1e-3
iteration=300
basecase=0
V=np.zeros(shape=(iteration,number_of_nodes))
Power=np.zeros(shape=(iteration,2))
inverterloc=np.where(gen_control>0.0)[0]
for itr in range(0,iteration):
    #doing a flat run analysis without any PV penetration, only the first time
    if (itr>0):
        basecase=1
    for i in range(1,number_of_nodes):
        sumpq=0    
        for j in range(1,number_of_nodes):
            if (j<i):
                sumpq=sumpq-pc[j]*j*r-qc[j]*j*x +basecase*gen_control[j]*Pcurve(v[i])/100*j*r+basecase*gen_control[j]*Qcurve(v[i])/100*j*x
            else:
                sumpq= sumpq-pc[j]*i*r-qc[j]*i*x +basecase*gen_control[j]*Pcurve(v[i])/100*i*r+basecase*gen_control[j]*Qcurve(v[i])/100*i*x
        
            # if (i==5):
            #     print(sumpq)
        if (gen_control[i]>0):
            Power[itr,0]=Pcurve(v[i])
            Power[itr, 1] = Qcurve(v[i])
            

        v[i]=vslack**2+sumpq
    v[0]=vslack**2
    V[itr,:]=v
    print('Iteration:', str(itr), '  ',str(v))
    if (itr>0):
        
        # diffv=abs(V[itr,inverterloc]-V[itr-1,inverterloc])
        diffv=abs(V[itr,:]-V[itr-1,:])
        if (max(diffv)<tol):
            break
#print(Power[0:itr,:])



