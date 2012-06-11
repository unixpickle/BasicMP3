//
//  main.m
//  lameconvert
//
//  Created by Alex Nichol on 6/10/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "lame.h"

static lame_t gLameSettings;

AudioStreamBasicDescription inputFormat;
AudioStreamBasicDescription clientFormat;
ExtAudioFileRef inputFile;

AudioFileTypeID fileTypeForExtension(NSString * extension);
OSStatus convertFile(NSString * source, NSString * ext, NSString * destination);
OSStatus applyClientFormat();
OSStatus encodeFile(NSString * outputPath);

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        gLameSettings = lame_init();
        if (argc != 4) {
            fprintf(stderr, "Usage: %s source source_ext dest\n", argv[0]);
            return 1;
        }
        if (convertFile([NSString stringWithUTF8String:argv[1]], [NSString stringWithUTF8String:argv[2]],
                        [NSString stringWithUTF8String:argv[3]]) == noErr) {
            printf("done\n");
        } else {
            printf("error\n");
        }
    }
    return 0;
}

AudioFileTypeID fileTypeForExtension(NSString * extension) {
    NSDictionary * fileTypes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithUnsignedLongLong:kAudioFileAIFFType], @"aif",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileAIFFType], @"aiff",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileAIFCType], @"aifc",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileWAVEType], @"wav",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileSoundDesigner2Type], @"sd2",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileMP3Type], @"mp3",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileMP2Type], @"mp2",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileMP1Type], @"mp1", 
                                [NSNumber numberWithUnsignedLongLong:kAudioFileMP1Type], @"mpg",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileCAFType], @"caf", 
                                [NSNumber numberWithUnsignedLongLong:kAudioFileCAFType],@"caff", 
                                [NSNumber numberWithUnsignedLongLong:kAudioFileNextType], @"snd",
                                [NSNumber numberWithUnsignedLongLong:kAudioFileNextType], @"au",
                                nil];
    return (AudioFileTypeID)[[fileTypes objectForKey:extension] unsignedLongLongValue];
}

OSStatus convertFile(NSString * source, NSString * ext, NSString * destination) {
    NSURL * sourceURL = [NSURL fileURLWithPath:source];
    AudioFileID fileID;
    OSStatus err = AudioFileOpenURL((__bridge CFURLRef)sourceURL, 1,
                                    fileTypeForExtension(ext),
                                    &fileID);

    if (err != noErr) return err;
    err = ExtAudioFileWrapAudioFileID(fileID, FALSE, &inputFile);
    if (err != noErr) return err;
    
    // get input format
    UInt32 size = sizeof(inputFormat);
    Boolean writable = 0;
    ExtAudioFileGetPropertyInfo(inputFile, kExtAudioFileProperty_FileDataFormat, &size, &writable);
    err = ExtAudioFileGetProperty(inputFile, kExtAudioFileProperty_FileDataFormat, &size, &inputFormat);
    if (err != noErr) return err;
    
    applyClientFormat();
    
    int bitRate = (int)(clientFormat.mSampleRate * clientFormat.mBitsPerChannel * clientFormat.mChannelsPerFrame);
    
    lame_set_num_channels(gLameSettings, clientFormat.mChannelsPerFrame);
    lame_set_in_samplerate(gLameSettings, clientFormat.mSampleRate);
    lame_set_out_samplerate(gLameSettings, clientFormat.mSampleRate);
    lame_set_brate(gLameSettings, (int)bitRate);
    lame_set_mode(gLameSettings, STEREO);
    lame_init_params(gLameSettings);
    
    err = encodeFile(destination);
    
    ExtAudioFileDispose(inputFile);
    AudioFileClose(fileID);
    return err;
}

OSStatus applyClientFormat() {
    clientFormat.mSampleRate = inputFormat.mSampleRate;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    clientFormat.mChannelsPerFrame = 2;
    clientFormat.mBitsPerChannel = 16;
    clientFormat.mBytesPerFrame = 2 * inputFormat.mChannelsPerFrame;
    clientFormat.mBytesPerPacket = clientFormat.mBytesPerFrame;
    clientFormat.mFramesPerPacket = 1;
    
    OSStatus err;
    UInt32 size = sizeof(clientFormat);
    err = ExtAudioFileSetProperty(inputFile, kExtAudioFileProperty_ClientDataFormat, size, &clientFormat);
    if (err != noErr) return err;
    
    return noErr;
}

OSStatus encodeFile(NSString * outputPath) {
    SInt64 inputFileSize = 0;
    UInt32 _size = sizeof(inputFileSize);
    OSStatus err;
    
    err = ExtAudioFileGetProperty(inputFile, kExtAudioFileProperty_FileLengthFrames, &_size, &inputFileSize);
    if (err != noErr) return err;
    
    UInt32 bytesForFrame = clientFormat.mBytesPerFrame;
    UInt32 bufferSizeInFrames = 65536;
    UInt32 bufferSize = (bufferSizeInFrames * bytesForFrame);
    UInt8 * buffer = (UInt8 *)malloc(bufferSize);
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mNumberChannels = clientFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mData = buffer;
    bufferList.mBuffers[0].mDataByteSize = bufferSize;
    
    int mp3bufsize = bufferSize * 2 + 7500;
    unsigned char * mp3buf = (unsigned char *)malloc(mp3bufsize);
    
    FILE * fp = fopen([outputPath UTF8String], "w");
    
    UInt32 encodedFrames = 0;
    
    while (TRUE) {
        UInt32 framesRead = bufferSizeInFrames;
        err = ExtAudioFileRead(inputFile, &framesRead, &bufferList);
        if (err != noErr) {
            free(buffer);
            free(mp3buf);
            return err;
        }
        
        encodedFrames += framesRead;
        
        if (framesRead == 0) break;
        
        int size = lame_encode_buffer_interleaved(gLameSettings, (short *)buffer, framesRead, mp3buf, mp3bufsize);
        fwrite(mp3buf, 1, size, fp);
        
        printf("%f\n", (float)encodedFrames / (float)inputFileSize);
    }
    
    int size = lame_encode_flush(gLameSettings, mp3buf, mp3bufsize);
    if (size > 0) {
        fwrite(mp3buf, 1, size, fp);   
    }

    fclose(fp);
    free(mp3buf);    
    free(buffer);
    return noErr;
}
