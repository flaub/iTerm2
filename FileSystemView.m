/*
 **  FileSystemView.m
 **  iTerm
 **
 **  Copyright (c) 2011
 **
 **  Author: Frank Laub
 **
 **  Description: Custom view that displays the file system as a tree.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 */

#import "FileSystemView.h"


@implementation FileSystemView

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)dealloc
{
    [super dealloc];
}

- (void) setRootPath: (NSString*) path
{
	[_fs release];	
	_fs = [[FileSystemModel alloc] initWithPath: path];
	[_fs setDelegate: self];
	[self setDataSource: _fs];
	[self reloadData];
	[self expandItem: [_fs root]];
}

@end
