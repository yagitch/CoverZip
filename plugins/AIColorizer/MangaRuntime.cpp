#include "MangaRuntime.h"
#include "onnxruntime_cxx_api.h"
#include <cstdio>
#include <cstring>
#include <memory>
#include <os/log.h>

namespace {
Ort::Env &environment() {
    static Ort::Env env(ORT_LOGGING_LEVEL_ERROR, "CoverZipManga");
    env.DisableTelemetryEvents();
    return env;
}
struct Model {
    Ort::Session session{nullptr};
    std::string input, output;
    Model(const char *path, bool accelerate) {
        Ort::SessionOptions options;
        options.SetIntraOpNumThreads(4);
        options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        if (accelerate) {
            options.AppendExecutionProvider("CoreML", {{"ModelFormat", "MLProgram"},
                {"MLComputeUnits", "CPUAndGPU"}, {"RequireStaticInputShapes", "1"}});
        }
        session = Ort::Session(environment(), path, options);
        Ort::AllocatorWithDefaultOptions allocator;
        input = session.GetInputNameAllocated(0, allocator).get();
        output = session.GetOutputNameAllocated(0, allocator).get();
        auto inputInfo = session.GetInputTypeInfo(0);
        auto outputInfo = session.GetOutputTypeInfo(0);
        std::fprintf(stderr, "[Manga] %s input:", input.c_str());
        for (auto d : inputInfo.GetTensorTypeAndShapeInfo().GetShape()) std::fprintf(stderr, " %lld", (long long)d);
        std::fprintf(stderr, " output %s:", output.c_str());
        for (auto d : outputInfo.GetTensorTypeAndShapeInfo().GetShape()) std::fprintf(stderr, " %lld", (long long)d);
        std::fprintf(stderr, "\n");
    }
};
}

void *cz_manga_create(const char *path, int accelerate) {
    try { return new Model(path, accelerate != 0); }
    catch (const std::exception &error) {
        os_log_error(OS_LOG_DEFAULT, "[Manga] load failed: %{public}s", error.what());
        return nullptr;
    }
}
void cz_manga_destroy(void *model) { delete static_cast<Model *>(model); }

int64_t cz_manga_run(void *handle, const float *input, const int64_t *shape, int rank,
                    float *output, int64_t capacity, int64_t *output_shape, int *output_rank) {
    if (!handle || rank < 1 || rank > 8) return -1;
    try {
        auto &model = *static_cast<Model *>(handle);
        int64_t count = 1;
        for (int i = 0; i < rank; ++i) { if (shape[i] <= 0) return -1; count *= shape[i]; }
        auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        auto tensor = Ort::Value::CreateTensor<float>(memory, const_cast<float *>(input), count, shape, rank);
        const char *inputs[] = {model.input.c_str()}, *outputs[] = {model.output.c_str()};
        auto result = model.session.Run(Ort::RunOptions{nullptr}, inputs, &tensor, 1, outputs, 1);
        auto info = result[0].GetTensorTypeAndShapeInfo();
        auto resultShape = info.GetShape();
        auto size = info.GetElementCount();
        if (size > static_cast<size_t>(capacity) || resultShape.size() > 8 || info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) return -1;
        *output_rank = static_cast<int>(resultShape.size());
        std::copy(resultShape.begin(), resultShape.end(), output_shape);
        std::memcpy(output, result[0].GetTensorData<float>(), size * sizeof(float));
        return static_cast<int64_t>(size);
    } catch (const std::exception &error) {
        std::fprintf(stderr, "[Manga] inference failed: %s\n", error.what());
        return -1;
    }
}
