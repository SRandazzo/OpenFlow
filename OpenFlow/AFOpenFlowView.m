/**
 * Copyright (c) 2009 Alex Fajkowski, Apparent Logic LLC
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 * 
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */
#import "AFOpenFlowView.h"
#import "AFUIImageReflection.h"
#import "SBNotifyingWindow.h"
#import "AFOpenFlowGeometry.h"

@interface AFOpenFlowView (hidden)

- (void)setUpInitialState;
- (AFItemView *)coverForIndex:(int)coverIndex;
- (void)updateCoverImage:(AFItemView *)aCover;
- (AFItemView *)dequeueReusableCover;
- (void)layoutCovers:(int)selected fromCover:(int)lowerBound toCover:(int)upperBound;
- (void)layoutCover:(AFItemView *)aCover selectedCover:(int)selectedIndex animated:(Boolean)animated;
- (AFItemView *)findCoverOnscreen:(CALayer *)targetLayer;

@end

@implementation AFOpenFlowView (hidden)

const static CGFloat kReflectionFraction = 0.85;

- (SBNotifyingWindow *)appWindow
{
    id appDel = [[UIApplication sharedApplication] delegate];
    if([appDel respondsToSelector:@selector(window)])
    {
        UIWindow *window = [appDel performSelector:@selector(window)];
        if([window isMemberOfClass:[SBNotifyingWindow class]])
        {
            return (SBNotifyingWindow *)window;
        }
    }
    return nil;
}

- (void)setUpInitialState {
    [[self appWindow] addObjectInterestedInTouches:self];
    
    [self setBackgroundColor:[UIColor clearColor]];
    // Set up the default image for the coverflow.
	self.defaultImage = [self.dataSource defaultImage];
    
	// Create data holders for onscreen & offscreen covers & UIImage objects.
	coverImages = [[NSMutableDictionary alloc] init];
	coverImageHeights = [[NSMutableDictionary alloc] init];
    coverImageCaptions = [[NSMutableDictionary alloc] init];
	offscreenCovers = [[NSMutableSet alloc] init];
	onscreenCovers = [[NSMutableDictionary alloc] init];
    
	// Initialize the visible and selected cover range.
	lowerVisibleCover = upperVisibleCover = -1;
	selectedCoverView = nil;
    
	// Set up the cover's left & right transforms.
    leftTransform = CATransform3DTranslate(CATransform3DIdentity, 0, 0, SIDE_COVER_ZPOSITION / 2.0);
    CGFloat sideCoverAngle = [AFOpenFlowGeometry sideCoverAngle];
	leftTransform = CATransform3DRotate(leftTransform, sideCoverAngle, 0.0f, 1.0f, 0.0f);
    
    rightTransform = CATransform3DTranslate(CATransform3DIdentity, 0, 0, SIDE_COVER_ZPOSITION / 2.0);
	rightTransform = CATransform3DRotate(rightTransform, sideCoverAngle, 0.0f, -1.0f, 0.0f);
    
    self.scrollEnabled = YES;
    self.userInteractionEnabled = YES;
    self.showsVerticalScrollIndicator = NO;
    self.showsHorizontalScrollIndicator = NO;
    self.bounces = NO;
    
    //  UIScrollViewDecelerationRateNormal = 0.998
    //  UIScrollViewDecelerationRateFast = 0.990
    self.decelerationRate = .98;
    [super setDelegate:self];
    
	// Set some perspective
	CATransform3D sublayerTransform = CATransform3DIdentity;
	sublayerTransform.m34 = -0.01;
	[self.layer setSublayerTransform:sublayerTransform];
    
    // Initialize Cover Caption
    selectedCoverCaption = [[UITextView alloc] init];
    selectedCoverCaption.textColor = [UIColor whiteColor];
    selectedCoverCaption.textAlignment = UITextAlignmentCenter;
    selectedCoverCaption.frame = CGRectMake(0, 0, CAPTION_WIDTH, CAPTION_HEIGHT);
    selectedCoverCaption.backgroundColor = nil;
    selectedCoverCaption.userInteractionEnabled = NO;
    selectedCoverCaption.font = [UIFont systemFontOfSize:CAPTION_FONTSIZE];
    
    [self addSubview:selectedCoverCaption];
    
    maxImageSize = CGSizeZero;
}

