//
//  AFOpenFlowGeometry.m
//  AFOpenFlowDemo
//
//  Created by Jonathan Saggau on 10/22/10.
//  Copyright 2010 Sounds Broken inc. All rights reserved.
//

#import "AFOpenFlowGeometry.h"


@implementation AFOpenFlowGeometry


+(CGFloat)sideCoverAngle
{
    static CGFloat sideCoverAngle;
    if (!sideCoverAngle) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        {
            sideCoverAngle = 1.59f;
        }
        else 
        {
            sideCoverAngle = 1.39f;
        }
    }
    return sideCoverAngle;
}


+(CGFloat)sideCoverZPosition
{
    static CGFloat sideCoverZPosition;
    if (!sideCoverZPosition) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        {
            sideCoverZPosition = -150.0f;
        }
        else 
        {
            sideCoverZPosition = -90.0f;
        }
    }
    return sideCoverZPosition;
}

+(CGFloat)coverSpacing
{
    static CGFloat coverSpacing;
    if (!coverSpacing) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        {
            coverSpacing = 80.0f;
        }
        else 
        {
            coverSpacing = 40.0f;
        }
    }
    return coverSpacing;
}

+(CGFloat)centerCoverOffset
{
    static CGFloat centerCoverOffset;
    if (!centerCoverOffset) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        {
            centerCoverOffset = 270.0f;
        }
        else 
        {
            centerCoverOffset = 70.0f;
        }
    }
    return centerCoverOffset;
}

@end
