using Test
using GeometryBasics
using LinearAlgebra
using Trace
using FileIO
using ImageCore

include("test_intersection.jl")

function check_scene_average(scene_file::String, target::Float32)
    scene = scene_file |> load |> channelview
    average = sum(scene) / length(scene)
    @test average ≈ target
end

@testset "Test Bounds2 iteration" begin
    b = Trace.Bounds2(Point2f0(1f0, 3f0), Point2f0(4f0, 4f0))
    targets = [
        Point2f0(1f0, 3f0), Point2f0(2f0, 3f0), Point2f0(3f0, 3f0), Point2f0(4f0, 3f0),
        Point2f0(1f0, 4f0), Point2f0(2f0, 4f0), Point2f0(3f0, 4f0), Point2f0(4f0, 4f0),
    ]
    @test length(b) == 8
    for (p, t) in zip(b, targets)
        @test p == t
    end

    b = Trace.Bounds2(Point2f0(-1f0), Point2f0(1f0))
    targets = [
        Point2f0(-1f0, -1f0), Point2f0(0f0, -1f0), Point2f0(1f0, -1f0),
        Point2f0(-1f0, 0f0), Point2f0(0f0, 0f0), Point2f0(1f0, 0f0),
        Point2f0(-1f0, 1f0), Point2f0(0f0, 1f0), Point2f0(1f0, 1f0),
    ]
    @test length(b) == 9
    for (p, t) in zip(b, targets)
        @test p == t
    end
end

@testset "Sphere bound" begin
    core = Trace.ShapeCore(Trace.translate(Vec3f0(0)), false)
    s = Trace.Sphere(core, 1f0, -1f0, 1f0, 360f0)

    sb = s |> Trace.object_bound
    @test sb[1] == Point3f0(-1f0)
    @test sb[2] == Point3f0(1f0)
end

@testset "LanczosSincFilter" begin
    l = Trace.LanczosSincFilter(Point2f0(4f0), 3f0)
    @test l(Point2f0(0f0)) ≈ 1f0
    @test l(Point2f0(4f0)) < 1f-6
    @test l(Point2f0(5f0)) ≈ 0f0
end

@testset "Film testing" begin
    filter = Trace.LanczosSincFilter(Point2f0(4f0), 3f0)
    film = Trace.Film(
        Point2f0(1920f0, 1080f0), Trace.Bounds2(Point2f0(0f0), Point2f0(1f0)),
        filter, 35f0, 1f0, "output.png",
    )
    @test size(film.pixels) == (1080, 1920)
    @test Trace.get_sample_bounds(film) == Trace.Bounds2(Point2f0(-3f0), Point2f0(1924f0, 1084f0))
end

