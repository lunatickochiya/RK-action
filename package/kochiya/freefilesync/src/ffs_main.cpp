// Headless FreeFileSync batch runner.
//
// FreeFileSync upstream is a wxWidgets/GTK GUI application. This entry point
// links the synchronization engine (comparison, synchronization, AFS backends)
// with a console StatusHandler so that .ffs_batch jobs can run on headless
// systems such as OpenWrt.

#include <cstring>
#include <iostream>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include <zen/error_log.h>
#include <zen/file_access.h>
#include <zen/file_path.h>
#include <zen/process_exec.h>
#include <zen/resolve_path.h>
#include <zen/scope_guard.h>
#include <zen/shutdown.h>
#include <zen/stl_tools.h>
#include <zen/sys_error.h>
#include <zen/time.h>

#include <afs/concrete.h>
#include <base/comparison.h>
#include <base/synchronization.h>
#include <ffs_paths.h>
#include <log_file.h>
#include <return_codes.h>
#include <status_handler.h>
#include <version/version.h>

#include "ffs_batch_config.h"
#include "ffs_console_handler.h"

using namespace zen;
using namespace fff;

namespace
{
const char CLI_VERSION[] = "1.0";

void printUsage(const char* argv0)
{
    std::cout << "FreeFileSync " << ffsVersion << " - headless batch runner " << CLI_VERSION << "\n"
        "\n"
        "Usage: " << argv0 << " [options] <job.ffs_batch>\n"
        "\n"
        "Options:\n"
        "  -c, --config <file>       job configuration (.ffs_batch)\n"
        "      --log-dir <dir>       override the log folder from the job/global config\n"
        "      --log-format <fmt>    html (default) or text\n"
        "      --no-log              do not write a log file\n"
        "      --continue-on-error   keep going after errors (same as config \"Ignore errors\")\n"
        "      --compare-only        run the comparison and print the result, do not synchronize\n"
        "      --version             print version\n"
        "  -h, --help                print this help\n"
        "\n"
        "Exit codes: 0 = success, 1 = warning, 2 = error, 3 = cancelled, 4 = exception\n";
}


Zstring getDefaultLogFolder()
{
    return appendPath(getConfigDirPath(), Zstr("Logs"));
}


std::wstring extractJobName(const Zstring& cfgFilePath)
{
    const Zstring fileName = getItemName(cfgFilePath);
    const Zstring jobName  = beforeLast(fileName, Zstr('.'), IfNotFoundReturn::all);
    return utfTo<std::wstring>(jobName);
}


void printSummary(const ProcessSummary& summary)
{
    std::cout << "\n";
    std::cout << "Result:    " << utfTo<std::string>(getSyncResultLabel(summary.result)) << "\n";
    if (summary.statsTotal.items >= 0)
        std::cout << "Items:     " << summary.statsProcessed.items << "/" << summary.statsTotal.items << "\n";
    else
        std::cout << "Items:     " << summary.statsProcessed.items << "\n";
    if (summary.statsTotal.bytes >= 0)
        std::cout << "Bytes:     " << summary.statsProcessed.bytes << "/" << summary.statsTotal.bytes << "\n";
    else
        std::cout << "Bytes:     " << summary.statsProcessed.bytes << "\n";
    std::cout << "Elapsed:   " << std::chrono::duration_cast<std::chrono::seconds>(summary.totalTime).count() << " s\n";
}


struct Options
{
    std::optional<Zstring> configPath;
    std::optional<Zstring> logDir;
    std::optional<LogFileFormat> logFormat;
    bool noLog = false;
    bool continueOnError = false;
    bool compareOnly = false;
};


bool parseArgs(int argc, char** argv, Options& opt)
{
    for (int i = 1; i < argc; ++i)
    {
        const std::string arg = argv[i];
        auto needValue = [&](const char* name) -> std::optional<std::string>
        {
            if (i + 1 >= argc)
            {
                std::cerr << "error: missing value for " << name << "\n";
                return std::nullopt;
            }
            return std::string(argv[++i]);
        };

        if (arg == "-h" || arg == "--help")
        {
            printUsage(argv[0]);
            std::exit(0);
        }
        else if (arg == "--version")
        {
            std::cout << "FreeFileSync " << ffsVersion << " (headless CLI " << CLI_VERSION << ")\n";
            std::exit(0);
        }
        else if (arg == "-c" || arg == "--config")
        {
            if (auto v = needValue(arg.c_str()))
                opt.configPath = Zstring(*v);
            else
                return false;
        }
        else if (arg == "--log-dir")
        {
            if (auto v = needValue(arg.c_str()))
                opt.logDir = Zstring(*v);
            else
                return false;
        }
        else if (arg == "--log-format")
        {
            auto v = needValue(arg.c_str());
            if (!v)
                return false;
            if (*v == "html" || *v == "HTML")
                opt.logFormat = LogFileFormat::html;
            else if (*v == "text" || *v == "Text")
                opt.logFormat = LogFileFormat::text;
            else
            {
                std::cerr << "error: unknown log format: " << *v << " (expected html or text)\n";
                return false;
            }
        }
        else if (arg == "--no-log")
            opt.noLog = true;
        else if (arg == "--continue-on-error")
            opt.continueOnError = true;
        else if (arg == "--compare-only")
            opt.compareOnly = true;
        else if (!arg.empty() && arg[0] == '-')
        {
            std::cerr << "error: unknown option: " << arg << "\n";
            return false;
        }
        else
        {
            if (opt.configPath)
            {
                std::cerr << "error: more than one job configuration given\n";
                return false;
            }
            opt.configPath = Zstring(arg);
        }
    }

    if (!opt.configPath)
    {
        std::cerr << "error: no .ffs_batch job configuration given\n\n";
        printUsage(argv[0]);
        return false;
    }
    return true;
}


int runJob(const Options& opt, FfsExitCode& exitCode)
{
    const Zstring& cfgPath = *opt.configPath;

    initAfs({Zstring(), getConfigDirPath()}); //empty resource dir => use libcurl's default CA store
    ZEN_ON_SCOPE_EXIT(teardownAfs());

    const auto [batchCfg, warningMsg] = readBatchConfig(cfgPath); //throw FileError

    if (!warningMsg.empty())
        std::cerr << "[FreeFileSync] warning: " << utfTo<std::string>(warningMsg) << "\n";

    MainConfiguration mainCfg = batchCfg.guiCfg.mainCfg;
    if (opt.continueOnError)
        mainCfg.ignoreErrors = true;

    if (AFS::isNullPath(createAbstractPath(mainCfg.firstPair.folderPathPhraseLeft)) ||
        AFS::isNullPath(createAbstractPath(mainCfg.firstPair.folderPathPhraseRight)))
        throw FileError(_("The job has no folder pair."));

    const std::chrono::system_clock::time_point startTime = std::chrono::system_clock::now();

    ConsoleStatusHandler statusHandler(extractJobName(cfgPath),
                                       startTime,
                                       mainCfg.ignoreErrors,
                                       mainCfg.autoRetryCount,
                                       mainCfg.autoRetryDelay,
                                       batchCfg.batchExCfg.batchErrorHandling);

    WarningDialogs warningDialogs;
    std::unique_ptr<LockHolder> dirLocks;

    AFS::RequestPasswordFun requestPassword; //headless: no interactive password prompt

    try
    {
        FolderComparison cmpResult = compare(warningDialogs,
                                             2 /*fileTimeTolerance*/,
                                             requestPassword,
                                             false /*runWithBackgroundPriority*/,
                                             true /*createLockFile*/,
                                             dirLocks,
                                             extractCompareCfg(mainCfg),
                                             statusHandler); //throw CancelProcess

        if (!cmpResult.empty() && !opt.compareOnly)
            synchronize(startTime,
                        false /*verifyFileCopy*/,
                        false /*copyLockedFiles*/,
                        false /*copyFilePermissions*/,
                        true /*failSafeFileCopy*/,
                        false /*runWithBackgroundPriority*/,
                        extractSyncCfg(mainCfg),
                        cmpResult,
                        warningDialogs,
                        statusHandler); //throw CancelProcess
    }
    catch (CancelProcess&) {}

    ConsoleStatusHandler::Result r = statusHandler.prepareResult();

    //------------------------------------------------------------------------
    // Log file (same naming/content as the GUI batch mode)
    //------------------------------------------------------------------------
    std::wstring logFilePath;
    if (!opt.noLog)
    {
        AbstractPath logFolderPath = opt.logDir ? createAbstractPath(*opt.logDir)
                                                : createAbstractPath(mainCfg.altLogFolderPathPhrase);
        if (AFS::isNullPath(logFolderPath))
            logFolderPath = createAbstractPath(getDefaultLogFolder());

        const LogFileFormat logFormat = opt.logFormat ? *opt.logFormat : LogFileFormat::html;
        const AbstractPath logFileAbstractPath = AFS::appendRelPath(logFolderPath, generateLogFileName(logFormat, r.summary));

        try
        {
            saveLogFile(logFileAbstractPath,
                        r.summary,
                        r.errorLog.ref(),
                        30 /*logfilesMaxAgeDays*/,
                        logFormat,
                        {} /*logsToKeepPaths*/,
                        [](std::wstring&&) {}); //throw FileError
            logFilePath = AFS::getDisplayPath(logFileAbstractPath);
        }
        catch (const FileError& e)
        {
            std::cerr << "[FreeFileSync] error: could not save log file: " << utfTo<std::string>(e.toString()) << "\n";
            raiseExitCode(exitCode, FfsExitCode::error);
        }
    }

    //------------------------------------------------------------------------
    // Post-sync command
    //------------------------------------------------------------------------
    if (!(statusHandler.taskCancelled() && *statusHandler.taskCancelled() == CancelReason::user))
        if (const Zstring cmdLine = trimCpy(expandMacros(mainCfg.postSyncCommand));
            !cmdLine.empty())
            if (mainCfg.postSyncCondition == PostSyncCondition::completion ||
                (mainCfg.postSyncCondition == PostSyncCondition::errors) == (r.summary.result == TaskResult::cancelled ||
                    r.summary.result == TaskResult::error))
                try
                {
                    if (const auto& [code, output] = consoleExecute(cmdLine, 100); //throw SysError, SysErrorTimeOut
                        code != 0)
                        throw SysError(formatSystemError("", replaceCpy(_("Exit code %x"), L"%x", numberTo<std::wstring>(code)),
                                                        utfTo<std::wstring>(output)));
                }
                catch (SysErrorTimeOut&)
                {
                    //Command still running after the short grace period: fine.
                }
                catch (const SysError& e)
                {
                    logMsg(r.errorLog.ref(), replaceCpy(_("Command %x failed."), L"%x", fmtPath(cmdLine)) + L"\n\n" + e.toString(), MSG_TYPE_ERROR);
                }

    printSummary(r.summary);
    if (!logFilePath.empty())
        std::cout << "Log file:  " << utfTo<std::string>(logFilePath) << "\n";

    switch (r.summary.result)
    {
        case TaskResult::success:   raiseExitCode(exitCode, FfsExitCode::success);   break;
        case TaskResult::warning:   raiseExitCode(exitCode, FfsExitCode::warning);   break;
        case TaskResult::error:     raiseExitCode(exitCode, FfsExitCode::error);     break;
        case TaskResult::cancelled: raiseExitCode(exitCode, FfsExitCode::cancelled); break;
    }

    const ErrorLogStats logCount = getStats(r.errorLog.ref());
    if (logCount.errors > 0)
        raiseExitCode(exitCode, FfsExitCode::error);
    else if (logCount.warnings > 0)
        raiseExitCode(exitCode, FfsExitCode::warning);

    return 0;
}
}


int main(int argc, char** argv)
{
    FfsExitCode exitCode = FfsExitCode::success;

    try
    {
        Options opt;
        if (!parseArgs(argc, argv, opt))
            return static_cast<int>(FfsExitCode::cancelled);

        runJob(opt, exitCode);
    }
    catch (const FileError& e)
    {
        std::cerr << "[FreeFileSync] error: " << utfTo<std::string>(e.toString()) << "\n";
        raiseExitCode(exitCode, FfsExitCode::error);
    }
    catch (const std::exception& e)
    {
        std::cerr << "[FreeFileSync] exception: " << e.what() << "\n";
        raiseExitCode(exitCode, FfsExitCode::exception);
    }

    return static_cast<int>(exitCode);
}
