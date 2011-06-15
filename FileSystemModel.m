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
	FileSystemNode* node = (FileSystemNode*)item;
	if (!node) {
		return 1;
	}
	[node refresh];

	int ret = [node numberOfChildren];
//	NSLog(@"outlineView> numberOfChildrenOfItem: %@, ret: %d", [node relativePath], ret);
	return ret;
}

- (BOOL) outlineView: (NSOutlineView*) outlineView isItemExpandable: (id) item
{
	FileSystemNode* node = (FileSystemNode*)item;
	BOOL ret = [node isExpandable];
//	NSLog(@"outlineView> isItemExpandable: %@: %d", [node relativePath], ret);
	return ret;
}

- (id) outlineView: (NSOutlineView*) outlineView child: (int) index ofItem: (id) item
{
	FileSystemNode* node = (FileSystemNode*)item;
//	NSLog(@"outlineView> child: %d ofItem: %@", index, [node relativePath]);
	if (!node)
		return _root;
	return [node childAtIndex: index];
}

- (id) outlineView: (NSOutlineView*) outlineView objectValueForTableColumn: (NSTableColumn*) tableColumn 
			byItem: (id) item
{
	FileSystemNode* node = (FileSystemNode*)item;
//	NSLog(@"outlineView> objectValueForTableColumn: byItem: %@", [node relativePath]);
	return (node == nil) ? [_root fullPath] : [node relativePath];
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

//	NSLog(@"Paths: %@", paths);

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
	FileSystemNode* node = [_root findItem: relativePath];
	if (node) {
		NSLog(@"Found node: %@", [node fullPath]);
		[node refresh];
		if ([_delegate respondsToSelector: @selector(onRefreshItem:)])
			[_delegate performSelector: @selector(onRefreshItem:) withObject: node];
	}
}

@end

@implementation FileSystemNode

- (id) initWithPath: (NSString*) path
{
	if ((self = [super init])) {
		_root = self;
		_path = [path copy];
		_relpath = [[path lastPathComponent] copy];
		_parent = nil;
	}
	return self;
}

- (id) initWithPath: (NSString*) path parent: (FileSystemNode*) parent root: (FileSystemNode*) root
{
	if ((self = [super init])) {
		_root = root;
		_parent = parent;
		_path = [[[parent fullPath] stringByAppendingPathComponent:path] copy];
		_relpath = [[path lastPathComponent] copy];
	}
	return self;
}

- (void) refresh
{
	if (_children)
		[_children release];
	_children = nil;
	
	if (![self isExpandable])
		return;
		
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSArray* array = [fileManager contentsOfDirectoryAtPath:_path error:nil];
	int numChildren = [array count];
	_children = [[NSMutableArray alloc] initWithCapacity: numChildren];
	 
	for (int i = 0; i < numChildren; i++) {
		NSString* path = [array objectAtIndex: i];
		
		// hide files that begin with a dot (.)
		if ([path characterAtIndex: 0] == '.')
			continue;
		
		FileSystemNode* newChild = [[FileSystemNode alloc] initWithPath: path parent: self root: _root];
		[_children addObject: newChild];
		[newChild release];
	}
}

- (FileSystemNode*) root { return _root; }
- (NSString*) fullPath { return _path; }
- (NSString*) relativePath { return _relpath; }

- (FileSystemNode*) childAtIndex:(int) index
{
	return [_children objectAtIndex: index];
}

- (int) numberOfChildren
{
	return [_children count];
}

- (BOOL) isExpandable
{
//	NSLog(@"isExpandable> %@", _path);
	NSFileManager* fileManager = [NSFileManager defaultManager];
	BOOL isDir;
	BOOL valid = [fileManager fileExistsAtPath: _path isDirectory: &isDir];
	return (valid && isDir);
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
	if (_children)
		[_children release];
	[_path release];
	[_relpath release];
	[super dealloc];
}

@end
