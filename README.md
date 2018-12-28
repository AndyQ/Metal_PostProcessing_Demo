# Metal_PostProcessing_Demo
A simple demo macOS project which uses Metal to render a simple fireworks scene to an offscreen texture, and then uses 
MetalPerformanceShaders to post-process the offscreen texture and display the new texture.

A MPSImageAreaMax filter is used initially to make the particles larger, and then a MPSImageGaussianBlur is applied to slightly
blur the image.

In addition, a blitEncoder is used to copy the offscreen texture to the drawable texture.

This could also be done using a Compute shader and again this is shown (but commented out).

Note - this is really for my reference but may well be useful for someone else looking at applying post process effects.

The fireworks are based on Karl Pickett's Fireworks Graphics Demo (https://github.com/kjpgit/fireworks) - updated for Swift 4.2 and changes in Metal.
