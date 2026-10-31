#include "ffs_console_handler.h"

#include <iostream>
#include <unistd.h>
#include <zen/format_unit.h>
#include <zen/extra_log.h>
#include <zen/stl_tools.h>
#include <zen/time.h>

using namespace zen;
using namespace fff;

namespace
{
std::string toUtf8(const std::wstring& s) { return utfTo<std::string>(s); }

std::wstring phaseLabel(ProcessPhase phase)
{
    switch (phase)
    {
        case ProcessPhase::none:          return L"initializing";
        case ProcessPhase::scan:          return L"scanning";
        case ProcessPhase::binaryCompare: return L"comparing content";
        case ProcessPhase::sync:          return L"synchronizing";
    }
    return L"working";
}

void writeErrLine(const std::string& line)
{
    std::cerr << line << '\n';
}
}


ConsoleStatusHandler::ConsoleStatusHandler(std::wstring jobName,
                                           std::chrono::system_clock::time_point startTime,
                                           bool ignoreErrors,
                                           size_t autoRetryCount,
                                           std::chrono::seconds autoRetryDelay,
                                           BatchErrorHandling batchErrorHandling) :
    jobName_(std::move(jobName)),
    startTime_(startTime),
    ignoreErrors_(ignoreErrors),
    autoRetryCount_(autoRetryCount),
    autoRetryDelay_(autoRetryDelay),
    batchErrorHandling_(batchErrorHandling)
{
    tty_ = ::isatty(STDERR_FILENO);
    if (!tty_)
        lastProgressHadNewline_ = true; //progress rendering is disabled
}


void ConsoleStatusHandler::forceUiUpdateNoThrow() //noexcept
{
    try
    {
        printProgress();
    }
    catch (...) {}
}


void ConsoleStatusHandler::printProgress()
{
    if (!tty_) //cron/syslog: don't spam a line every 50 ms
        return;

    const ProgressStats cur = getCurrentStats();
    const ProgressStats tot = getTotalStats();

    std::wstring line = L"[" + phaseLabel(currentPhase()) + L"] ";
    if (tot.items > 0)
        line += formatNumber(cur.items) + L"/" + formatNumber(tot.items) + L" items";
    else
        line += formatNumber(cur.items) + L" items";

    if (tot.bytes > 0)
        line += L", " + formatFilesizeShort(cur.bytes) + L"/" + formatFilesizeShort(tot.bytes);
    else if (cur.bytes > 0)
        line += L", " + formatFilesizeShort(cur.bytes);

    if (!currentStatusText().empty())
        line += L" - " + currentStatusText();

    if (!lastProgressHadNewline_)
        std::cerr << '\r';
    std::cerr << toUtf8(line) << "     " << std::flush;
    lastProgressHadNewline_ = false;
}


ConsoleStatusHandler::Result ConsoleStatusHandler::prepareResult()
{
    if (!lastProgressHadNewline_)
    {
        std::cerr << '\n';
        lastProgressHadNewline_ = true;
    }

    if (const ErrorLog extraLog = fetchExtraLog();
        !extraLog.empty())
    {
        append(errorLog_.ref(), extraLog);
        std::stable_sort(errorLog_.ref().begin(), errorLog_.ref().end(),
                         [](const LogEntry& lhs, const LogEntry& rhs) { return lhs.time < rhs.time; });
    }

    const TaskResult result = [&]
    {
        if (taskCancelled())
        {
            logMsg(errorLog_.ref(), _("Stopped"), MSG_TYPE_ERROR);
            return TaskResult::cancelled;
        }
        const ErrorLogStats logCount = getStats(errorLog_.ref());
        if (logCount.errors > 0)
            return TaskResult::error;
        if (logCount.warnings > 0)
            return TaskResult::warning;

        if (getTotalStats() == ProgressStats())
            logMsg(errorLog_.ref(), _("Nothing to synchronize"), MSG_TYPE_INFO);
        return TaskResult::success;
    }();

    //Keep the same shape as the GUI summary. The CLI has no pause feature, so
    //the wall-clock elapsed time is good enough.
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now() - startTime_);

    return {ProcessSummary{startTime_, result, {jobName_}, getCurrentStats(), getTotalStats(), elapsed}, errorLog_};
}


