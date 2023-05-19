I tried to make a biome map.

This algorithm works by choosing biomes at random and then using a simulation to make sure they are placed realistically(hot biomes are far from cold biomes, ocean/land biomes are clustered together).

This turned out to not work that well, but it makes some interesting images and the simulation process looks almost organic:

https://github.com/IntegratedQuantum/VoronoiBiomeArt/assets/43880493/40b0f828-403c-4044-88bb-0e3e90fb6140

# How to run

1. [Install zig](https://ziglang.org/download/) and hope for the best. I have tested this with zig version `0.11.0-dev.3132+465272921` You may need to some changes when using a newer/older version of zig.

2. Run it in release for your own sanity
```
zig build run -Doptimize=ReleaseFast
```

3. Watch how the folder gets flooded with images. This is only for making the video and in itself is pretty slow. You can disable this behavior [here](https://github.com/IntegratedQuantum/VoronoiBiomeArt/blob/9a656172945eb0776c254671e01e72cfe7f9f701/src/RecursiveAttempt.zig#L386 ).

4. You can now turn the images into a video using ffmpeg:
```
ffmpeg -framerate 30 -i 'testBefore%d.png' -c:v libx264 -pix_fmt yuv420p out.mp4
```
