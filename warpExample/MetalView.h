//
//  MetalView.h
//  warpExample
//
//  Created by Alessandro Dal Grande on 8/11/15.
//  Copyright (c) 2015 Nifty. All rights reserved.
//

#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>

@protocol MetalViewDelegate;


@interface MetalView : UIView

@property (nonatomic, weak) IBOutlet id <MetalViewDelegate> delegate;

// view has a handle to the metal device when created
@property (nonatomic, readonly) id <MTLDevice> device;

// the current drawable created within the view's CAMetalLayer
@property (nonatomic, readonly) id <CAMetalDrawable> currentDrawable;

// The current framebuffer can be read by delegate during -[MetalViewDelegate render:]
// This call may block until the framebuffer is available.
@property (nonatomic, readonly) MTLRenderPassDescriptor *renderPassDescriptor;

// set these pixel formats to have the main drawable framebuffer get created with depth and/or stencil attachments
@property (nonatomic) MTLPixelFormat depthPixelFormat;
@property (nonatomic) MTLPixelFormat stencilPixelFormat;
@property (nonatomic) NSUInteger     sampleCount;

// view controller will be call off the main thread
- (void)display;

// release any color/depth/stencil resources. view controller will call when paused.
- (void)releaseTextures;

@end



// rendering delegate (App must implement a rendering delegate that responds to these messages
@protocol MetalViewDelegate <NSObject>

@required

- (void)update;

// delegate should perform all rendering here
- (void)render;

@end
