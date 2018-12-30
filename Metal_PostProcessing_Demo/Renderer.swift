//
//  Renderer.swift
//  MetalSample
//
//  Created by Andy Qua on 28/06/2018.
//  Copyright © 2018 Andy Qua. All rights reserved.
//

// Our platform independent renderer class

import GameplayKit
import Metal
import MetalKit
import MetalPerformanceShaders
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size & ~0xFF) + 0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}


func randomInt( ) -> Int {
    return GKRandomSource.sharedRandom().nextInt()
}

func randomInt( upperBound: Int ) -> Int {
    return GKRandomSource.sharedRandom().nextInt(upperBound:upperBound)
}
func random_unit_float() -> Float {
    return GKRandomSource.sharedRandom().nextUniform()
}


extension float4x4 {
    init(perspectiveWithAspect aspect: Float, fovy: Float, near: Float, far: Float) {
        let yScale = 1 / tan(fovy * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2 * far * near / zRange
        
        // List of the matrix' columns
        let vectorP: float4 = [xScale,      0,       0,  0]
        let vectorQ: float4 = [     0, yScale,       0,  0]
        let vectorR: float4 = [     0,      0,  zScale, -1]
        let vectorS: float4 = [     0,      0, wzScale,  0]
        self.init(vectorP, vectorQ, vectorR, vectorS)
    }
    
    static func makeLookAt(eye: float3, lookAt: float3, up:float3) -> float4x4 {
        let n = normalize(eye + (-lookAt))
        let u = normalize(cross(up, n))
        let v = cross(n, u)
        
        let m : float4x4 = float4x4([ u.x, v.x, n.x, 0.0],
                                    [u.y, v.y, n.y, 0.0],
                                    [u.z, v.z, n.z, 0.0],
                                    [dot(-u, eye), dot(-v, eye), dot(-n, eye), 1.0] )
        
        return m
    }
    
}

class Renderer: NSObject, MTKViewDelegate {
    
    // Metal stuff
    public let device: MTLDevice
    var isDilateEnabled = false
    var isBlurEnabled = false

    let metalLayer : CAMetalLayer
    
    var commandQueue: MTLCommandQueue!
    var dynamicUniformBuffer: MTLBuffer!
    var depthState: MTLDepthStencilState!
    var colorMap: MTLTexture!
    var depthTexture: MTLTexture!
    
    var drawableSize = CGSize()
    
    var projectionMatrix = float4x4()
    
    var sharedBufferProvider : BufferProvider!
    var sharedUniformBuffer : MTLBuffer!
    
    var frameDuration : Float = 1.0 / 60.0;
    
    var camera : Camera
    
    let fireworks : FireworkScene
    
    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.metalLayer = metalKitView.layer as! CAMetalLayer
        self.metalLayer.pixelFormat = MTLPixelFormat.bgra8Unorm;
        //self.metalLayer.framebufferOnly = false // <-- THIS
        metalKitView.framebufferOnly = false

        self.drawableSize = metalKitView.drawableSize
        
        camera = Camera(pos: [0, 5, -10], lookAt: [0, 5, 10])
        
        fireworks = FireworkScene(device:device)

        super.init()
        
        buildDescriptors( metalKitView: metalKitView)
        
        buildSharedUniformBuffers()
    }
    
    
    func buildDescriptors( metalKitView: MTKView ) {
        guard let queue = self.device.makeCommandQueue() else { return }
        self.commandQueue = queue
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.isDepthWriteEnabled = true
        depthDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!
    }
    
    
    func buildSharedUniformBuffers() {
        
        sharedBufferProvider = BufferProvider(device: device, inflightBuffersCount: 3, sizeOfUniformsBuffer: MemoryLayout<Uniforms>.size)
    }
    
    func createDepthTexture(  ) {
        let drawableSize = metalLayer.drawableSize
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.depth32Float, width: Int(drawableSize.width), height: Int(drawableSize.height), mipmapped: false)
        descriptor.usage = MTLTextureUsage.renderTarget
        descriptor.storageMode = .private
        
