//
//  ViewController.m
//  warpExample
//
//  Created by Alessandro Dal Grande on 8/11/15.
//  Copyright (c) 2015 Nifty. All rights reserved.
//

#import <simd/simd.h>
#import "ViewController.h"

#define IMAGE_WIDTH 320
#define IMAGE_HEIGHT 240

@interface ViewController ()
{
  cv::Mat _image;
  
  // metal
  id<MTLDevice> _device;
  id<MTLTexture> _textureOriginal;
  id<MTLTexture> _textureCPUWarped;
  id<MTLBuffer> _verticesCoordsBuffer;
  id<MTLBuffer> _textureCoordsBuffer;
  id<MTLCommandEncoder> _renderCommandEncoder;
  id<MTLCommandQueue> _commandQueue;
  id<MTLLibrary> _library;
  id<MTLRenderPipelineState> _pipelineState;
  id<MTLDepthStencilState> _depthState;

}

@end

@implementation ViewController

@dynamic view;

- (void)loadView
{
  self.view = [[MetalView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  // load image
  NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"ace" ofType:@"jpg"];
  _image = cv::imread([path UTF8String]);
  cv::cvtColor(_image, _image, CV_BGR2GRAY);

  self.view.delegate = self;
  
  [self setupMetal];
  [self configureRenderer];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

#pragma mark - CPU warp

- (cv::Mat)getCPUWarp
{
  // _image contains the original image
  cv::Matx33d h(1.03140473, 0.0778113901, 0.000169219566,
                0.0342947133, 1.06025684, 0.000459250761,
                -0.0364957005, -38.3375587, 0.818259298);
  cv::Mat dest(_image.size(), _image.type());
  // h is transposed because OpenCV is col major and using backwarping because it is what is used on the GPU, so better for comparison
  cv::warpPerspective(_image, dest, h.t(), _image.size(), cv::WARP_INVERSE_MAP | cv::INTER_LINEAR);
  return dest;
}

#pragma mark - metal setup

- (void)setupMetal
{
  self.view.depthPixelFormat   = MTLPixelFormatInvalid;
  self.view.stencilPixelFormat = MTLPixelFormatInvalid;
  self.view.sampleCount        = 1;
  _device = MTLCreateSystemDefaultDevice();
  _commandQueue = [_device newCommandQueue];
  _library = [_device newDefaultLibrary];
}

- (void)configureRenderer
{
  if (![self preparePipelineState]) {
    NSLog(@">> ERROR: Failed creating a pipeline stencil state descriptor!");
    assert(0);
  }
  
  if (![self prepareBuffersAndTexturesWithOriginalImage:_image withCPUWarpedImage:[self getCPUWarp]]) {
    NSLog(@">> ERROR: Failed creating buffers!");
    assert(0);
  }
}

- (BOOL)preparePipelineState
{
  // get the vertex function from the library
  id <MTLFunction> vertexProgram = [_library newFunctionWithName:@"warpVertex"];
  
  if (!vertexProgram) {
    NSLog(@">> ERROR: Couldn't load vertex function from default library");
  }
  
  // get the fragment function from the library
  id <MTLFunction> fragmentProgram = [_library newFunctionWithName:@"warpFragment"];
  
  if (!fragmentProgram) {
    NSLog(@">> ERROR: Couldn't load fragment function from default library");
  }
  
  //  create a pipeline state for the quad
  MTLRenderPipelineDescriptor *quadPipelineStateDescriptor = [MTLRenderPipelineDescriptor new];
  
  if (!quadPipelineStateDescriptor) {
    NSLog(@">> ERROR: Failed creating a pipeline state descriptor!");
    return NO;
  }
  
  quadPipelineStateDescriptor.depthAttachmentPixelFormat      = MTLPixelFormatInvalid;
  quadPipelineStateDescriptor.stencilAttachmentPixelFormat    = MTLPixelFormatInvalid;
  quadPipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  
  quadPipelineStateDescriptor.sampleCount      = 1;
  quadPipelineStateDescriptor.vertexFunction   = vertexProgram;
  quadPipelineStateDescriptor.fragmentFunction = fragmentProgram;
  
  NSError *pError = nil;
  _pipelineState = [_device newRenderPipelineStateWithDescriptor:quadPipelineStateDescriptor error:&pError];
  
  if (!_pipelineState) {
    NSLog(@">> ERROR: Failed acquiring pipeline state descriptor: %@", pError);
    return NO;
  }
  
  return YES;
}

- (BOOL)prepareBuffersAndTexturesWithOriginalImage:(cv::Mat)originalImage withCPUWarpedImage:(cv::Mat)cpuWarpedImage
{
  int width = IMAGE_WIDTH, height = IMAGE_HEIGHT;
  
  // original image
  MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:width height:height mipmapped:NO];
  
  _textureOriginal = [_device newTextureWithDescriptor:textureDescriptor];
  
  if (!_textureOriginal) {
    NSLog(@"Could not prepare original image texture");
    return NO;
  }
  
  const void *pixels = originalImage.data;
  
  if (pixels != NULL) {
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    uint32_t rowBytes = width;
    [_textureOriginal replaceRegion:region mipmapLevel:0 withBytes:pixels bytesPerRow:rowBytes];
  }
  
  // CPU warped image
  _textureCPUWarped = [_device newTextureWithDescriptor:textureDescriptor];
  
  if (!_textureCPUWarped) {
    NSLog(@"Could not prepare CPU warped image texture");
    return NO;
  }
  
  pixels = cpuWarpedImage.data;
  
  if (pixels != NULL) {
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    uint32_t rowBytes = width;
    [_textureCPUWarped replaceRegion:region mipmapLevel:0 withBytes:pixels bytesPerRow:rowBytes];
  }
  
  // vertices coordinates buffer
  const simd::float4 kQuadVertices[4] =
  {
    { -1.0f,  -1.0f, 0.0f, 1.0f },
    { +1.0f,  -1.0f, 0.0f, 1.0f },
    { -1.0f,  +1.0f, 0.0f, 1.0f },
    { +1.0f,  +1.0f, 0.0f, 1.0f },
  };
  
  _verticesCoordsBuffer = [_device newBufferWithBytes:kQuadVertices length:4 * sizeof(simd::float4) options:MTLResourceOptionCPUCacheModeDefault];
  
  if (!_verticesCoordsBuffer) {
    NSLog(@">> ERROR: Failed creating a vertex buffer for a quad!");
    return NO;
  }
  
  // texture coordinates buffer
  const simd::float3 textureCoords[4] =
  {
    { 0,  IMAGE_HEIGHT, 1.0f },
    { IMAGE_WIDTH, IMAGE_HEIGHT, 1.0f },
    { 0, 0, 1.0f },
    { IMAGE_WIDTH, 0, 1.0f },
  };
  
  _textureCoordsBuffer = [_device newBufferWithBytes:textureCoords length:4 * sizeof(simd::float3) options:MTLResourceOptionCPUCacheModeDefault];
  
  if (!_textureCoordsBuffer) {
    NSLog(@">> ERROR: Failed creating a 2d texture coordinate buffer!");
    return NO;
  }
  
  return YES;
}

- (void)encodeForWarp:(id<MTLRenderCommandEncoder>)renderEncoder
{
  [renderEncoder pushDebugGroup:@"warp"];
  
  [renderEncoder setRenderPipelineState:_pipelineState];
  
  [renderEncoder setVertexBuffer:_verticesCoordsBuffer offset:0 atIndex:0];
  [renderEncoder setVertexBuffer:_textureCoordsBuffer offset:0 atIndex:1];
  
  [renderEncoder setFragmentTexture:_textureOriginal atIndex:0];
  [renderEncoder setFragmentTexture:_textureCPUWarped atIndex:1];
  
  [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
  [renderEncoder endEncoding];
  
  [renderEncoder popDebugGroup];
}

#pragma mark - MetalViewDelegate

- (void)update
{

}

- (void)render
{
  id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
  
  // create a render command encoder so we can render into something
  MTLRenderPassDescriptor *renderPassDescriptor = self.view.renderPassDescriptor;
  
  if (renderPassDescriptor) {
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    // render textured quad
    [self encodeForWarp:renderEncoder];
    
    [commandBuffer addCompletedHandler:^(id <MTLCommandBuffer> cmdb) {
      if (cmdb.error) {
        NSLog(@"%@", cmdb.error);
      }
    }];
    
    // present and commit the command buffer
    [commandBuffer presentDrawable:self.view.currentDrawable];
    [commandBuffer commit];
  }
}


@end
