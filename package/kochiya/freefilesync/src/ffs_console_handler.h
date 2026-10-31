// Console implementation of FreeFileSync's StatusHandler for the headless CLI.
#pragma once

#include <status_handler.h>
#include <zen/stl_tools.h>
#include "ffs_batch_config.h"

namespace fff
{
class ConsoleStatusHandler : public StatusHandler
{
public:
    ConsoleStatusHandler(std::wstring jobName,
                         std::chrono::system_clock::time_point startTime,
                         bool ignoreErrors,
                         size_t autoRetryCount,
                         std::chrono::seconds autoRetryDelay,
                         BatchErrorHandling batchErrorHandling);

    struct Result
    {
        ProcessSummary summary;
        zen::SharedRef<zen::ErrorLog> errorLog;
    };

    void forceUiUpdateNoThrow() override; //noexcept

    Result prepareResult();

    void logMessage(const std::wstring& msg, MsgType type) override;
    void reportWarning(const std::wstring& msg, bool& warningActive) override;
    Response reportError(const ErrorInfo& errorInfo) override;
    void reportFatalError(const std::wstring& msg) override;
    ErrorStats getErrorStats() const override;

private:
    void printProgress();

    const std::wstring jobName_;
    const std::chrono::system_clock::time_point startTime_;
    const bool ignoreErrors_;
    const size_t autoRetryCount_;
    const std::chrono::seconds autoRetryDelay_;
    const BatchErrorHandling batchErrorHandling_;

    zen::SharedRef<zen::ErrorLog> errorLog_ = zen::makeSharedRef<zen::ErrorLog>();
    mutable ErrorStats errorStatsBuf_{};
    mutable size_t errorStatsRowsChecked_ = 0;
    bool tty_ = false;
    bool lastProgressHadNewline_ = true;
};
}
