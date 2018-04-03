# iOSmmap
在iOS中实现mmap
文件内存映射(mmap)之前看过很多文章提及到，但是都没有写iOS中具体的实现，只是都说对于大文件读写效率比较高等。所以作者就专门研究了以下mmap技术，并且实现了一下
# mmap
文件映射是将文件的磁盘扇区映射到进程的虚拟内存空间的过程。一旦被映射，您的应用程序就会访问这个文件，就好像它完全驻留在内存中一样（<font color = 'red'>不占用内存，使用的是虚拟内存</font>）。当您从映射的文件指针读取数据时，将在适当的数据中的内核页面并将其返回给您的应用程序。

## 疑问
那大家就会想了，既然不消耗内存，那岂不是都用mmap就行了，这样多好啊，又不占内存。其实不然，并不是所有的场景都适合使用mmap的

## 适合的场景
* 您有一个很大的文件，其内容您想要随机访问一个或多个时间。
* 您有一个小文件，它的内容您想要立即读入内存并经常访问。这种技术最适合那些大小不超过几个虚拟内存页的文件。（页是地址空间的最小单位，虚拟页和物理页的大小是一样的，通常为4KB。）
* 您需要在内存中缓存文件的特定部分。文件映射消除了缓存数据的需要，这使得系统磁盘缓存中的其他数据空间更大。

当随机访问一个非常大的文件时，通常最好只映射文件的一小部分。映射大文件的问题是文件会消耗活动内存。如果文件足够大，系统可能会被迫将其他部分的内存分页以加载文件。将多个文件映射到内存中会使这个问题更加复杂。
## 不适合的场景
* 您希望从开始到结束的顺序从头到尾读取一个文件。
* 这个文件有几百兆字节或者更大。将大文件映射到内存中会快速地填充内存，并可能导致分页，这将抵消首先映射文件的好处。对于大型顺序读取操作，禁用磁盘缓存并将文件读入一个小内存缓冲区。
* 该文件大于可用的连续虚拟内存地址空间。对于64位应用程序来说，这不是什么问题，但是对于32位应用程序来说，这是一个问题。
* 该文件位于可移动驱动器上。
* 该文件位于网络驱动器上。

# 实现
这个代码实现的功能就是首先读取存储在我们沙盒的文件，然后在该文件的上继续写入数据（追加数据）
```Objective-C
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
```
最重要的就是2个函数：`mmap()`和`munmap()`。
* mmap()
>void* mmap(void* start,size_t length,int prot,int flags,int fd,off_t offset);

start：映射区的开始地址，设置为0时表示由系统决定映射区的起始地址。
length：映射区的长度。//长度单位是 以字节为单位，不足一内存页按一内存页处理
prot：期望的内存保护标志，不能与文件的打开模式冲突。是以下的某个值，可以通过or运算合理地组合在一起
PROT_EXEC //页内容可以被执行
PROT_READ //页内容可以被读取
PROT_WRITE //页可以被写入
PROT_NONE //页不可访问
flags：指定映射对象的类型，映射选项和映射页是否可以共享。它的值可以是一个或者多个以下位的组合体
fd：有效的文件描述词。一般是由open()函数返回，其值也可以设置为-1，此时需要指定flags参数中的MAP_ANON,表明进行的是匿名映射。
off_toffset：被映射对象内容的起点。

***这里的参数我们要重点关注3个`length`、`prot`、`flags`。
`length`代表了我们可以操作的内存大小；
`prot`代表我们对文件的操作权限。这里传入了读写权限，而且注意要与`open()`保持一致，所以`open()`函数传入了`O_RDWR`可读写权限；。
`flags`要写`MAP_FILE|MAP_SHARED`,我一开始只写了`MAP_FILE`,能读，但是不能写。***
* munmap()
>int munmap(void* start,size_t length);

>这里对原来文件追加写入数据要注意一点，读取原来文件之后，我们只有原来文件大小的可写区域。例如以上例子原文件中是AAA，这时我们要写入CCCC，做覆盖写入的话我们只能写入CCC。所以要要对文件进行追加写入的话，必须提前增加文件的大小即调用`ftruncate()`和`sync()`，增加了4位了，最终才能使CCCC顺利写入
