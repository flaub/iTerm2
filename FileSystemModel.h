/*
 **  FileSystemView.m
 **  iTerm
 **
 **  Copyright (c) 2011
 **
 **  Author: Frank Laub
 **
 **  Description: Models a file system.
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

#import <Cocoa/Cocoa.h>

@interface FileSystemNode : NSObject {
@private
	NSString* _path;
	NSString* _relpath;
	FileSystemNode* _root;
	FileSystemNode* _parent;
	NSMutableArray* _children;
	BOOL _isExpanded;
}

- (id) initWithPath: (NSString*) path;
- (FileSystemNode*) root;
- (int) numberOfChildren;
- (FileSystemNode*) childAtIndex: (int) index; // Invalid to call on leaf nodes
- (NSString*) fullPath;
- (NSString*) relativePath;
- (FileSystemNode*) findItem: (NSString*) path;
- (void) refresh;
- (BOOL) isExpandable;

@end

@interface FileSystemModel : NSObject <NSOutlineViewDataSource> {
@private
	FileSystemNode* _root;
	FSEventStreamContext* _context;
	FSEventStreamRef _stream;
	id _delegate;
}

- (FileSystemNode*) root;
- (id) delegate;
- (void) setDelegate: (id) delegate;
- (id) initWithPath: (NSString*) path;

@end

