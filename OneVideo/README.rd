#OpenGLVideoMerge

1. CVOpenGLESTextureCacheCreate http://stackoverflow.com/questions/9544293/where-is-the-official-documentation-for-cvopenglestexture-method-types
2.             http://www.liquidsketch.com/recording-from-the-ipad-screen/
3.             http://stackoverflow.com/questions/10455329/opengl-es-2d-rendering-into-image/10455622
4.             http://stackoverflow.com/questions/16716085/copy-a-texture-to-pixelbuffer-cvpixelbufferref?lq=1
5.             http://stackoverflow.com/questions/17883519/ios-generating-movie-with-opengl-texturecache-does-not-show-frames-correctly



6. CVOpenGLESTextureCacheCreateTextureFromImage vs glTexImage2D http://stackoverflow.com/questions/13848743/cvopenglestexturecachecreatetexturefromimage-vs-glteximage2d
http://stackoverflow.com/questions/12813442/cvopenglestexturecache-vs-gltexsubimage2d-on-ios
7. 原理： http://stackoverflow.com/questions/10646657/hardware-accelerated-h-264-decoding-to-texture-overlay-or-similar-in-ios

8. http://stackoverflow.com/questions/4237538/is-it-possible-using-video-as-texture-for-gl-in-ios

9. Updating a texture in OpenGL with glTexImage2D  http://stackoverflow.com/questions/9863969/updating-a-texture-in-opengl-with-glteximage2d


CODE:
video snake from wwdc 2012: https://github.com/david-robles/WWDC-2012/tree/0a1705ff84b1ea1467dae31596e3c5ccb4ac3ecb/520%20-%20What's%20New%20in%20Camera%20Capture/VideoSnake

https://github.com/bdudney/Experiments/blob/81df1f76bd052324c3fba0fa543a0cc5aac3b0ca/TweakedSamples/GLCameraRipple/GLCameraRipple/RippleViewController.m



10. 各种buffers中得关系 比如vertex, index 和 texture(pixmap) Compare OpenGL ES 2.0 buffers, uniforms, and vertex attributes to Direct3D http://msdn.microsoft.com/en-us/library/windows/apps/dn166871.aspx  http://stackoverflow.com/questions/8757212/opengles-2-0-separate-buffers-for-vertices-colors-and-texture-coordinates


11. handle CMSampleBuffer的处理方式： 第一种使用core graphic 慢，第二种使用opengl es The most efficient way to modify CMSampleBuffer contents http://stackoverflow.com/questions/4662789/the-most-efficient-way-to-modify-cmsamplebuffer-contents  这个链接中提到了 如何

     1. 创建一个在后台处理的OpenGL framebuffer
     2. 将CMSampleBuffer转换为texture, 然后发送到OpenGL中， OpenGL处理这个texture 比如通过shader
     3. 将数据聪OpenGL的渲染中读取出来， 转换为图片


12. OpenGL Texture tutorial : http://open.gl/textures



https://developer.apple.com/library/mac/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/05_Export.html#//apple_ref/doc/uid/TP40010188-CH9-SW17

https://developer.apple.com/library/mac/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/05_Export.html


### PERformance:

#### TWO VIDEO CHROMA KEY:
iPod5:
 GPU: 4.68s
 Custom: 3.87s

iPhone4:
 GPU: 44.79s
 Custom: 11.90s