        self.depthTexture = self.device.makeTexture(descriptor: descriptor)
        self.depthTexture.label = "Depth Texture"
    }
    
    
    func updateSharedUniforms( )
    {
        let aspect = Float(metalLayer.drawableSize.width / metalLayer.drawableSize.height)
        let fov :Float = (aspect > 1) ? (Float.pi / 4) : (Float.pi / 3); //.pi_2/5
        
        projectionMatrix = float4x4(perspectiveWithAspect: aspect, fovy: fov, near: 0.1, far: 2000)
        
        let modelViewMatrix = camera.look()
        let modelViewProjectionMatrix = projectionMatrix * modelViewMatrix
        
        var uniforms = Uniforms()
        uniforms.viewProjectionMatrix = modelViewProjectionMatrix
        
        self.sharedUniformBuffer = sharedBufferProvider.nextBuffer( )
        memcpy(self.sharedUniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)
    }
    
    func updateUniforms( )
    {
        updateSharedUniforms( )
    }
    
    func createRenderPassWithColorAttachmentTexture( texture : MTLTexture ) -> MTLRenderPassDescriptor {
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture;
        renderPass.colorAttachments[0].loadAction = MTLLoadAction.clear;
        renderPass.colorAttachments[0].storeAction = MTLStoreAction.store;
        
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        
        renderPass.depthAttachment.texture = self.depthTexture;
        renderPass.depthAttachment.loadAction = MTLLoadAction.clear;
        renderPass.depthAttachment.storeAction = MTLStoreAction.store;
        renderPass.depthAttachment.clearDepth = 1.0;
        
        return renderPass;
    }
    
    
    func draw(in view: MTKView) {
        fireworks.prepareToDraw()

        // Prepare
        fireworks.update()

        updateUniforms()
        
        if self.depthTexture == nil || (self.depthTexture.width != Int(metalLayer.drawableSize.width) ||
            self.depthTexture.height != Int(metalLayer.drawableSize.height)) {
            
            createDepthTexture()
        }
        
        guard let drawable = metalLayer.nextDrawable() else { return }

        let viewWidth = Int(drawable.texture.width)
        let viewHeight = Int(drawable.texture.height)

        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: viewWidth, height: viewHeight, mipmapped: false)
        textureDescriptor.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderWrite, MTLTextureUsage.shaderRead]
        textureDescriptor.storageMode = .private

        guard var texture = device.makeTexture(descriptor: textureDescriptor ) else { print( "Failed to make texture" ) ; return}

        let commandBuffer = self.commandQueue.makeCommandBuffer()!
        commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
            self?.fireworks.finishedDrawing()
        }

        // First pass - Use texture create above (render offscreen)
        let renderPass = createRenderPassWithColorAttachmentTexture( texture: texture )
        

        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!
        commandEncoder.setFrontFacing(MTLWinding.counterClockwise)
        
        commandEncoder.setCullMode(MTLCullMode.none)
        
        commandEncoder.setDepthStencilState(self.depthState)
        
        // Draw
        fireworks.draw(renderEncoder: commandEncoder, sharedUniformsBuffer: sharedUniformBuffer)

        commandEncoder.endEncoding()

        if isDilateEnabled {
            // Dilate the buffer (makes the particles look bigger)
            let dilate = MPSImageAreaMax(device: device, kernelWidth: 3, kernelHeight: 3)
            dilate.encode(commandBuffer: commandBuffer, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
        }
        
        if isBlurEnabled {
            // Blur the buffer
            let kernel = MPSImageGaussianBlur(device: device, sigma: 2.5)
            kernel.encode(commandBuffer: commandBuffer, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
        }

        // Copy the texture to the drawable texture
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        let size = MTLSize(width: viewWidth, height: viewHeight, depth: 1)
        blitEncoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOriginMake(0, 0, 0), sourceSize: size,
                     
                     to: drawable.texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOriginMake(0, 0, 0))
        
        blitEncoder.endEncoding()

        
/* Could do texture copy using a compute shader
   but blitEncoder is probably more efficient
         let library = device.makeDefaultLibrary()!
         let computeProgram = library.makeFunction(name: "computeShader")!
         
         let computePipelineState : MTLComputePipelineState
         do {
         computePipelineState = try
         device.makeComputePipelineState(function: computeProgram)
         } catch {
         print("could not prepare compute pipeline state")
         return
         }
         
        let compute = commandBuffer.makeComputeCommandEncoder()!
        compute.setComputePipelineState(computePipelineState)
        // input one -- primary texture
        compute.setTexture(texture, index: 0)
        // input two -- mask texture
        // output texture
        compute.setTexture(drawable.texture, index: 1)
        var t2 = drawable.texture
        
        // set up an 8x8 group of threads
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        
        // define the number of such groups needed to process the textures
        let numGroups = MTLSize(
            width: viewWidth/threadGroupSize.width+1,
            height: viewHeight/threadGroupSize.height+1,
            depth: 1)
        
        compute.dispatchThreadgroups(numGroups,
                                     threadsPerThreadgroup: threadGroupSize)
        
        compute.endEncoding()
*/
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        //let aspect = Float(size.width) / Float(size.height)
        //projectionMatrix = matrix_perspective_projection(aspect: aspect, fovy: radians_from_degrees(65), near: 0.1, far: 100.0)
    }
}
