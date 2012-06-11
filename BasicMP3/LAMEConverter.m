//
//  LAMEConverter.m
//  BasicMP3
//
//  Created by Alex Nichol on 6/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "LAMEConverter.h"

@implementation LAMEConverter

+ (BOOL)supportsExtension:(NSString *)oldExt toExtension:(NSString *)newExt {
    NSArray * fileTypes = [NSArray arrayWithObjects:@"aif", @"aiff", @"aifc", @"wav",
                           @"sd2", @"mp3", @"mp2", @"mp1", @"mpg", @"caf", @"caff",
                           @"snd", @"au", nil];
    if ([fileTypes containsObject:oldExt] && [newExt isEqualToString:@"mp3"]) {
        return YES;
    } else {
        return NO;
    }
}

- (void)convertSynchronously:(ACConverterCallback)callback {
    NSBundle * currentBundle = [NSBundle bundleWithIdentifier:@"com.aqnichol.BasicMP3"];
    NSString * convertPath = [[currentBundle resourcePath] stringByAppendingPathComponent:@"lameconvert"];
    converterTask = [[NSTask alloc] init];
    [converterTask setLaunchPath:convertPath];
    [converterTask setArguments:[NSArray arrayWithObjects:file, sourceExtension, tempFile, nil]];
    NSPipe * infoPipe = [NSPipe pipe];
    [converterTask setStandardOutput:infoPipe];
    [converterTask launch];
    
    NSFileHandle * handle = [infoPipe fileHandleForReading];
    NSMutableString * line = [NSMutableString string];
    
    BOOL failed = NO;
    while ([converterTask isRunning]) {
        if ([[NSThread currentThread] isCancelled]) {
            [converterTask terminate];
            return;
        }
        NSData * charData = [handle readDataOfLength:1];
        if ([charData length] == 0) break;
        
        if ([[NSThread currentThread] isCancelled]) {
            [converterTask terminate];
            return;
        }
        
        char byte = ((const char *)[charData bytes])[0];
        if (byte == '\n') {
            if ([line isEqualToString:@"done"]) {
                break;
            } else if ([line isEqualToString:@"error"]) {
                callback(ACConverterCallbackTypeError, 0, [NSError errorWithDomain:@"LAME" code:1 userInfo:nil]);
                failed = YES;
                break;
            } else {
                float progress = [line floatValue];
                callback(ACConverterCallbackTypeProgress, progress, nil);
            }
            [line deleteCharactersInRange:NSMakeRange(0, [line length])];
        } else {
            [line appendFormat:@"%c", byte];
        }
    }

    if ([converterTask isRunning]) {
        [converterTask terminate];
    }

    if ([[NSThread currentThread] isCancelled]) {
        return;
    }

    if (!failed) {
        NSError * error = nil;
        if (![self placeTempFile:&error]) {
            callback(ACConverterCallbackTypeError, 0, error);
        }
    } else {
        callback(ACConverterCallbackTypeDone, 0, nil);
    }
}

@end
