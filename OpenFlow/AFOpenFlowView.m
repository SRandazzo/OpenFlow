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
#import "AFOpenFlowGeometry.h"

#define COVER_BUFFER 6

@interface AFOpenFlowView (hidden)

- (AFItemView *)coverForIndex:(int)coverIndex;
- (void)updateCoverImage:(AFItemView *)aCover;
- (AFItemView *)dequeueReusableCover;
- (void)layoutCovers:(int)selected fromCover:(int)lowerBound toCover:(int)upperBound;
- (void)layoutCover:(AFItemView *)aCover selectedCover:(int)selectedIndex animated:(Boolean)animated;
- (AFItemView *)findCoverOnscreen:(CALayer *)targetLayer;
- (void)notifyCoverTapped;

@end

@implementation AFOpenFlowView
@synthesize dataSource, viewDelegate, numberOfImages, defaultImage, selectedCoverCaption;

// parameters for reflection
const static CGFloat kReflectionFraction = 0.65;
const static CGFloat kReflectionAlpha    = 0.30;

- (void)setUpInitialState {
    
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
    middleTransform = CATransform3DMakeTranslation(0.0, 0.0, 80.0);
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
	sublayerTransform.m34 = -0.003;
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
    
    [self setMaxSizeForCoverFlowImages:CGSizeMake(self.frame.size.width, self.frame.size.height)];
}

- (AFItemView *)coverForIndex:(int)coverIndex {
	AFItemView *coverView = [self dequeueReusableCover];
	if (!coverView)
    {
		coverView = [[[AFItemView alloc] initWithFrame:CGRectZero] autorelease];

        if (!CGSizeEqualToSize(maxImageSize, CGSizeZero)) 
            [coverView setMaxCoverSize:maxImageSize];
             
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewTapped:)];
        [coverView addGestureRecognizer:tapGesture];
        [tapGesture release];
        
        UITapGestureRecognizer *doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewDoubleTapped:)];
        [doubleTapGesture setNumberOfTapsRequired:2];
        [coverView addGestureRecognizer:doubleTapGesture];
        [doubleTapGesture release];
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
	newPosition.y = 240;
    if (coverNumber < selectedIndex) {
		newPosition.x -= [AFOpenFlowGeometry centerCoverOffset];
		newTransform = leftTransform;
	} else if (coverNumber > selectedIndex) {
		newPosition.x += [AFOpenFlowGeometry centerCoverOffset];
		newTransform = rightTransform;
	} else {
		newTransform = middleTransform;
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
    
    [self bringSubviewToFront:selectedCoverCaption];
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
    [self releaseAll];
	
	[super dealloc];
}

- (void)releaseAll
{
    for (id key in onscreenCovers) {
        AFItemView* cover = [onscreenCovers objectForKey:key];
        [cover removeFromSuperview];
    }
    
    //[[self appWindow] removeObjectWithInterest:self];
	[defaultImage release];
    defaultImage = nil;
	
	[coverImages release];
	[coverImageHeights release];
    [coverImageCaptions release];
	[offscreenCovers removeAllObjects];
	[offscreenCovers release];
	
	[onscreenCovers removeAllObjects];
	[onscreenCovers release];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    //    NSLog(@"[%@ %s]", self, _cmd);
    halfScreenWidth = self.bounds.size.width / 2;
    halfScreenHeight = self.bounds.size.height / 2;
    [self setNumberOfImages:numberOfImages]; // resets view bounds and stuff
    CGPoint contentOffset = [self contentOffset];
    int targetCover = (int) roundf(contentOffset.x / 
								   [AFOpenFlowGeometry coverSpacing]);
    if (targetCover != selectedCoverView.number) {
        if (targetCover < 0)
            [self setSelectedCover:0];
        else if (targetCover >= self.numberOfImages)
            [self setSelectedCover:self.numberOfImages - 1];
        else
            [self setSelectedCover:targetCover];
    }
        
    CGFloat horizOrigin = contentOffset.x + halfScreenWidth - CAPTION_WIDTH / 2;
    CGFloat vertOrigin = selectedCoverView.frame.origin.y + selectedCoverView.frame.size.height / 2.0 + CAPTION_OFFSET+40;
    selectedCoverCaption.frame = CGRectMake(horizOrigin, vertOrigin, CAPTION_WIDTH, CAPTION_HEIGHT);
    selectedCoverCaption.text = [NSString stringWithFormat:@"%@", [coverImageCaptions objectForKey:[NSNumber numberWithInt:targetCover]]];
    // put it on top
    [self addSubview:selectedCoverCaption];
    [self bringSubviewToFront:selectedCoverCaption];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    // no scrolling below where the caption is
    return point.y < selectedCoverView.frame.origin.y + selectedCoverView.frame.size.width;
}

#pragma mark UIScrollViewDelegate
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

#pragma mark UIScrollView

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
	defaultImage = [[newDefaultImage addImageReflection:kReflectionFraction backgroundColor:self.backgroundColor alpha:kReflectionAlpha] retain];
}

- (void)setImage:(UIImage *)image forIndex:(int)index {
    [self setImage:image forIndex:index captionTitle:nil];
}

- (void)setImage:(UIImage *)image forIndex:(int)index captionTitle:(NSString*)captionTitle {
	// Create a reflection for this image.
	UIImage *imageWithReflection = [image addImageReflection:kReflectionFraction backgroundColor:self.backgroundColor alpha:kReflectionAlpha];
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

-(void)viewTapped:(UIGestureRecognizer *)sender
{
    AFItemView *targetCover = (AFItemView *)[sender view];
    int number = [targetCover number];
    if (targetCover && (number != selectedCoverView.number))
    {
        CGPoint selectedOffset = CGPointMake([AFOpenFlowGeometry coverSpacing] * targetCover.number, 0);
        [self setContentOffset:selectedOffset animated:YES];
    }
    else {
        [self notifyCoverTapped];
    }
}

-(void)viewDoubleTapped:(UIGestureRecognizer *)sender
{
    AFItemView *targetCover = (AFItemView *)[sender view];
    int number = [targetCover number];
    NSLog(@"Double tapped %d", number);
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

-(void)notifyCoverTapped
{
    // And send the delegate the newly selected cover message.
    if ([self.viewDelegate respondsToSelector:@selector(openFlowView:coverTapped:)])
        [self.viewDelegate openFlowView:self coverTapped:selectedCoverView.number];
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
