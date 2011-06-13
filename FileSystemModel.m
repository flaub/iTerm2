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

#import "FileSystemModel.h"
#include <Carbon/Carbon.h>

static
void OnFSEventStreamCallback(ConstFSEventStreamRef streamRef, 
							 void* clientCallBackInfo, 
							 size_t numEvents,
							 void* eventPaths,
							 const FSEventStreamEventFlags eventFlags[],
							 const FSEventStreamEventId eventIds[]);


@implementation FileSystemModel (DataSource)

- (int) outlineView: (NSOutlineView*) outlineView numberOfChildrenOfItem: (id) item
{
	return (item == nil) ? 1 : [item numberOfChildren];
}

- (BOOL) outlineView: (NSOutlineView*) outlineView isItemExpandable: (id) item
{
	return (item == nil) ? YES : ([item numberOfChildren] != -1);
}

- (id) outlineView: (NSOutlineView*) outlineView child: (int) index ofItem: (id) item
{
	FileSystemNode* node = (FileSystemNode*)item;
	if (node)
		return [node childAtIndex: index];
	else
		return _root;
}

- (id) outlineView: (NSOutlineView*) outlineView objectValueForTableColumn: (NSTableColumn*) tableColumn 
			byItem: (id) item
{
	return (item == nil) ? [_root fullPath] : [item relativePath];
}

@end

@interface FileSystemModel(Private)

- (void) onFSEvent: (NSString*) path 
		 withFlags: (FSEventStreamEventFlags) flags 
	   withEventId: (FSEventStreamEventId) eventId;

@end

@implementation FileSystemModel

void OnFSEventStreamCallback(ConstFSEventStreamRef streamRef, 
							 void* clientCallBackInfo, 
							 size_t numEvents,
							 void* eventPaths,
							 const FSEventStreamEventFlags eventFlags[],
							 const FSEventStreamEventId eventIds[])
{
	FileSystemModel* this = (FileSystemModel*)clientCallBackInfo;
	NSArray* paths = (NSArray*) eventPaths;

	NSLog(@"Paths: %@", paths);

	for (int i = 0; i < numEvents; i++) {
		[this onFSEvent: [paths objectAtIndex: i] withFlags: eventFlags[i] withEventId: eventIds[i]];
	}
}

- (id) initWithPath: (NSString*) path
{
	if ((self = [super init])) {
		_root = [[FileSystemNode alloc] initWithPath: path];
		NSArray* paths = [NSArray arrayWithObject: path];
		uint flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot;

		_context = malloc(sizeof(FSEventStreamContext));
		memset(_context, 0, sizeof(FSEventStreamContext));
		_context->info = self;

		_stream = FSEventStreamCreate(kCFAllocatorDefault,
									  OnFSEventStreamCallback,
									  _context,
									  (CFArrayRef) paths,
									  kFSEventStreamEventIdSinceNow,
									  1,
									  flags);
		
		FSEventStreamScheduleWithRunLoop(_stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		FSEventStreamStart(_stream);
	}
	return self;
}

- (void) delloc
{
	FSEventStreamStop(_stream);
	FSEventStreamUnscheduleFromRunLoop(_stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	FSEventStreamRelease(_stream);
	free(_context);
}

- (id) delegate { return _delegate; }
- (void) setDelegate: (id) delegate { _delegate = delegate; }
- (FileSystemNode*) root { return _root; }

- (void) onFSEvent: (NSString*) path 
		 withFlags: (FSEventStreamEventFlags) flags 
	   withEventId: (FSEventStreamEventId) eventId
{
	NSString* relativePath = [path substringFromIndex: [[_root fullPath] length]];
	FileSystemNode* item = [_root findItem: relativePath];
	NSLog(@"Found item: %@", [item fullPath]);
	if (item) {
		[item refresh];
		if ([_delegate respondsToSelector: @selector(onRefreshItem:)])
			[_delegate performSelector: @selector(onRefreshItem:) withObject: item];
	}
}

@end

@implementation FileSystemNode

- (id) initWithPath: (NSString*) path
{
	if ((self = [super init])) {
		_root = self;
		_path = [path copy];
		_parent = nil;
	}
	return self;
}

- (id) initWithPath: (NSString*) path parent: (FileSystemNode*) parent root: (FileSystemNode*) root
{
	if ((self = [super init])) {
		_root = root;
		_parent = parent;
		_path = [[path lastPathComponent] copy];
	}
	return self;
}

- (FileSystemNode*) root
{
	return _root;
}

// Creates, caches, and returns the array of children
// Loads children incrementally
- (NSArray*) children
{
	if (_children == NULL)
		[self refresh];
    return _children;
}

- (void) refresh
{
	if (!_isLeaf)
		[_children release];
		
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSString* fullPath = [self fullPath];
	BOOL isDir;
	BOOL valid = [fileManager fileExistsAtPath: fullPath isDirectory: &isDir];
	
	if (valid && isDir)	{
		NSError* error;
		NSArray* array = [fileManager contentsOfDirectoryAtPath:fullPath error:&error];
		int numChildren = [array count];
		_children = [[NSMutableArray alloc] initWithCapacity: numChildren];
		
		for (int i = 0; i < numChildren; i++) {
			NSString* path = [array objectAtIndex: i];
			if ([path characterAtIndex: 0] == '.')
				continue;
			
			FileSystemNode* newChild = [[FileSystemNode alloc] initWithPath: path parent: self root: _root];
			[_children addObject: newChild];
			[newChild release];
		}
	}
	else {
		_isLeaf = YES;
	}
}

- (NSString*) relativePath { return _path; }

- (NSString*) fullPath
{
	// If no parent, return our own relative path
	if (_parent == nil) 
		return _path;
	
	// recurse up the hierarchy, prepending each parent’s path
	return [[_parent fullPath] stringByAppendingPathComponent: _path];
}

- (FileSystemNode*) childAtIndex:(int) index
{
	return [[self children] objectAtIndex: index];
}

- (int) numberOfChildren
{
	return (_isLeaf) ? (-1) : [[self children] count];
}

- (NSArray*) popItem: (NSArray*) array
{
	int count = [array count];
	int location = 1;
	if (count == 1)
		location = 0;
	return [array subarrayWithRange: NSMakeRange(location, count - 1)];
}

- (FileSystemNode*) findItem: (NSString*) path
{
	NSArray* parts = [path pathComponents];
	//NSLog(@"findItem: %@, %x", parts);

	while ([parts count]) {
		NSString* part = [parts objectAtIndex: 0];
		parts = [self popItem: parts];
		if ([part isEqualToString: @"/"])
			continue;
		
		if (!_children)
			return nil;
		
		if (_isLeaf)
			return self;
		
		for (FileSystemNode* child in _children) {
			if ([[child relativePath] isEqualToString: part]) {
				NSString* newPath = [NSString pathWithComponents: parts];
				return [child findItem: newPath];
			}
		}
		return nil;
	}
	
	return self;
}

- (void) dealloc
{
	if (!_isLeaf)
		[_children release];
	[_path release];
	[super dealloc];
}

@end
