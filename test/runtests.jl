module TestStructuredArrays

using Test, TypeUtils, StructuredArrays, OffsetArrays
using TypeUtils: Converter
using StructuredArrays: value, shape, shape_type, checked_shape, step_type, origin_type, Returns
using Base: OneTo, has_offset_axes

const counter = Ref(0)
get_counter(args...; kwds...) = counter[]
set_counter(val::Integer) = counter[] = val
reset_counter(args...; kwds...) = set_counter(0)
incr_counter(args...; kwds...) = set_counter(get_counter() + 1)

@generated my_mapfoldl(f, op, x::NTuple{N,Any}) where {N} = StructuredArrays.unrolled_mapfoldl(:f, :op, :x, N)
@generated my_mapfoldr(f, op, x::NTuple{N,Any}) where {N} = StructuredArrays.unrolled_mapfoldr(:f, :op, :x, N)

to_mesh_offset(::Type{R}) where {R<:Real} = Converter(to_mesh_offset, R)
to_mesh_offset(::Type{R}, x::Integer) where {R<:Real} = as(Int, x)
to_mesh_offset(::Type{R}, x::Real) where {R<:Real} = as(R, x)

function mesh_node(stp::Union{Number,NTuple{N,Number}}, org::Nothing,
    idx::NTuple{N,Int}) where {N}
    return idx .* stp
end

function mesh_node(stp::Union{Number,NTuple{N,Number}}, org::Union{Real,NTuple{N,Real}},
    idx::NTuple{N,Int}) where {N}
    return (idx .- org) .* stp
end

function string_from_show(x, m=nothing)
    io = IOBuffer()
    if m === nothing
        show(io, x)
    else
        show(io, m, x)
    end
    return String(take!(io))
end

