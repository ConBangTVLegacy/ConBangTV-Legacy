// cbsymcheck — chạy trên máy iOS 6: đọc từ stdin từng dòng «<đường dẫn thư viện> <ký hiệu>» (lấy từ `nm -m` của tệp dựng),
// tra ký hiệu đúng trong thư viện đó (dlopen RTLD_FIRST: chỉ thư viện ấy và các thư viện nó tái xuất — giống cách dyld gắn ký
// hiệu hai tầng), in ra những ký hiệu iOS này không có. Dùng trước khi chạy app để khỏi dò từng lỗi «dyld: Symbol not found».
#include <dlfcn.h>
#include <stdio.h>

int main(void) {
    char line[2048], lib[1024], sym[1024];
    int total = 0, missing = 0;
    while (fgets(line, sizeof(line), stdin)) {
        if (sscanf(line, "%1023s %1023s", lib, sym) != 2) continue;
        total++;
        void *handle = dlopen(lib, RTLD_LAZY | RTLD_FIRST);
        if (!handle) {
            printf("THIẾU-THƯ-VIỆN %s %s\n", lib, sym);
            missing++;
            continue;
        }
        if (!dlsym(handle, sym[0] == '_' ? sym + 1 : sym)) {
            printf("THIẾU %s %s\n", lib, sym);
            missing++;
        }
    }
    printf("đã tra %d ký hiệu, thiếu %d\n", total, missing);
    return missing ? 1 : 0;
}
