#pragma once

#include <string>
#include <utility>
#include <zen/zstring.h>
#include <base/structures.h>

namespace fff
{
enum class BatchErrorHandling
{
    showPopup,
    cancel
};

enum class PostBatchAction
{
    none,
    sleep,
    shutdown
};

struct FfsGuiConfig
{
    MainConfiguration mainCfg;
    std::wstring notes;
};

struct BatchExclusiveConfig
{
    bool runMinimized = false;
    bool autoCloseSummary = false;
    BatchErrorHandling batchErrorHandling = BatchErrorHandling::showPopup;
    PostBatchAction postBatchAction = PostBatchAction::none;
};

struct FfsBatchConfig
{
    FfsGuiConfig guiCfg;
    BatchExclusiveConfig batchExCfg;
};

// Parse a FreeFileSync .ffs_batch file. Throws zen::FileError.
std::pair<FfsBatchConfig, std::wstring /*warningMsg*/> readBatchConfig(const Zstring& filePath);
}