@testset "StructuredArrays package" begin

    @testset "Utilities" begin
        # Shape methods.
        @test @inferred(checked_shape(())) === ()
        @test @inferred(checked_shape(2)) === (2,)
        @test @inferred(checked_shape(0x2)) === (2,)
        @test @inferred(checked_shape(1:3)) === (1:3,)
        @test @inferred(checked_shape(OneTo(11))) === (11,)
        @test @inferred(checked_shape(0x2:0x4)) === (2:4,)
        @test @inferred(checked_shape((3,))) === (3,)
        @test @inferred(checked_shape((0x4, Int16(0), 1,))) === (4, 0, 1,)
        @test @inferred(checked_shape((4, OneTo{Int16}(8), 1,))) === (4, 8, 1,)
        @test @inferred(checked_shape((OneTo(7), 2:6, 5))) === (7, 2:6, 5)
        @test_throws ArgumentError checked_shape(-1)      # bad value
        @test_throws ArgumentError checked_shape(1:2:6)   # bad step
        @test_throws ArgumentError checked_shape("hello") # bad type
        A = ones(3, 4)
        @test shape(A) === size(A)
        B = OffsetArray(A, OneTo(3), -1:2)
        @test shape(B) in ((1:3, -1:2), (3, -1:2))

        # Meta-programming for unrolling.
        t = (1, 3, 8)
        @test my_mapfoldl(float, =>, t) === mapfoldl(float, =>, t)
        @test my_mapfoldr(float, =>, t) === mapfoldr(float, =>, t)

        # `foreach` replacement.
        # ... on tuples:
        for n = 0:33
            reset_counter()
            @test StructuredArrays.foreach(incr_counter, ntuple(identity, Val(n))) === nothing
            @test get_counter() == n
        end
        # ... on other iterables:
        A = 1:17
        reset_counter()
        @test StructuredArrays.foreach(incr_counter, A) === nothing
        @test get_counter() == length(A)

        # `Returns` replacement.
        v1, v2 = π, Float32(π)
        f1 = @inferred StructuredArrays.Returns(v1)
        f2 = @inferred StructuredArrays.Returns(v2)
        @test f1 === @inferred StructuredArrays.Returns{typeof(v1)}(v1)
        @test f2 === @inferred StructuredArrays.Returns{typeof(v2)}(v2)
        @test f2 === @inferred StructuredArrays.Returns{typeof(v2)}(v1)
        for (f, v) in ((f1, v1), (f2, v2))
            @test f() === v
            @test f(1) === v
            @test f(1, 2) === v
            @test f(; gizmo=3) === v
        end
    end

    uniform_types = (UniformArray, FastUniformArray, MutableUniformArray)
    uniform_values = (1.2, pi, missing, NaN)
    @testset "Comparison of `$U($x,m...)` and `$V($y,n...))`" for U in uniform_types, V in uniform_types, x in uniform_values, y in uniform_values
        @test isequal(U(x, 0), V(y, 0)) === true # empty arrays of same axes
        @test isequal(U(x, 0, 1), V(y, 1:0, 1)) === true # empty arrays of same axes
        @test isequal(U(x, 0), V(y, 0, 1)) === false # both empty but not same axes
        @test isequal(U(x, 2, 3), V(y, 2, 3)) === isequal(x, y)
        @test isequal(U(x, 2, 1:3), V(y, 2, 3)) === isequal(x, y)
        @test isequal(U(x, 2, 1:3), V(y, 2, 0:2)) === false # not same axes

        @test (U(x, 0) == V(y, 0)) === true # empty arrays of same axes
        @test (U(x, 0, 1) == V(y, 1:0, 1)) === true # empty arrays of same axes
        @test (U(x, 0) == V(y, 0, 1)) === false # both empty but not same axes
        @test (U(x, 2, 3) == V(y, 2, 3)) === (x == y)
        @test (U(x, 2, 1:3) == V(y, 2, 3)) === (x == y)
        @test (U(x, 2, 1:3) == V(y, 2, 0:2)) === false # not same axes

        @test cmp(U(x, 0), V(y, 0)) === 0
        @test cmp(U(x, 0), V(y, 1)) === -1
        @test cmp(U(x, 1), V(y, 0)) === 1
        @test cmp(U(x, 1), V(y, 1)) === cmp(x, y)
    end

    @testset "Uniform arrays ($K)" for K in (UniformArray,
        FastUniformArray,
        MutableUniformArray)
        dims = (Int8(2), Int16(3), Int32(4))
        inds = (Int8(0):Int8(1), OneTo{Int16}(3), Int16(-2):Int16(1),)
        @test as_array_size(dims) === map(Int, dims)
        @test as_array_size(inds) === as_array_size(dims)
        N = length(dims)
        vals = (Float64(2.1), UInt32(7), UInt16(11),
            Float32(-6.2), Float64(pi), Int16(-4))
        for k in 1:6
            x = vals[k]
            T = typeof(x)
            A = k == 1 ? K(x, dims) :
                k == 2 ? K(x, dims...) :
                k == 3 ? K{T}(x, dims) :
                k == 4 ? K{T}(x, dims...) :
                k == 5 ? K{T,N}(x, dims) :
                k == 6 ? K{T,N}(x, dims...) : break
            B = k == 1 ? K(x, inds) :
                k == 2 ? K(x, inds...) :
                k == 3 ? K{T}(x, inds) :
                k == 4 ? K{T}(x, inds...) :
                k == 5 ? K{T,N}(x, inds) :
                k == 6 ? K{T,N}(x, inds...) : break
            @test findfirst("$K{", repr(A)) !== nothing
            @test eltype(A) === T
            @test eltype(B) === T
            @test ndims(A) == N
            @test ndims(B) == N
            @test size(A) == dims
            @test size(B) == dims
            @test ntuple(i -> size(A, i), ndims(A) + 1) == (size(A)..., 1)
            @test ntuple(i -> size(B, i), ndims(B) + 1) == (size(B)..., 1)
            @test_throws BoundsError size(A, 0)
            @test_throws BoundsError size(B, 0)
            @test axes(A) === map(OneTo{Int}, dims)
            @test axes(B) === map(x -> convert_eltype(Int, x), inds)
            @test ntuple(i -> axes(A, i), ndims(A) + 1) == (axes(A)..., OneTo(1))
            @test ntuple(i -> axes(B, i), ndims(B) + 1) == (axes(B)..., OneTo(1))
            @test_throws BoundsError axes(A, 0)
            @test_throws BoundsError axes(B, 0)
            @test has_offset_axes(A) == false
            @test has_offset_axes(B) == true
            @test IndexStyle(A) === IndexLinear()
            @test IndexStyle(B) === IndexLinear()
            @test IndexStyle(typeof(A)) === IndexLinear()
            @test IndexStyle(typeof(B)) === IndexLinear()
            @test A == fill!(Array{T}(undef, size(A)), A[1])
            @test_throws Exception A[1] = zero(T)
            @test_throws Exception B[1] = zero(T)
            @test_throws BoundsError A[0]
            @test_throws BoundsError B[0]
            x -= one(x)
            if K <: MutableUniformArray
                A[:] = x
                @test all(isequal(x), A)
                B[:] = x
                @test all(isequal(x), B)
                x -= one(x)
                A[1:end] = x
                @test A[end] == A[1] == x
                B[1:end] = x
                @test B[end] == B[1] == x
                x -= one(x)
                A[1:length(A)] = x
                @test A[end] == A[1] == x
                B[firstindex(B):lastindex(B)] = x
                @test B[end] == B[firstindex(B)] == x
                A = A .+ one(x)
                @test A[end] == A[1] == x + one(x)
                @test typeof(A) === typeof(A .+ one(x))
                A = A .- one(x)
                @test A[end] == A[1] == x

            else
                @test_throws Exception A[:] = x
            end
            # `copy(A)` and `deepcopy(A)` simply yields `A` if it is immutable.
            let C = @inferred copy(A)
                @test C == A
                @test (C === A) == !(A isa MutableUniformArray)
            end
            let C = @inferred deepcopy(A)
                @test C == A
                @test (C === A) == !(A isa MutableUniformArray)
            end
            # Mapping and broadcasting of functions.
            C = if !(A isa FastUniformArray) || v"1.1" ≤ VERSION ≤ v"1.3" || VERSION ≥ v"1.7"
                # Inference for fast uniform arrays only works on some Julia versions
                @inferred map(sin, A)
            else
                map(sin, A)
            end
            @test C isa K
            @test ndims(C) === ndims(A)
            @test shape(C) === shape(A)
            @test value(C) === sin(value(A))
            if K <: MutableUniformArray
                @test C == sin.(A)
            else
                @test C === sin.(A)
            end
            C = if !(B isa FastUniformArray) || v"1.1" ≤ VERSION ≤ v"1.3" || VERSION ≥ v"1.7"
                # Inference for fast uniform arrays only works on some Julia versions
                @inferred map(cos, B)
            else
                map(cos, B)
            end
            @test C isa K
            @test ndims(C) === ndims(B)
            @test shape(C) === shape(B)
            @test value(C) === cos(value(B))
            if K <: MutableUniformArray
                @test C == cos.(B)
            else
                @test C === cos.(B)
            end
        end

        # Check conversion of value.
        let A = @inferred K{Float32}(π, dims)
            @test eltype(A) === Float32
            @test first(A) === Float32(π)
        end

        # All true and all false uniform arrays.
        let A = K(true, dims), B = K(false, dims)
            @test all(A) === true
            @test count(A) == length(A)
            if A isa MutableUniformArray
                A[:] = false
                B = A
            else
                B = K(false, dims)
            end
            @test all(B) === false
            @test count(B) == 0
        end

        # For fast uniform arrays, the value can be specified as a type parameter.
        if K === FastUniformArray
            val = -1.23
            if VERSION < v"1.2"
                # Inference is broken for some versions of Julia.
                @test K(true, inds) === K{Bool,length(inds),true}(inds)
                @test K(val, inds) === K{typeof(val),length(inds),val}(inds)
            else
                @test K(true, inds) === @inferred K{Bool,length(inds),true}(inds)
                @test K(val, inds) === @inferred K{typeof(val),length(inds),val}(inds)
            end
        end

        # Check that axes specified as `Base.OneTo(dim)` is stored as `dim`.
        let A = K(-7.4, 2, OneTo(3), 1:4)
            @test A isa AbstractUniformArray{eltype(A),ndims(A),Tuple{Int,Int,UnitRange{Int}}}
        end

        # Aliases.
        V = K === UniformArray ? UniformVector :
            K === FastUniformArray ? FastUniformVector :
            K === MutableUniformArray ? MutableUniformVector : Nothing
        M = K === UniformArray ? UniformMatrix :
            K === FastUniformArray ? FastUniformMatrix :
            K === MutableUniformArray ? MutableUniformMatrix : Nothing
        let A = (K{Float32}(3.0, 5)), #=@inferred=#
            B = (V(first(A), length(A))), #=@inferred=#
            C = (V{eltype(A)}(first(A), length(A)))
            #=@inferred=#
            if isimmutable(A)
                @test B === A
                @test C === A
            else
                @test first(B) === first(A)
                @test eltype(B) === eltype(A)
                @test axes(B) === axes(A)
                @test first(C) === first(A)
                @test eltype(C) === eltype(A)
                @test axes(C) === axes(A)
            end
        end
        let A = (K{Float32}(-3.0, 5, 2)), #=@inferred=#
            B = (M(first(A), size(A))), #=@inferred=#
            C = (M{eltype(A)}(first(A), size(A)))
            #=@inferred=#
            if isimmutable(A)
                @test B === A
                @test C === A
            else
                @test first(B) === first(A)
                @test eltype(B) === eltype(A)
                @test axes(B) === axes(A)
                @test first(C) === first(A)
                @test eltype(C) === eltype(A)
                @test axes(C) === axes(A)
            end
        end

        # Colon and range indexing of uniform arrays.
        x = K === UniformArray ? π :
            K === FastUniformArray ? 3.1 :
            K === MutableUniformArray ? Int8(5) : nothing
        A = K(x, dims)
        @test A isa K{typeof(x)}
        @test A[:] isa Array{eltype(A)}
        @test length(A[:]) == length(A)
        @test first(A[:]) === first(A)
        @test_throws BoundsError A[firstindex(A)-1:2:lastindex(A)]
        @test_throws BoundsError A[firstindex(A):2:lastindex(A)+1]
        r = firstindex(A):2:lastindex(A)
        @test A[r] isa Array{eltype(A)}
        @test length(A[r]) == length(r)
        @test first(A[r]) == first(A)
        r = firstindex(A):firstindex(A)-1
        @test A[r] isa Array{eltype(A)}
        @test length(A[r]) == 0

        # Sub-indexing a uniform array yields uniform array (or a scalar).
        let B = Array(A)
            @test B isa Array{eltype(A),ndims(A)}
            funcs = A isa MutableUniformArray ? (getindex,) : (getindex, view)
            @testset "sub-indexing ($f)" for f in funcs
                R = f === getindex ? Array : K
                let I = (1, 2, 3), X = f(A, I...), Y = f(B, I...)
                    # should yield a scalar when sub-indexing
                    @test X isa (f === getindex ? eltype(A) : K{eltype(A),ndims(Y)})
                    @test X == Y
                end
                let I = (1, 2, 3, 1, 1), X = f(A, I...), Y = f(B, I...)
                    # should yield a scalar when sub-indexing
                    @test X isa (f === getindex ? eltype(A) : K{eltype(A),ndims(Y)})
                    @test X == Y
                end
                # result is an array
                let I = (1, 2:2, 3, 1), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test X == Y
                end
                let I = (1, 2, 3, 1, 1:1), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test X == Y
                end
                let I = (1, 2:2, 3, 1, 1:1), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test X == Y
                end
                let I = (:,), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test X == Y
                end
                let I = (:, :, :), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test axes(X) === axes(A)
                    @test X == Y
                end
                let I = ntuple(i -> i:size(A, i), ndims(A)), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test size(X) == map(length, I)
                    @test X == Y
                end
                let I = (:, 2, 2:4), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(A) - 1}
                    @test X == Y
                end
                let I = (:, [true, false, true], :), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test X == Y
                end
                if v"1.6" ≤ VERSION ≤ v"1.10"
                    let I = (:, [true false true], :), X = f(A, I...), Y = f(B, I...)
                        @test X isa R{eltype(A),ndims(Y)}
                        @test X == Y
                    end
                end
                let I = (:, [2, 1, 2, 3], :), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test X == Y
                end
                let I = (falses(size(A)),), X = f(A, I...), Y = f(B, I...)
                    @test X isa R{eltype(A),ndims(Y)}
                    @test X == Y
                end
            end
        end

        # Check ambiguities.
        let B = A[:] # a uniform vector
            @test eltype(B) === eltype(A)
            @test ndims(B) == 1
            @test length(B) == length(A)
            @test all(isequal(first(B)), B)
            @test B[0x1] === B[1]
            C = B[:]
            @test typeof(C) === typeof(B)
            @test length(C) == length(B)
            @test all(isequal(first(C)), C)
        end

        # Array with zero dimensions.
        C = K{Int,0}(17)
        @test C[1] == 17
        @test Base.axes1(C) == 1:1
        @test has_offset_axes(C) == false

        if K <: MutableUniformArray
            # Using index 1 to set a single-element mutable uniform array is allowed.
            D = K(11, 1)
            @test D[1] == 11
            D[1] = 6
            @test D[1] == 6
        end

        # Call constructors with illegal dimension.
        @test_throws ArgumentError K{Int}(17, 1, -1)
    end

    val_list = (true, false, 0, 3, 3.0)
    dims_list = (:, 1, 2, 3, (2,), [3, 3], (2, 1), [3, 2],
        # NOTE: Specifying dimensions larger than number of dimensions
        #       is only supported in Julia ≥ 1.8
        VERSION ≥ v"1.8" ? [1, 3, 4] : [1, 3],
        1:3)
    @testset "Optimized methods for uniform arrays (val=$val, shape=$inds)" for val in val_list, inds in ((2, 3, 4), (2, 3, -1:2))
        A = @inferred(UniformArray(val, inds))
        B = shape_type(A) <: Dims{ndims(A)} ? Array(A) : OffsetArray(A)
        @test A == B
        @test findfirst("UniformArray{", repr(A)) !== nothing
        @testset "... with `dims=$dims`" for dims in dims_list
            f(x) = x > zero(x)
            if dims isa Colon
                @test all(f, B) == @inferred(all(f, A))
                @test any(f, B) == @inferred(any(f, A))
                @test extrema(B) == @inferred(extrema(A))
                @test findmax(B) == @inferred(findmax(A))
                @test findmin(B) == @inferred(findmin(A))
                @test maximum(B) == @inferred(maximum(A))
                @test minimum(B) == @inferred(minimum(A))
                @test prod(B) == @inferred(prod(A))
                @test sum(B) == @inferred(sum(A))
                if VERSION ≥ v"1.6"
                    @test reverse(B) == @inferred(reverse(A))
                end
                @test unique(B) == @inferred(unique(A))
            end
            @test all(f, B; dims=dims) == all(f, A; dims=dims)
            @test any(f, B; dims=dims) == any(f, A; dims=dims)
            # Before Julia 1.8, `extrema(A;dims=d)` with `d` a number does not work for
            # `OffsetArray` instances if they have offset axes.
            if dims isa Colon || !has_offset_axes(A) || VERSION ≥ v"1.8"
                @test extrema(B; dims=dims) == extrema(A; dims=dims)
            end
            @test findmax(B; dims=dims) == findmax(A; dims=dims)
            @test findmin(B; dims=dims) == findmin(A; dims=dims)
            @test maximum(B; dims=dims) == maximum(A; dims=dims)
            @test minimum(B; dims=dims) == minimum(A; dims=dims)
            @test prod(B; dims=dims) == prod(A; dims=dims)
            @test sum(B; dims=dims) == sum(A; dims=dims)
            if dims isa Integer || ((dims isa Tuple || dims isa Colon) && VERSION ≥ v"1.6")
                @test reverse(B; dims=dims) == @inferred reverse(A; dims=dims)
            end
            if dims isa Integer || dims isa Colon
                @test unique(B; dims=dims) == @inferred unique(A; dims=dims)
            end
        end
    end

    @testset "Structured arrays (StructuredArray)" begin
        dims = (Int8(3), Int16(4))
        N = length(dims)
        f1(i) = -2i
        f2(i, j) = (-1 ≤ i - j ≤ 2)
        T1 = typeof(f1(1))
        T2 = typeof(f2(1, 1))
        S1 = IndexLinear
        S2 = IndexCartesian
        for A in (StructuredArray(S2, f2, dims),
            StructuredArray(S2(), f2, dims...),
            StructuredArray{T2}(S2(), f2, dims),
            StructuredArray{T2}(S2, f2, dims...),
            StructuredArray{T2,N}(S2, f2, as_array_size(dims)),
            StructuredArray{T2,N}(S2(), f2, dims...),
            StructuredArray{T2,N,S2}(f2, dims),
            StructuredArray{T2,N,S2}(f2, as_array_size(dims)...),
            StructuredArray{T2,N,S2}(S2, f2, dims),
            StructuredArray{T2,N,S2}(S2(), f2, dims...),
            StructuredArray(f2, dims),
            StructuredArray(f2, dims...),
            StructuredArray{T2}(f2, dims),
            StructuredArray{T2}(f2, dims...),
            StructuredArray{T2,N}(f2, dims),
            StructuredArray{T2,N}(f2, dims...),)
            @test eltype(A) === T2
            @test ndims(A) == N
            @test size(A) == dims
            @test ntuple(i -> size(A, i), ndims(A) + 1) == (size(A)..., 1)
            @test_throws BoundsError size(A, 0)
            @test axes(A) === map(OneTo, size(A))
            @test ntuple(i -> axes(A, i), ndims(A) + 1) == (axes(A)..., OneTo(1))
            @test_throws BoundsError axes(A, 0)
            @test has_offset_axes(A) == false
            @test IndexStyle(A) === IndexCartesian()
            @test IndexStyle(typeof(A)) === IndexCartesian()
            @test A == [f2(i, j) for i in 1:dims[1], j in 1:dims[2]]
            #@test_throws ErrorException A[1,1] = zero(T)
            @test_throws BoundsError A[0, 1]
            if shape_type(A) <: Dims
                @test A == @inferred Array(A)
            end
            @test A == @inferred OffsetArray(A)
        end
        for A in (StructuredArray(S1, f1, dims),
            StructuredArray(S1(), f1, dims...),
            StructuredArray{T1}(S1(), f1, dims),
            StructuredArray{T1}(S1, f1, dims...),
            StructuredArray{T1,N}(S1, f1, dims),
            StructuredArray{T1,N}(S1(), f1, dims...),
            StructuredArray{T1,N,S1}(f1, dims),
            StructuredArray{T1,N,S1}(f1, dims...),
            StructuredArray{T1,N,S1}(S1, f1, dims),
            StructuredArray{T1,N,S1}(S1(), f1, dims...),)
            I = LinearIndices(A)
            @test eltype(A) === T1
            @test ndims(A) == N
            @test size(A) == dims
            @test ntuple(i -> size(A, i), ndims(A) + 1) == (size(A)..., 1)
            @test_throws BoundsError size(A, 0)
            @test axes(A) === map(OneTo, size(A))
            @test ntuple(i -> axes(A, i), ndims(A) + 1) == (axes(A)..., OneTo(1))
            @test_throws BoundsError axes(A, 0)
            @test has_offset_axes(A) == false
            @test IndexStyle(A) === IndexLinear()
            @test IndexStyle(typeof(A)) === IndexLinear()
            @test A == [f1(I[CartesianIndex(i, j)]) for i in 1:dims[1], j in 1:dims[2]]
            #@test_throws ErrorException A[1,1] = zero(T)
            @test_throws BoundsError A[0, 1]
            if shape_type(A) <: Dims
                @test A == @inferred Array(A)
            end
            @test A == @inferred OffsetArray(A)
        end

        # Call constructors with illegal dimension.
        @test_throws ArgumentError StructuredArray{Bool}((i, j) -> i ≥ j, 1, -1)
    end

    @testset "Cartesian meshes (step=$stp, origin=$(repr(org)))" for (stp, org) in ((0.1f0, nothing),
        ((0.1f0, 0.2f0), nothing),
        ((1.4, 0.9), (11, 12)),
        ((1 // 2, 3 // 4), (10.5, 4.7)),
        ((0.1f0, 0.2f0, 0.3f0), (-1, 0, 1)))
        A = @inferred CartesianMesh(stp, org)
        stp′ = @inferred step(A)
        org′ = @inferred origin(A)
        N = stp isa Tuple ? length(stp) : org isa Tuple ? length(org) : 1
        @test A isa CartesianMesh{N,typeof(stp′),typeof(org′)}
        @test typeof(stp′) === @inferred step_type(A)
        @test typeof(org′) === @inferred origin_type(A)
        @test N === @inferred ndims(A)
        R = real_type(stp′...)
        @test (org isa Tuple) === (org′ isa Tuple)
        @test (stp isa Tuple) === (stp′ isa Tuple)
        if org isa Nothing
            @test org′ === nothing
            @test ntuple(Returns(0), N) === @inferred origin(Tuple, A)
        elseif org isa Tuple
            @test all(org′ .≈ org)
            @test org′ === map(to_mesh_offset(R), org)
            @test org′ === @inferred origin(Tuple, A)
        else
            @test org′ ≈ org
            @test org′ === to_mesh_offset(R, org)
            @test ntuple(Returns(org′), N) === @inferred origin(Tuple, A)
        end
        if stp isa Tuple
            @test all(stp′ .≈ stp)
            @test stp′ === map(convert_real_type(R), stp)
            @test stp′ === @inferred step(Tuple, A)
        else
            @test stp′ ≈ stp
            @test stp′ === convert_real_type(R, stp)
            @test ntuple(Returns(stp′), N) === @inferred step(Tuple, A)
        end
        I = ((1,), (2, 3), (2, 3, -5))[N]
        J = ((-2,), (-1, 4), (5, -2, 1))[N]
        K = ((0,), (3, -2), (-1, 2, -3))[N]
        A_I = mesh_node(step(A), origin(A), I)
        A_J = mesh_node(step(A), origin(A), J)
        A_K = mesh_node(step(A), origin(A), K)
        T = typeof(A_I)
        @test T === @inferred eltype(A)
        @test A_I === @inferred A(I)
        @test A_J === @inferred A(J)
        @test A_K === @inferred A(K)
        @test A_I === @inferred A(I...)
        @test A_J === @inferred A(J...)
        @test A_K === @inferred A(K...)
        @test A_I === @inferred A(CartesianIndex(I))
        @test A_J === @inferred A(CartesianIndex(J))
        @test A_K === @inferred A(CartesianIndex(K))

        inds = ntuple(Returns(-15:20), N)
        X = @inferred StructuredArray(A, inds)
        @test X === @inferred CartesianMeshArray(inds...; step=stp, origin=org)
        @test N === @inferred ndims(X)
        @test typeof(stp′) === @inferred step_type(X)
        @test typeof(org′) === @inferred origin_type(X)
        @test T === @inferred eltype(X)
        @test stp′ === @inferred step(X)
        @test org′ === @inferred origin(X)
        @test step(Tuple, A) === @inferred step(Tuple, X)
        @test origin(Tuple, A) === @inferred origin(Tuple, X)
        @test A_I === @inferred X[I...]
        @test A_J === @inferred X[J...]
        @test A_K === @inferred X[K...]
        @test A_I === @inferred X[CartesianIndex(I)]
        @test A_J === @inferred X[CartesianIndex(J)]
        @test A_K === @inferred X[CartesianIndex(K)]
        @test startswith(string_from_show(X), "CartesianMeshArray{")
        @test startswith(string_from_show(X, MIME"text/plain"()), "CartesianMeshArray{")

        # Unary plus and minus.
        @test @inferred(+A) === A
        @test @inferred(-A) === @inferred(-one(R) * A)

        # Multiplication of mesh by a scalar.
        B = @inferred 3A
        @test B === @inferred A * 3
        @test all(step(B) .≈ (step(A) .* 3))
        @test origin(B) === origin(A)
        @test all(B(I) .≈ (A(I) .* 3))
        @test all(B(J) .≈ (A(J) .* 3))
        @test all(B(K) .≈ (A(K) .* 3))

        # Division of mesh by a scalar.
        B = @inferred A / 2
        @test B === @inferred 2 \ A
        @test all(step(B) .≈ (step(A) ./ 2))
        @test origin(B) === origin(A)
        @test all(B(I) .≈ (A(I) ./ 2))
        @test all(B(J) .≈ (A(J) ./ 2))
        @test all(B(K) .≈ (A(K) ./ 2))

        # Shift of a mesh.
        s = map(convert_real_type(R), ((1:N)...,)) .* step(A)
        B = @inferred(A + s)
        @test all(B(I) .≈ (A(I) .+ s))
        @test all(B(J) .≈ (A(J) .+ s))
        @test all(B(K) .≈ (A(K) .+ s))
        @test B === @inferred(s + A)
        B = @inferred(A - s)
        @test all(B(I) .≈ (A(I) .- s))
        @test all(B(J) .≈ (A(J) .- s))
        @test all(B(K) .≈ (A(K) .- s))
        B = @inferred(s - A)
        @test all(B(I) .≈ (s .- A(I)))
        @test all(B(J) .≈ (s .- A(J)))
        @test all(B(K) .≈ (s .- A(K)))

        # Comparison.
        z = ntuple(Returns(zero(R)), Val(N)) .* step(A)
        @test !isequal(A, CartesianMesh{N + 1}(0.1, nothing))
        @test isequal(@inferred(A + z), A)
        @test isequal(@inferred(z + A), A)
        @test isequal(@inferred(A - z), A)
        @test isequal(@inferred(z - A), -A)
        @test A != CartesianMesh{N + 1}(0.1, nothing)
        @test @inferred(A + z) == A
        @test @inferred(z + A) == A
        @test @inferred(A - z) == A
        @test @inferred(z - A) == -A

        if stp isa Number && org isa Union{Nothing,Real}
            A = @inferred CartesianMesh{2}(stp, org)
            @test A isa CartesianMesh{2}
            I = (2, 3)
            J = (-1, 4)
            K = (3, -2)
            A_I = mesh_node(step(A), origin(A), I)
            A_J = mesh_node(step(A), origin(A), J)
            A_K = mesh_node(step(A), origin(A), K)
            T = typeof(A_I)
            @test T === @inferred eltype(A)
            @test 2 === @inferred ndims(A)
            @test A_I === @inferred A(I)
            @test A_J === @inferred A(J)
            @test A_K === @inferred A(K)
            @test A_I === @inferred A(I...)
            @test A_J === @inferred A(J...)
            @test A_K === @inferred A(K...)
            @test A_I === @inferred A(CartesianIndex(I))
            @test A_J === @inferred A(CartesianIndex(J))
            @test A_K === @inferred A(CartesianIndex(K))
            @test all(A_I .≈ mesh_node(stp, org, I))
            @test all(A_J .≈ mesh_node(stp, org, J))
            @test all(A_K .≈ mesh_node(stp, org, K))
        end
    end
end

end # module

nothing