- (AFItemView *)coverForIndex:(int)coverIndex {
	AFItemView *coverView = [self dequeueReusableCover];
	if (!coverView)
		coverView = [[[AFItemView alloc] initWithFrame:CGRectZero] autorelease];
    if (!CGSizeEqualToSize(maxImageSize, CGSizeZero)) {
        [coverView setMaxCoverSize:maxImageSize];
    }
	
	coverView.number = coverIndex;
    
	return coverView;
}

- (void)updateCoverImage:(AFItemView *)aCover {
	NSNumber *coverNumber = [NSNumber numberWithInt:aCover.number];
	UIImage *coverImage = (UIImage *)[coverImages objectForKey:coverNumber];
	if (coverImage) {
		NSNumber *coverImageHeightNumber = (NSNumber *)[coverImageHeights objectForKey:coverNumber];
		if (coverImageHeightNumber)
			[aCover setImage:coverImage originalImageHeight:[coverImageHeightNumber floatValue] reflectionFraction:kReflectionFraction];
	} else {
		[aCover setImage:defaultImage originalImageHeight:defaultImageHeight reflectionFraction:kReflectionFraction];
		[self.dataSource openFlowView:self requestImageForIndex:aCover.number];
	}
}

- (AFItemView *)dequeueReusableCover {
	AFItemView *aCover = [offscreenCovers anyObject];
	if (aCover) {
		[[aCover retain] autorelease];
		[offscreenCovers removeObject:aCover];
	}
	return aCover;
}

- (void)layoutCover:(AFItemView *)aCover selectedCover:(int)selectedIndex animated:(Boolean)animated  {
	int coverNumber = aCover.number;
	CATransform3D newTransform;
	CGFloat newZPosition = [AFOpenFlowGeometry sideCoverZPosition]/2;
	CGPoint newPosition;
    
	newPosition.x = halfScreenWidth + aCover.horizontalPosition;
    //Bottom of the cover should always in the same place
	newPosition.y = 265;
    if (coverNumber < selectedIndex) {
		newPosition.x -= [AFOpenFlowGeometry centerCoverOffset];
		newTransform = leftTransform;
	} else if (coverNumber > selectedIndex) {
		newPosition.x += [AFOpenFlowGeometry centerCoverOffset];
		newTransform = rightTransform;
	} else {
		newZPosition = 0;
		newTransform = CATransform3DIdentity;
	}
	
	if (animated) {
		[UIView beginAnimations:nil context:nil];
        [UIView setAnimationDuration:0.3];
		[UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
		[UIView setAnimationBeginsFromCurrentState:YES];
	}
	
	aCover.layer.transform = newTransform;
	//aCover.layer.zPosition = newZPosition;
	
    if([[[UIDevice currentDevice] systemVersion] floatValue] >= 5.0 && animated) {
    	
        CABasicAnimation *zPositionAnimation = [CABasicAnimation animationWithKeyPath:@"zPosition"];
    	
        [zPositionAnimation setToValue:[NSNumber numberWithFloat:newZPosition]];
    	
         [zPositionAnimation setDuration:.3];
     	
         [zPositionAnimation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
     	
         [zPositionAnimation setRemovedOnCompletion:NO];
      	
          [zPositionAnimation setFillMode:kCAFillModeForwards];
      	
          [aCover.layer addAnimation:zPositionAnimation forKey:nil];
       	
         } else {
       	
           aCover.layer.zPosition = newZPosition;
       	
    }
    
    aCover.layer.position = newPosition;
    
	if (animated) {
		[UIView commitAnimations];
	}
}

- (void)layoutCovers:(int)selected fromCover:(int)lowerBound toCover:(int)upperBound {
    //    NSLog(@"[%@ %s]", self, _cmd);
	AFItemView *cover;
	NSNumber *coverNumber;
	for (int i = lowerBound; i <= upperBound; i++) {
		coverNumber = [[NSNumber alloc] initWithInt:i];
		cover = (AFItemView *)[onscreenCovers objectForKey:coverNumber];
		[coverNumber release];
		[self layoutCover:cover selectedCover:selected animated:YES];
	}
}

- (AFItemView *)findCoverOnscreen:(CALayer *)targetLayer {
	// See if this layer is one of our covers.
	NSEnumerator *coverEnumerator = [onscreenCovers objectEnumerator];
	AFItemView *aCover = nil;
	while (aCover = (AFItemView *)[coverEnumerator nextObject])
		if ([[aCover.imageView layer] isEqual:targetLayer])
			break;
	
	return aCover;
}
@end


@implementation AFOpenFlowView
@synthesize dataSource, viewDelegate, numberOfImages, defaultImage, selectedCoverCaption;

#define COVER_BUFFER 6

- (void)awakeFromNib {
	[self setUpInitialState];
}

- (id)initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame]) {
		[self setUpInitialState];
	}
	
	return self;
}