void ConsoleStatusHandler::logMessage(const std::wstring& msg, MsgType type)
{
    if (!lastProgressHadNewline_)
    {
        std::cerr << '\n';
        lastProgressHadNewline_ = true;
    }

    const MessageType msgType = [&]
    {
        switch (type)
        {
            case MsgType::info:    return MSG_TYPE_INFO;
            case MsgType::warning: return MSG_TYPE_WARNING;
            case MsgType::error:   return MSG_TYPE_ERROR;
        }
        return MSG_TYPE_ERROR;
    }();

    logMsg(errorLog_.ref(), msg, msgType);

    if (type != MsgType::info || tty_) //only warnings/errors in cron logs
    {
        const char* prefix = (type == MsgType::error) ? "error: " : (type == MsgType::warning) ? "warning: " : "info: ";
        writeErrLine(std::string("[FreeFileSync] ") + prefix + toUtf8(msg));
    }

    requestUiUpdate(false); //throw CancelProcess
}


void ConsoleStatusHandler::reportWarning(const std::wstring& msg, bool& warningActive)
{
    if (!lastProgressHadNewline_)
    {
        std::cerr << '\n';
        lastProgressHadNewline_ = true;
    }

    logMsg(errorLog_.ref(), msg, MSG_TYPE_WARNING);
    writeErrLine("[FreeFileSync] warning: " + toUtf8(msg));

    if (!warningActive)
        return;

    //No interactive warning dialog in headless mode. "Cancel on error" is the
    //only policy that needs to act here; warnings otherwise stay warnings.
    if (!ignoreErrors_ && batchErrorHandling_ == BatchErrorHandling::cancel)
        cancelProcessNow(CancelReason::firstError); //throw CancelProcess
}


ProcessCallback::Response ConsoleStatusHandler::reportError(const ErrorInfo& errorInfo)
{
    if (!lastProgressHadNewline_)
    {
        std::cerr << '\n';
        lastProgressHadNewline_ = true;
    }

    const time_t failTime = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now() -
        std::chrono::duration_cast<std::chrono::system_clock::duration>(std::chrono::steady_clock::now() - errorInfo.failTime));

    if (errorInfo.retryNumber < autoRetryCount_)
    {
        logMsg(errorLog_.ref(), errorInfo.msg + L"\n-> " + _("Automatic retry"), MSG_TYPE_INFO, failTime);
        writeErrLine("[FreeFileSync] info: " + toUtf8(errorInfo.msg) + " -> automatic retry " +
                     numberTo<std::string>(errorInfo.retryNumber + 1));

        delayAndCountDown(errorInfo.failTime + autoRetryDelay_ - std::chrono::steady_clock::now(),
                          [&](const std::wstring& timeRemMsg)
        {
            updateStatus(_("Automatic retry") +
                         (errorInfo.retryNumber == 0 ? L"" : L' ' + formatNumber(errorInfo.retryNumber + 1)) +
                         SPACED_DASH + timeRemMsg + SPACED_DASH + _("Error") + L": " +
                         replaceCpy(errorInfo.msg, L'\n', L' ')); //throw CancelProcess
        });
        return ProcessCallback::retry;
    }

    logMsg(errorLog_.ref(), errorInfo.msg, MSG_TYPE_ERROR, failTime);
    writeErrLine("[FreeFileSync] error: " + toUtf8(errorInfo.msg));

    if (!ignoreErrors_ && batchErrorHandling_ == BatchErrorHandling::cancel)
        cancelProcessNow(CancelReason::firstError); //throw CancelProcess

    //Headless "show popup" is mapped to "ignore and continue"; the error is
    //still counted and reflected in the exit code/log file.
    return ProcessCallback::ignore;
}


void ConsoleStatusHandler::reportFatalError(const std::wstring& msg)
{
    if (!lastProgressHadNewline_)
    {
        std::cerr << '\n';
        lastProgressHadNewline_ = true;
    }

    logMsg(errorLog_.ref(), msg, MSG_TYPE_ERROR);
    writeErrLine("[FreeFileSync] fatal: " + toUtf8(msg));

    if (!ignoreErrors_ && batchErrorHandling_ == BatchErrorHandling::cancel)
        cancelProcessNow(CancelReason::firstError); //throw CancelProcess
}


Statistics::ErrorStats ConsoleStatusHandler::getErrorStats() const
{
    for (const LogEntry& entry : std::span(errorLog_.ref().begin() + errorStatsRowsChecked_, errorLog_.ref().end()))
        switch (entry.type)
        {
            case MSG_TYPE_INFO:
                break;
            case MSG_TYPE_WARNING:
                ++errorStatsBuf_.warningCount;
                break;
            case MSG_TYPE_ERROR:
                ++errorStatsBuf_.errorCount;
                break;
        }
    errorStatsRowsChecked_ = errorLog_.ref().size();

    return errorStatsBuf_;
}
