# Matrix Multiplication Driver
#
# This is a driver program to test various ways of computing
# the product:
#                 C = A * B
#
# A and B are constant matrices, square and the order is
# set as a constant, ORDER (see definitions.py). This is so
# we can make a quick test of the multiplication result.
#
# History:   C++ version written by Tim Mattson, August 2010
#            Modified by Simon McIntosh-Smith, September 2011
#            Modified by Tom Deakin and Simon McIntosh-Smith, October 2012
#            Ported to Python by Tom Deakin, July 2013
#            Ported to Julia by Jake Bolewski, Nov 2013

using OpenCL

const kernel_source = """
__kernel void mmul(
	const int Mdim,
	const int Ndim,
	const int Pdim,
	__global float* A,
	__global float* B,
	__global float* C)
{
	int k;
	int i = get_global_id(0);
	int j = get_global_id(1);
	float tmp;
	if ((i < Ndim) && (j < Mdim))
	{
		tmp = 0.0f;
		for (k = 0; k < Pdim; k++)
			tmp += A[i*Ndim+k] * B[k*Pdim+j];
		C[i*Ndim+j] = tmp;
	}
}
"""

#### Definitions ###

# Order of the square matrices A, B and C
ORDER = 512

# A elemetns are constant and equal to AVAL
AVAL = 3.0

# B elemetns are constant and equal to BVAL
BVAL = 5.0

# tolerance used in floating point comparisons
TOL = 0.001

# Max dim for NDRange
DIM = 2

# number of times to do each multiplication
COUNT = 1

# Helper functions
include("helper.jl")

# A[N,P], B[P M], C[N,M]
Ndim = ORDER
Pdim = ORDER
Mdim = ORDER

# Number of elements in the matrix
sizeA = Ndim * Pdim
sizeB = Pdim * Mdim
sizeC = Ndim * Mdim

# Number of elements in the matrix
h_A = fill(Float32(AVAL), sizeA)
h_B = fill(Float32(BVAL), sizeB)
h_C = Vector{Float32}(undef, sizeC)

# %20 improvment using @inbounds
function seq_mat_mul_sdot(Mdim::Int, Ndim::Int, Pdim::Int,
                          A::Array{T}, B::Array{T}, C::Array{T}) where T
    for i in 1:Ndim
        for j in 1:Mdim
            tmp = zero(Float32)
            for k in 1:Pdim
                @inbounds tmp += A[(i-1)*Ndim+k] * B[(k-1)*Pdim+j]
            end
            @inbounds C[(i-1)*Ndim+j] = tmp
        end
    end
end

@info("=== Julia, matix mult (dot prod), order $ORDER ===")

# force compilation
seq_mat_mul_sdot(Mdim, Ndim, Pdim, h_A, h_B, h_C)

for i in 1:COUNT
    fill!(h_C, 0.0)
    t1 = time()
    seq_mat_mul_sdot(Mdim, Ndim, Pdim, h_A, h_B, h_C)
    t2 = time()
    results(Mdim, Ndim, Pdim, h_C, t2 - t1)
end

# create OpenCL arrays
d_a = CLArray(h_A; access=:r)
d_b = CLArray(h_B; access=:r)
d_c = CLArray{Float32}(undef, length(h_C); access=:w)

prg  = cl.Program(source=kernel_source) |> cl.build!
mmul = cl.Kernel(prg, "mmul")

@info("=== OpenCL, matrix mult, C(i, j) per work item, order $Ndim ====")

for i in 1:COUNT
    fill!(h_C, 0.0)

    global_size = (Ndim, Mdim)

    # You can enable profiling events on the queue
    # by calling the constructor with the :profile flag
    cl.queue!(:profile) do
        evt = clcall(mmul, Tuple{Int32, Int32, Int32, Ptr{Float32}, Ptr{Float32}, Ptr{Float32}},
                     Mdim, Ndim, Pdim, d_a, d_b, d_c; global_size)
        wait(evt)

        # profiling events are measured in ns
        run_time = evt.profile_duration / 1e9
        cl.copy!(h_C, d_c)
        results(Mdim, Ndim, Pdim, h_C, run_time)
    end
end