- (void)dealloc {
    [[self appWindow] removeObjectWithInterest:self];
	[defaultImage release];
	
	[coverImages release];
	[coverImageHeights release];
    [coverImageCaptions release];
	[offscreenCovers removeAllObjects];
	[offscreenCovers release];
	
	[onscreenCovers removeAllObjects];
	[onscreenCovers release];
	
	[super dealloc];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    //    NSLog(@"[%@ %s]", self, _cmd);
    halfScreenWidth = self.bounds.size.width / 2;
    halfScreenHeight = self.bounds.size.height / 2;
    
    int lowerBound = MAX(-1, selectedCoverView.number - COVER_BUFFER);
    int upperBound = MIN(self.numberOfImages - 1, selectedCoverView.number + COVER_BUFFER);
    
    [self layoutCovers:selectedCoverView.number fromCover:lowerBound toCover:upperBound];
    [self setNumberOfImages:numberOfImages]; // resets view bounds and stuff
    CGPoint contentOffset = [self contentOffset];
    int targetCover = (int) roundf(contentOffset.x / [AFOpenFlowGeometry coverSpacing]);
    if (targetCover != selectedCoverView.number) {
        if (targetCover < 0)
            [self setSelectedCover:0];
        else if (targetCover >= self.numberOfImages)
            [self setSelectedCover:self.numberOfImages - 1];
        else
            [self setSelectedCover:targetCover];
    }
        
    CGFloat horizOrigin = contentOffset.x + halfScreenWidth - CAPTION_WIDTH / 2;
    CGFloat vertOrigin = selectedCoverView.frame.origin.y + selectedCoverView.frame.size.height / 2.0 + CAPTION_OFFSET+10;
    selectedCoverCaption.frame = CGRectMake(horizOrigin, vertOrigin, CAPTION_WIDTH, CAPTION_HEIGHT);
    selectedCoverCaption.text = [NSString stringWithFormat:@"%@", [coverImageCaptions objectForKey:[NSNumber numberWithInt:targetCover]]];
    // put it on top
    [self addSubview:selectedCoverCaption];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    // no scrolling below where the caption is
    return point.y < selectedCoverView.frame.origin.y + selectedCoverView.frame.size.width;
}

#pragma mark UIScrollViewDelegate
//- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;                              
//// called on start of dragging (may require some time and or distance to move)
//{
//    //NSLog(@"%s %f", _cmd, CACurrentMediaTime());
//}