@testset "FilmTile testing" begin
    filter = Trace.LanczosSincFilter(Point2f0(4f0), 3f0)
    film = Trace.Film(
        Point2f0(1920f0, 1080f0), Trace.Bounds2(Point2f0(0f0), Point2f0(1f0)),
        filter, 35f0, 1f0, "output.png",
    )
    # Test tile from start of the film.
    tile = Trace.FilmTile(film, Trace.Bounds2(Point2f0(1f0), Point2f0(10f0)))
    @test size(tile.pixels) == (14, 14)
    @test tile.bounds == Trace.Bounds2(Point2f0(1f0), Point2f0(14f0))
    # Pixels in 1:5 radius should be affected.
    for i in 1:5
        @test tile.pixels[i, i].filter_weight_sum ≈ 0f0
    end
    Trace.add_sample!(tile, Point2f0(1f0), Trace.RGBSpectrum(1f0))
    for (i, j) in zip(1:4, 2:5)
        @test tile.pixels[i, i].filter_weight_sum > 0 && tile.pixels[j, j].filter_weight_sum > 0
        @test tile.pixels[i, i].filter_weight_sum > tile.pixels[j, j].filter_weight_sum
    end
    # Merging tile back to film.
    for i in 1:5
        @test film.pixels[i, i].filter_weight_sum ≈ 0f0
    end
    Trace.merge_film_tile!(film, tile)
    for (i, j) in zip(1:4, 2:5)
        @test film.pixels[i, i].filter_weight_sum > 0 && film.pixels[j, j].filter_weight_sum > 0
        @test film.pixels[i, i].filter_weight_sum > film.pixels[j, j].filter_weight_sum
    end

    # Test shifted tile.
    tile = Trace.FilmTile(film, Trace.Bounds2(Point2f0(10f0), Point2f0(60f0)))
    @test size(tile.pixels) == (59, 59) # Account for filter radius shift.
    @test tile.bounds == Trace.Bounds2(Point2f0(6f0), Point2f0(64f0))
    # Add to [20, 20] pixel
    #   -> [16:24] radius of contribution on the film
    #   -> [16 - 6 + 1:24 - 6 + 1] = [11:19] radius of contribution on the film tile.
    for i in 11:19
        @test tile.pixels[i, i].filter_weight_sum ≈ 0f0
    end
    Trace.add_sample!(tile, Point2f0(20f0), Trace.RGBSpectrum(1f0))
    # Symmetrical.
    for (i, j) in zip(11:14, 18:-1:15)
        @test tile.pixels[i, i].filter_weight_sum ≈ tile.pixels[j, j].filter_weight_sum
    end
    # Increasing from left-to-right.
    for (i, j) in zip(11:13, 12:14)
        @test tile.pixels[i, i].filter_weight_sum > 0 && tile.pixels[j, j].filter_weight_sum > 0
        @test tile.pixels[i, i].filter_weight_sum < tile.pixels[j, j].filter_weight_sum
    end
    # Decreasing from right-to-left.
    for (i, j) in zip(16:18, 17:19)
        @test tile.pixels[i, i].filter_weight_sum > 0 && tile.pixels[j, j].filter_weight_sum > 0
        @test tile.pixels[i, i].filter_weight_sum > tile.pixels[j, j].filter_weight_sum
    end
    # Merging tile back to film.
    for i in 16:24
        @test film.pixels[i, i].filter_weight_sum ≈ 0f0
    end
    Trace.merge_film_tile!(film, tile)
    # Symmetrical.
    for (i, j) in zip(16:19, 23:-1:20)
        @test film.pixels[i, i].filter_weight_sum ≈ film.pixels[j, j].filter_weight_sum
    end
    # Increasing from left-to-right.
    for (i, j) in zip(16:18, 17:19)
        @test film.pixels[i, i].filter_weight_sum > 0 && film.pixels[j, j].filter_weight_sum > 0
        @test film.pixels[i, i].filter_weight_sum < film.pixels[j, j].filter_weight_sum
    end
    # Decreasing from right-to-left.
    for (i, j) in zip(20:23, 21:24)
        @test film.pixels[i, i].filter_weight_sum > 0 && film.pixels[j, j].filter_weight_sum > 0
        @test film.pixels[i, i].filter_weight_sum > film.pixels[j, j].filter_weight_sum
    end
end

@testset "Fresnel Dielectric" begin
    # Vacuum gives no reflectance.
    @test Trace.fresnel_dielectric(1f0, 1f0, 1f0) ≈ 0f0
    @test Trace.fresnel_dielectric(0.5f0, 1f0, 1f0) ≈ 0f0
    # Vacuum-diamond -> total reflection.
    @test Trace.fresnel_dielectric(cos(π / 4f0), 1f0, 2.42f0) ≈ 1f0
end

@testset "Fresnel Conductor" begin
    s = Trace.RGBSpectrum(1f0)
    @test Trace.fresnel_conductor(0f0, s, s, s) == s
    @test all(Trace.fresnel_conductor(cos(π / 4f0), s, s, s).c .> 0f0)
    @test all(Trace.fresnel_conductor(1f0, s, s, s).c .> 0f0)
end

@testset "SpecularReflection" begin
    sr = Trace.SpecularReflection(Trace.RGBSpectrum(1f0), Trace.FresnelNoOp())
    @test sr & Trace.BSDF_REFLECTION
    @test sr & Trace.BSDF_SPECULAR
    @test sr & (Trace.BSDF_SPECULAR | Trace.BSDF_REFLECTION)
end

@testset "SpecularTransmission" begin
    st = Trace.SpecularTransmission(
        Trace.RGBSpectrum(1f0), 1f0, 1f0,
        Trace.FresnelDielectric(1f0, 1f0),
        Trace.Radiance,
    )
    @test st & Trace.BSDF_SPECULAR
    @test st & Trace.BSDF_TRANSMISSION
    @test st & (Trace.BSDF_SPECULAR | Trace.BSDF_TRANSMISSION)
end

