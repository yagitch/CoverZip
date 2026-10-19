#include "MangaRuntime.h"
#include <string>
#include <cstdio>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    for (const char *name : {"head.onnx", "foreground-fp16.onnx", "generator512.onnx"}) {
        auto path = std::string(argv[1]) + "/" + name;
        std::fprintf(stderr, "%s\n", name);
        auto model = cz_manga_create(path.c_str(), 1);
        if (!model) return 1;
        cz_manga_destroy(model);
    }
}
