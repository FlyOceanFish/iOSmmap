//
//  ViewController.m
//  testMMap
//
//  Created by FlyOceanFish on 2018/4/2.
//  Copyright © 2018年 FlyOceanFish. All rights reserved.
//

#import "ViewController.h"
#import <sys/mman.h>
#import <sys/stat.h>

int MapFile( char * inPathName, void ** outDataPtr, size_t * outDataLength );

void ProcessFile( char * inPathName )
{
    size_t dataLength;
    void * dataPtr;
    void *start;
    if( MapFile( inPathName, &dataPtr, &dataLength ) == 0 )
    {
        start = dataPtr;
        dataPtr = dataPtr+3;
        memcpy(dataPtr, "CCCC", 4);
        // Unmap files:
        munmap(start, 7);
    }
}
// MapFile

// Exit:    outDataPtra     pointer to the mapped memory region
//          outDataLength   size of the mapped memory region
//          return value    an errno value on error (see sys/errno.h)
//                          or zero for success
//
int MapFile( char * inPathName, void ** outDataPtr, size_t * outDataLength )
{
    int outError;
    int fileDescriptor;
    struct stat statInfo;
    
    // Return safe values on error.
    outError = 0;
    *outDataPtr = NULL;
    *outDataLength = 0;
    
    // Open the file.
    fileDescriptor = open( inPathName, O_RDWR, 0 );
    if( fileDescriptor < 0 )
    {
        outError = errno;
    }
    else
    {
        // We now know the file exists. Retrieve the file size.
        if( fstat( fileDescriptor, &statInfo ) != 0 )
        {
            outError = errno;
        }
        else
        {
            ftruncate(fileDescriptor, statInfo.st_size+4);//增加文件大小
            fsync(fileDescriptor);//刷新文件
            *outDataPtr = mmap(NULL,
                               statInfo.st_size+4,
                               PROT_READ|PROT_WRITE,
                               MAP_FILE|MAP_SHARED,
                               fileDescriptor,
                               0);
            if( *outDataPtr == MAP_FAILED )
            {
                outError = errno;
            }
            else
            {
                // On success, return the size of the mapped file.
                *outDataLength = statInfo.st_size;
            }
        }
        
        // Now close the file. The kernel doesn’t use our file descriptor.
        close( fileDescriptor );
    }
    
    return outError;
}

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextView *mTV;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *str = @"AAA";
    NSError *error;
    NSString *filePath = [NSString stringWithFormat:@"%@/text.txt",path];
    [str writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"%@",error);
    }
    ProcessFile(filePath.UTF8String);
    NSString *result = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    self.mTV.text = result;
}


@end