@testset "FresnelSpecular" begin
    f = Trace.FresnelSpecular(
        Trace.RGBSpectrum(1f0), Trace.RGBSpectrum(1f0),
        1f0, 1f0, Trace.Radiance,
    )
    @test f & Trace.BSDF_SPECULAR
    @test f & Trace.BSDF_TRANSMISSION
    @test f & Trace.BSDF_REFLECTION
    @test f & (Trace.BSDF_SPECULAR | Trace.BSDF_REFLECTION | Trace.BSDF_TRANSMISSION)

    wo = Vec3f0(0, 0, 1)
    u = Point2f0(0, 0)
    wi, pdf, bxdf_value, sampled_type = Trace.sample_f(f, wo, u)
    @test wi ≈ -wo
    @test pdf ≈ 1f0
    @test sampled_type == Trace.BSDF_SPECULAR | Trace.BSDF_TRANSMISSION
end

@testset "Perspective Camera" begin
    filter = Trace.LanczosSincFilter(Point2f0(4f0), 3f0)
    film = Trace.Film(
        Point2f0(1920f0, 1080f0), Trace.Bounds2(Point2f0(0f0), Point2f0(1f0)),
        filter, 35f0, 1f0, "output.png",
    )
    camera = Trace.PerspectiveCamera(
        Trace.translate(Vec3f0(0)), Trace.Bounds2(Point2f0(0), Point2f0(10)),
        0f0, 1f0, 0f0, 700f0, 45f0, film,
    )

    sample1 = Trace.CameraSample(Point2f0(1f0), Point2f0(1f0), 0f0)
    ray1, contribution = Trace.generate_ray(camera, sample1)
    sample2 = Trace.CameraSample(
        Point2f0(film.resolution[1]), Point2f0(film.resolution[2]), 0f0,
    )
    ray2, contribution = Trace.generate_ray(camera, sample2)

    @test contribution == 1f0
    @test ray1.o == ray2.o == Point3f0(0f0)
    @test ray1.time == ray2.time == camera.core.core.shutter_open
    @test ray1.d[1] < ray2.d[1] && ray1.d[2] < ray2.d[2]
    @test argmax(abs.(ray1.d)) == argmax(abs.(ray2.d)) == 3

    ray_differential, contribution = Trace.generate_ray_differential(
        camera, sample1,
    )
    @test ray_differential.has_differentials
    @test ray_differential.o == Point3f0(0f0)
    @test ray_differential.d ≈ Point3f0(ray1.d)

    @test ray_differential.rx_direction[1] > ray_differential.d[1]
    @test ray_differential.rx_direction[2] ≈ ray_differential.d[2]
    @test ray_differential.ry_direction[1] ≈ ray_differential.d[1]
    @test ray_differential.ry_direction[2] > ray_differential.d[2]
end

# @testset "Analytic scene" begin
#     # Unit sphere, Kd = 0.5, point light I = π at center
#     # With GI, should have radiance of 1.
#     material = Trace.MatteMaterial(
#         Trace.ConstantTexture(Trace.RGBSpectrum(1f0)),
#         Trace.ConstantTexture(0f0),
#     )
#     core = Trace.ShapeCore(Trace.Transformation(), true)
#     sphere = Trace.Sphere(core, 1f0, -1f0, 1f0, 360f0)
#     primitive = Trace.GeometricPrimitive(sphere, material)
#     bvh = Trace.BVHAccel([primitive])

#     lights = [Trace.PointLight(
#         Trace.Transformation(), Trace.RGBSpectrum(Float32(π)),
#     )]
#     scene = Trace.Scene(lights, bvh)
#     # Construct Film and Camera.
#     resolution = Point2f0(10f0, 10f0)
#     filter = Trace.LanczosSincFilter(Point2f0(4f0), 3f0)
#     scene_file = "test-output.png"
#     film = Trace.Film(
#         resolution, Trace.Bounds2(Point2f0(0f0), Point2f0(1f0)),
#         filter, 1f0, 1f0, scene_file,
#     )
#     screen = Trace.Bounds2(Point2f0(-1f0), Point2f0(1f0))
#     camera = Trace.PerspectiveCamera(
#         Trace.Transformation(), screen, 0f0, 1f0, 0f0, 10f0, 45f0, film,
#     )

#     sampler = Trace.UniformSampler(1)
#     integrator = Trace.WhittedIntegrator(camera, sampler, 1)
#     scene |> integrator

#     check_scene_average(scene_file, 1f0)
# end
