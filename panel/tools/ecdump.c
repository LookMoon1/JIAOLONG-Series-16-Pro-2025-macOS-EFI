// ecdump — 读取 MechrevoEC 驱动发布的 EC 快照（只读，无需 root）
// 用法: ./ecdump [seq]
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

int main(int argc, char **argv)
{
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
                            IOServiceMatching("MechrevoEC"));
    if (!svc) {
        fprintf(stderr, "服务未找到（kext 未加载？）\n");
        return 2;
    }

    CFMutableDictionaryRef props = NULL;
    if (IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) != KERN_SUCCESS || !props) {
        fprintf(stderr, "读取属性失败\n");
        return 3;
    }

    long long seq = -1;
    CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(props, CFSTR("Seq"));
    if (num) CFNumberGetValue(num, kCFNumberLongLongType, &seq);

    int raw = (argc > 1 && strcmp(argv[1], "-r") == 0);

    if (!raw && argc > 1 && atoll(argv[1]) == seq && seq >= 0) {
        printf("unchanged seq=%lld\n", seq);
    } else {
        CFDataRef map = (CFDataRef)CFDictionaryGetValue(props, CFSTR("ECMap"));
        if (!map) {
            fprintf(stderr, "无 ECMap 数据\n");
            return 4;
        }
        const UInt8 *b = CFDataGetBytePtr(map);
        CFIndex len = CFDataGetLength(map);
        if (raw) {
            printf("%lld ", seq);
            for (CFIndex i = 0; i < len; i++) printf("%02X", b[i]);
            printf("\n");
        } else {
            printf("seq=%lld len=%ld\n", seq, (long)len);
            for (CFIndex row = 0; row < len; row += 16) {
                printf("%02lX:", (long)row);
                for (CFIndex i = row; i < row + 16 && i < len; i++) printf(" %02X", b[i]);
                printf("\n");
            }
        }
    }

    CFRelease(props);
    IOObjectRelease(svc);
    return 0;
}
