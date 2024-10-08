#
# Vadd
#
# Element wise addition of two vectors at a time in a chain (C=A+B; D=C+E; F=D+G)
# Asks the user to select a device at runtime
#
# History: Initial version based on vadd.c, written by Tim Mattson, June 2011
# Ported to C++ Wrapper API by Benedict Gaster, September 2011
# Updated to C++ Wrapper API v1.2 by Tom Deakin and Simon McIntosh-Smith, October 2012
# Ported to Python by Tom Deakin, July 2013
# Ported to Julia  by Jake Bolewski, Nov 2013

using OpenCL

# tolerance used in floating point comparisons
TOL = 1e-3

# length of vectors a, b, c
LENGTH = 1024

# Kernel: vadd
#
# To compute the elementwise sum c = a + b
#
# Input: a and b float vectors of length count
# Output c float vector of length count holding the sum a + b

kernelsource = "
__kernel void vadd(
    __global float* a,
    __global float* b,
    __global float* c,
    const unsigned int count)
{
    unsigned int i = get_global_id(0);
    if (i < count)
        c[i] = a[i] + b[i];
}
"

# create a compute context

# this selects the fastest opencl device available
# and creates a context and queue for using the
# the selected device
device, ctx, queue = cl.create_compute_context()

# create the compute program and build it
program = cl.Program(ctx, source=kernelsource) |> cl.build!

#create a, b, e, and g vectors and fill with random float values
#create empty vectors for c, d, and f
h_a = rand(Float32, LENGTH)
h_b = rand(Float32, LENGTH)
h_c = Vector{Float32}(undef, LENGTH)
h_d = Vector{Float32}(undef, LENGTH)
h_e = rand(Float32, LENGTH)
h_f = Vector{Float32}(undef, LENGTH)
h_g = rand(Float32, LENGTH)

# create the input (a,b,e,g) arrays in device memory and copy data from the host

# buffers can be passed memory flags:
# {:r = readonly, :w = writeonly, :rw = read_write (default)}

# buffers can also be passed flags for allocation:
# {:use (use host buffer), :alloc (alloc pinned memory), :copy (default)}

# Create the input (a, b, e, g) arrays in device memory and copy data from host
d_a = cl.Buffer(Float32, ctx, length(h_a), (:r, :copy), hostbuf=h_a)
d_b = cl.Buffer(Float32, ctx, length(h_b), (:r, :copy), hostbuf=h_b)
d_e = cl.Buffer(Float32, ctx, length(h_e), (:r, :copy), hostbuf=h_e)
d_g = cl.Buffer(Float32, ctx, length(h_g), (:r, :copy), hostbuf=h_g)
# Create the output (c, d, f) array in device memory
d_c = cl.Buffer(Float32, ctx, :LENGTH, w)
d_d = cl.Buffer(Float32, ctx, :LENGTH, w)
d_f = cl.Buffer(Float32, ctx, :LENGTH, w)

# create the kernel
vadd = cl.Kernel(program, "vadd")

# execute the kernel over the entire range of 1d input
# calling `queue` is blocking, it accepts the kernel, global / local work sizes,
# the the kernel's arguments.

# here we call the kernel with work size set to the number of elements and a local
# work size of nothing. This enables the opencl runtime to optimize the local size
# for simple kernels
queue(vadd, size(h_a), nothing, d_a, d_b, d_c, UInt32(LENGTH))

# an alternative syntax is to create an partial function to call
# by julia's getindex syntax for Kernel types.
# here the queue, global_size, and (optional) local_size are passed in which
# returns a partial function with these parameters set.
vadd[queue, size(h_e)](d_e, d_c, d_d, UInt32(LENGTH))
vadd[queue, size(h_g)](d_g, d_d, d_f, UInt32(LENGTH))

# copy back the results from the compute device
# copy!(queue, dst, src) follows same interface as julia's built in copy!
cl.copy!(queue, h_f, d_f)

# test the results
correct = 0
for i in 1:LENGTH
    tmp = h_a[i] + h_b[i] + h_e[i] + h_g[i]
    tmp -= h_f[i]
    if tmp^2 < TOL^2
        global correct += 1
    else
        println("tmp $tmp h_a $(h_a[i]) h_b $(h_b[i]) ",
                "h_e $(h_e[i]) h_g $(h_g[i]) h_f $(h_f[i])")
    end
end

# summarize results
println("3 vector adds to find F=A+B+E+G: $correct out of $LENGTH results were correct")