- (void)centerCoverHelperAnimated
{
    [self centerOnSelectedCover:YES];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate; // called on finger up if user dragged. decelerate is true if it will continue moving afterwards
{
    //NSLog(@"%s %f", _cmd, CACurrentMediaTime());
    if(!decelerate)
    {
        [self centerOnSelectedCover:YES];
    }
}

/*
 - (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;      // called when scroll view grinds to a halt
 {
 NSLog(@"%s %f", _cmd, CACurrentMediaTime());
 
 }
 - (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView;   // called on finger up as we are moving
 {
 //[self centerOnSelectedCover:YES];
 NSLog(@"%s %f", _cmd, CACurrentMediaTime());
 //[self performSelector:@selector(centerCoverHelper) withObject:nil afterDelay:0.0];
 }
 
 - (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView; // called when setContentOffset/scrollRectVisible:animated: finishes. not called if not animating
 {
 //[self centerOnSelectedCover:YES];
 NSLog(@"%s %f", _cmd, CACurrentMediaTime());
 }
 */

#pragma mark SBNotifyingWindowTouches

-(void)interestingEvent:(UIEvent *)event;
{
    //NSLog(@"%@ %s %@", self, _cmd, event);
    
    NSSet *touches = [event allTouches];
    UITouch *touch = [touches anyObject];
    UITouchPhase phase = [touch phase];
    
    if (phase == UITouchPhaseBegan) {
        [self touchesBegan:touches withEvent:event];
    }
    if (phase == UITouchPhaseEnded)
    {
        [self touchesEnded:touches withEvent:event];
    }
    if (phase == UITouchPhaseCancelled) {
        [self touchesCancelled:touches withEvent:event];
    }
    if (phase == UITouchPhaseMoved) {
        [self touchesMoved:touches withEvent:event];
    }
}

#pragma mark UIScrollView

//-(void)setContentInset:(UIEdgeInsets)inset
//{
//    NSLog(@"[%@ %s%@]", self, _cmd, NSStringFromUIEdgeInsets(inset));
//    
//    [super setContentInset:inset];
//}

//-(void)setContentSize:(CGSize)contentSize
//{
//    NSLog(@"[%@ %s%@]", self, _cmd, NSStringFromCGSize(contentSize));
//    [super setContentSize:contentSize];
//}
//- (void)setContentOffset:(CGPoint)contentOffset
//{
//    NSLog(@"[%@ %s%@]", self, _cmd, NSStringFromCGPoint(contentOffset));
//    [super setContentOffset:contentOffset];
//}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated;
{
    //    NSLog(@"contentOffset = %@ animated:%@", NSStringFromCGPoint(contentOffset), (animated) ? @"YES" : @"NO");
    [super setContentOffset:contentOffset animated:animated];
    if(!animated)
    {
        [self centerOnSelectedCover:NO];
    }
}

- (void)setNumberOfImages:(int)newNumberOfImages {
	numberOfImages = newNumberOfImages;
	self.contentSize = CGSizeMake((newNumberOfImages-1)* [AFOpenFlowGeometry coverSpacing] + self.bounds.size.width, self.bounds.size.height);
    
	int lowerBound = MAX(0, selectedCoverView.number - COVER_BUFFER);
	int upperBound = MIN(self.numberOfImages - 1, selectedCoverView.number + COVER_BUFFER);
	
	if (selectedCoverView)
		[self layoutCovers:selectedCoverView.number fromCover:lowerBound toCover:upperBound];
	else
		[self setSelectedCover:0];
}

- (void)setDefaultImage:(UIImage *)newDefaultImage {
	[defaultImage release];
	defaultImageHeight = newDefaultImage.size.height;
	defaultImage = [[newDefaultImage addImageReflection:kReflectionFraction] retain];
}

- (void)setImage:(UIImage *)image forIndex:(int)index {
    [self setImage:image forIndex:index captionTitle:nil];
}

- (void)setImage:(UIImage *)image forIndex:(int)index captionTitle:(NSString*)captionTitle {
	// Create a reflection for this image.
	UIImage *imageWithReflection = [image addImageReflection:kReflectionFraction];
	NSNumber *coverNumber = [NSNumber numberWithInt:index];
	[coverImages setObject:imageWithReflection forKey:coverNumber];
	[coverImageHeights setObject:[NSNumber numberWithFloat:image.size.height] forKey:coverNumber];
    if (captionTitle == nil) {
        captionTitle = [coverNumber description];
    }
    [coverImageCaptions setObject:captionTitle forKey:coverNumber];
	
	// If this cover is onscreen, set its image and call layoutCover.
	AFItemView *aCover = (AFItemView *)[onscreenCovers objectForKey:[NSNumber numberWithInt:index]];
	if (aCover) {
		[aCover setImage:imageWithReflection originalImageHeight:image.size.height reflectionFraction:kReflectionFraction];
		[self layoutCover:aCover selectedCover:selectedCoverView.number animated:NO];
	}
}

- (void)setMaxSizeForCoverFlowImages:(CGSize)maxSize {
    //Set the max size for all AFItemViews.
    maxImageSize = maxSize;
    for (AFItemView *aCover in onscreenCovers) {
        [self layoutCover:aCover selectedCover:selectedCoverView.number animated:NO];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if ([touch tapCount] == 1) {
        // Which cover did the user tap?
        CGPoint targetPoint = [[touches anyObject] locationInView:[self appWindow]];
		CALayer *targetLayer = (CALayer *)[self.layer hitTest:targetPoint];
		AFItemView *targetCover = [self findCoverOnscreen:targetLayer];
        
        if ([self.viewDelegate respondsToSelector:@selector(openFlowView:didTapItemView:)]) {
            [self.viewDelegate openFlowView:self didTapItemView:targetCover];
        }
        
		if (targetCover && (targetCover.number != selectedCoverView.number))
        {
            CGPoint selectedOffset = CGPointMake([AFOpenFlowGeometry coverSpacing] * targetCover.number, 0);
            [self setContentOffset:selectedOffset animated:YES];
        }
    }
    if ([touch tapCount] == 2) 
    {
        // Which cover did the user double tap?
        CGPoint targetPoint = [[touches anyObject] locationInView:[self appWindow]];
        CALayer *targetLayer = (CALayer *)[self.layer hitTest:targetPoint];
        AFItemView *targetCover = [self findCoverOnscreen:targetLayer];
        NSLog(@"Double tapped %@", targetCover);
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [self touchesEnded:touches withEvent:event];
}

- (void)centerOnSelectedCover:(BOOL)animated {
	CGPoint selectedOffset = CGPointMake([AFOpenFlowGeometry coverSpacing] * selectedCoverView.number, 0);
	[self setContentOffset:selectedOffset animated:animated];
}

-(void)notifyCoverSelection
{
    // And send the delegate the newly selected cover message.
    if ([self.viewDelegate respondsToSelector:@selector(openFlowView:selectionDidChange:)])
        [self.viewDelegate openFlowView:self selectionDidChange:selectedCoverView.number];
}

- (void)setSelectedCover:(int)newSelectedCover {
	if (selectedCoverView && (newSelectedCover == selectedCoverView.number))
		return;
	
	AFItemView *cover;
	int newLowerBound = MAX(0, newSelectedCover - COVER_BUFFER);
	int newUpperBound = MIN(self.numberOfImages - 1, newSelectedCover + COVER_BUFFER);
	if (!selectedCoverView) {
		// Allocate and display covers from newLower to newUpper bounds.
		for (int i=newLowerBound; i <= newUpperBound; i++) {
			cover = [self coverForIndex:i];
			[onscreenCovers setObject:cover forKey:[NSNumber numberWithInt:i]];
			[self updateCoverImage:cover];
			[self addSubview:cover];
			[self layoutCover:cover selectedCover:newSelectedCover animated:NO];
		}
		
		lowerVisibleCover = newLowerBound;
		upperVisibleCover = newUpperBound;
		selectedCoverView = (AFItemView *)[onscreenCovers objectForKey:[NSNumber numberWithInt:newSelectedCover]];
		[self notifyCoverSelection];
		return;
	}
	
	// Check to see if the new & current ranges overlap.
	if ((newLowerBound > upperVisibleCover) || (newUpperBound < lowerVisibleCover)) {
		// They do not overlap at all.
		// This does not animate--assuming it's programmatically set from view controller.
		// Recycle all onscreen covers.
		AFItemView *cover;
		for (int i = lowerVisibleCover; i <= upperVisibleCover; i++) {
			cover = (AFItemView *)[onscreenCovers objectForKey:[NSNumber numberWithInt:i]];
			[offscreenCovers addObject:cover];
			[cover removeFromSuperview];
			[onscreenCovers removeObjectForKey:[NSNumber numberWithInt:cover.number]];
		}
        
		// Move all available covers to new location.
		for (int i=newLowerBound; i <= newUpperBound; i++) {
			cover = [self coverForIndex:i];
			[onscreenCovers setObject:cover forKey:[NSNumber numberWithInt:i]];
			[self updateCoverImage:cover];
			//[self.layer addSublayer:cover.layer];
            [self addSubview:cover];
		}
        
		lowerVisibleCover = newLowerBound;
		upperVisibleCover = newUpperBound;
		selectedCoverView = (AFItemView *)[onscreenCovers objectForKey:[NSNumber numberWithInt:newSelectedCover]];
		[self layoutCovers:newSelectedCover fromCover:newLowerBound toCover:newUpperBound];
		[self notifyCoverSelection];
		return;
	} else if (newSelectedCover > selectedCoverView.number) {
		// Move covers that are now out of range on the left to the right side,
		// but only if appropriate (within the range set by newUpperBound).
		for (int i=lowerVisibleCover; i < newLowerBound; i++) {
			cover = (AFItemView *)[onscreenCovers objectForKey:[NSNumber numberWithInt:i]];
			if (upperVisibleCover < newUpperBound) {
				// Tack it on the right side.
				upperVisibleCover++;
				cover.number = upperVisibleCover;
				[self updateCoverImage:cover];
				[onscreenCovers setObject:cover forKey:[NSNumber numberWithInt:cover.number]];
				[self layoutCover:cover selectedCover:newSelectedCover animated:NO];
			} else {
				// Recycle this cover.
				[offscreenCovers addObject:cover];
				[cover removeFromSuperview];
			}
			[onscreenCovers removeObjectForKey:[NSNumber numberWithInt:i]];
		}
		lowerVisibleCover = newLowerBound;
		
		// Add in any missing covers on the right up to the newUpperBound.
		for (int i=upperVisibleCover + 1; i <= newUpperBound; i++) {
			cover = [self coverForIndex:i];
			[onscreenCovers setObject:cover forKey:[NSNumber numberWithInt:i]];
			[self updateCoverImage:cover];
			//[self.layer addSublayer:cover.layer];
            [self addSubview:cover];
			[self layoutCover:cover selectedCover:newSelectedCover animated:NO];
		}
		upperVisibleCover = newUpperBound;
	} else {
		// Move covers that are now out of range on the right to the left side,
		// but only if appropriate (within the range set by newLowerBound).
		for (int i=upperVisibleCover; i > newUpperBound; i--) {
			cover = (AFItemView *)[onscreenCovers objectForKey:[NSNumber numberWithInt:i]];
			if (lowerVisibleCover > newLowerBound) {
				// Tack it on the left side.
				lowerVisibleCover --;
				cover.number = lowerVisibleCover;
				[self updateCoverImage:cover];
				[onscreenCovers setObject:cover forKey:[NSNumber numberWithInt:lowerVisibleCover]];
				[self layoutCover:cover selectedCover:newSelectedCover animated:NO];
			} else {
				// Recycle this cover.
				[offscreenCovers addObject:cover];
				[cover removeFromSuperview];
			}
			[onscreenCovers removeObjectForKey:[NSNumber numberWithInt:i]];
		}
		upperVisibleCover = newUpperBound;
		
		// Add in any missing covers on the left down to the newLowerBound.
		for (int i=lowerVisibleCover - 1; i >= newLowerBound; i--) {
			cover = [self coverForIndex:i];
			[onscreenCovers setObject:cover forKey:[NSNumber numberWithInt:i]];
			[self updateCoverImage:cover];
			//[self.layer addSublayer:cover.layer];
			[self addSubview:cover];
			[self layoutCover:cover selectedCover:newSelectedCover animated:NO];
		}
		lowerVisibleCover = newLowerBound;
	}
    
	if (selectedCoverView.number > newSelectedCover)
		[self layoutCovers:newSelectedCover fromCover:newSelectedCover toCover:selectedCoverView.number];
	else if (newSelectedCover > selectedCoverView.number)
		[self layoutCovers:newSelectedCover fromCover:selectedCoverView.number toCover:newSelectedCover];
	
	selectedCoverView = (AFItemView *)[onscreenCovers objectForKey:[NSNumber numberWithInt:newSelectedCover]];
    [self notifyCoverSelection];
}

@end
