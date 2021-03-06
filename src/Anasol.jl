__precompile__()

"""
MADS: Model Analysis & Decision Support in Julia (Mads.jl v1.0) 2016

http://mads.lanl.gov
http://madsjulia.lanl.gov
http://gitlab.com/mads/Mads.jl

Licensing: GPLv3: http://www.gnu.org/licenses/gpl-3.0.html

Copyright 2016.  Los Alamos National Security, LLC.  All rights reserved.

This material was produced under U.S. Government contract DE-AC52-06NA25396 for
Los Alamos National Laboratory, which is operated by Los Alamos National Security, LLC for
the U.S. Department of Energy. The Government is granted for itself and others acting on its
behalf a paid-up, nonexclusive, irrevocable worldwide license in this material to reproduce,
prepare derivative works, and perform publicly and display publicly. Beginning five (5) years after
--------------- November 17, 2015, ----------------------------------------------------------------
subject to additional five-year worldwide renewals, the Government is granted for itself and
others acting on its behalf a paid-up, nonexclusive, irrevocable worldwide license in this
material to reproduce, prepare derivative works, distribute copies to the public, perform
publicly and display publicly, and to permit others to do so.

NEITHER THE UNITED STATES NOR THE UNITED STATES DEPARTMENT OF ENERGY, NOR LOS ALAMOS NATIONAL SECURITY, LLC,
NOR ANY OF THEIR EMPLOYEES, MAKES ANY WARRANTY, EXPRESS OR IMPLIED, OR ASSUMES ANY LEGAL LIABILITY OR
RESPONSIBILITY FOR THE ACCURACY, COMPLETENESS, OR USEFULNESS OF ANY INFORMATION, APPARATUS, PRODUCT, OR
PROCESS DISCLOSED, OR REPRESENTS THAT ITS USE WOULD NOT INFRINGE PRIVATELY OWNED RIGHTS.

LA-CC-15-080; Copyright Number Assigned: C16008
"""
module Anasol

using Distributions
using Base.Cartesian
using MetaProgTools

include("newanasol.jl")

const standardnormal = Distributions.Normal(0, 1)

function inclosedinterval(x, a, b)
	return x >= a && x <= b
end

dispersionnames = ["b", "f"] # b is form brownian motion, f is for fractional brownian motion
sourcenames = ["d", "b"] # d is for distributed (e.g., Gaussian or Levy alpha stable), b is for box
boundarynames = ["i", "r", "a"] # d is for infinite (no boundary), r is for reflecting

function getdispersions(dispersionnames)
	f(x) = x == "b" ? :linear : :fractional
	return :(Val{$(map(f, dispersionnames))})
end
function getsources(sourcenames)
	f(x) = x == "b" ? :box : :dispersed
	return :(Val{$(map(f, sourcenames))})
end
function getboundaries(boundarynames)
	f(x) = x == "i" ? :infinite : x == "r" ? :reflecting : :absorbing
	return :(Val{$(map(f, boundarynames))})
end

#the functions defined in this monstrosity of loops are for backwards compatibility
#use the functions defined in "newanasol.jl" instead
maxnumberofdimensions = 3
for n = 1:maxnumberofdimensions
	bigq = quote
		@nloops numberofdimensions j ii->1:length(boundarynames) begin
			@nloops numberofdimensions k ii->1:length(sourcenames) begin
				@nloops numberofdimensions i ii->1:length(dispersionnames) begin
					shortfunctionname = string((@ntuple numberofdimensions ii->dispersionnames[i_ii])..., "_", (@ntuple numberofdimensions ii->sourcenames[k_ii])..., "_", (@ntuple numberofdimensions ii->boundarynames[j_ii])...)
					q = quote
						$(symbol(string("long_", shortfunctionname)))(x::Vector,tau) = 1
					end
					x0s = parse(string("[", join(map(i->"x0$i", 1:numberofdimensions), ",")..., "]"))
					sigma0s = parse(string("[", join(map(i->"sigma0$i", 1:numberofdimensions), ",")..., "]"))
					vs = parse(string("[", join(map(i->"v$i", 1:numberofdimensions), ",")..., "]"))
					sigmas = parse(string("[", join(map(i->"sigma$i", 1:numberofdimensions), ",")..., "]"))
					Hs = parse(string("[", join(map(i->"H$i", 1:numberofdimensions), ",")..., "]"))
					xbs = parse(string("[", join(map(i->"xb$i", 1:numberofdimensions), ",")..., "]"))
					dispersions = getdispersions(@ntuple numberofdimensions ii->dispersionnames[i_ii])
					sources = getsources(@ntuple numberofdimensions ii->sourcenames[k_ii])
					boundaries = getboundaries(@ntuple numberofdimensions ii->boundarynames[j_ii])
					q.args[2].args[2].args[2] = :(innerkernel(Val{$numberofdimensions}, x, tau, $x0s, $sigma0s, $vs, $sigmas, $Hs, $xbs, $dispersions, $sources, $boundaries, nothing))
					for i = 1:numberofdimensions
						q.args[2].args[1].args = [q.args[2].args[1].args; symbol("x0$(i)"); symbol("sigma0$(i)"); symbol("v$(i)"); symbol("sigma$(i)"); symbol("H$(i)"); symbol("xb$(i)")]
					end
					eval(q)# make the function with all possible arguments
					# now make a version that includes a continuously released source from t0 to t1
					continuousreleaseargs = [q.args[2].args[1].args[2:end]; symbol("lambda"); symbol("t0"); symbol("t1")]
					# start by making the kernel of the time integral
					qck = quote
						function $(symbol(string("long_", shortfunctionname, "_ckernel")))(thiswillbereplaced) # this function defines the kernel that the continuous release function integrates against
							return cinnerkernel(Val{$numberofdimensions}, x, tau, $x0s, $sigma0s, $vs, $sigmas, $Hs, $xbs, lambda, t0, t1, t, $dispersions, $sources, $boundaries, nothing)
						end
					end
					qck.args[2].args[1].args = [qck.args[2].args[1].args[1]; continuousreleaseargs[1:end]...; symbol("t")] # give it the correct set of arguments
					eval(qck) # evaluate the kernel function definition
					# now make a function that integrates the kernel
					qc = quote
						function $(symbol(string("long_", shortfunctionname, "_c")))(thiswillbereplaced) # this function defines the continuous release function
							return kernel_c(x, t, $x0s, $sigma0s, $vs, $sigmas, $Hs, $xbs, lambda, t0, t1, $dispersions, $sources, $boundaries, nothing)
						end
					end
					continuousreleaseargs[2] = symbol("t")
					qc.args[2].args[1].args = [qc.args[2].args[1].args[1]; continuousreleaseargs[1:end]...] # give it the correct set of arguments
					eval(qc)
					continuousreleaseargs[2] = symbol("tau")
					qcf = quote
						function $(symbol(string("long_", shortfunctionname, "_cf")))(thiswillbereplaced) # this function defines the continuous release function
							return kernel_cf(x, t, $x0s, $sigma0s, $vs, $sigmas, $Hs, $xbs, lambda, t0, t1, sourcestrength, $dispersions, $sources, $boundaries, nothing)
						end
					end
					continuousreleaseargs[2] = symbol("t")
					qcf.args[2].args[1].args = [qcf.args[2].args[1].args[1]; continuousreleaseargs[1:end]...; :(sourcestrength::Function)] # give it the correct set of arguments
					eval(qcf)
				end
			end
		end
	end
	MetaProgTools.replacesymbol!(bigq, :numberofdimensions, n)
	eval(bigq)
end

end
