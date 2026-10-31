// Headless .ffs_batch reader.
//
// This is a trimmed copy of the configuration parsing code from upstream
// FreeFileSync (config.cpp). The original file also handles global/GUI settings,
// layout data and wxWidgets types; a headless build only needs the batch/job
// part, so the XML readers are kept here without the GUI dependencies.
//
// Original code: Copyright (C) Zenju (zenju AT freefilesync DOT org)
// License: GNU General Public License v3 (same as FreeFileSync)

#include "ffs_batch_config.h"

#include <algorithm>
#include <zenxml/xml.h>
#include <zen/file_access.h>
#include <zen/stl_tools.h>
#include <zen/string_tools.h>
#include <zen/time.h>

using namespace zen;
using namespace fff;

namespace
{
const int XML_FORMAT_SYNC_CFG = 23; //2023-08-24


std::vector<unsigned int> fromTimeShiftPhrase(std::wstring_view timeShiftPhrase)
{
    std::vector<unsigned int> minutes;

    split2(timeShiftPhrase, [](wchar_t c) { return c == L',' || c == L';' || c == L' '; },
    [&minutes](const std::wstring_view block)
    {
        if (!block.empty())
        {
            std::wstring part(block);
            replace(part, L'-', L""); //there is no negative shift => treat as positive!

            const unsigned int timeShift = stringTo<unsigned int>(beforeFirst(part, L':', IfNotFoundReturn::all)) * 60 +
                                           stringTo<unsigned int>(afterFirst (part, L':', IfNotFoundReturn::none));
            if (timeShift > 0)
                minutes.push_back(timeShift);
        }
    });
    removeDuplicates(minutes);
    return minutes;
}


Zstring mergeFilterLines(const std::vector<Zstring>& filterLines)
{
    Zstring filterPhrase;
    for (const Zstring& line : filterLines)
        if (!trimCpy(line).empty())
            filterPhrase += line + Zstr('\n');
    return trimCpy(filterPhrase);
}
}


//################################################################################################
// enum <-> XML text (subset of the specializations in upstream config.cpp)

namespace zen
{
template <> inline
void writeText(const CompareVariant& value, std::string& output)
{
    switch (value)
    {
        case CompareVariant::timeSize: output = "TimeAndSize"; break;
        case CompareVariant::content:  output = "Content";     break;
        case CompareVariant::size:     output = "Size";        break;
    }
}

template <> inline
bool readText(const std::string& input, CompareVariant& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "TimeAndSize") value = CompareVariant::timeSize;
    else if (tmp == "Content")     value = CompareVariant::content;
    else if (tmp == "Size")        value = CompareVariant::size;
    else return false;
    return true;
}


template <> inline
void writeText(const SymLinkHandling& value, std::string& output)
{
    switch (value)
    {
        case SymLinkHandling::exclude: output = "Exclude"; break;
        case SymLinkHandling::asLink:  output = "Direct";  break;
        case SymLinkHandling::follow:  output = "Follow";  break;
    }
}

template <> inline
bool readText(const std::string& input, SymLinkHandling& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "Exclude") value = SymLinkHandling::exclude;
    else if (tmp == "Direct")  value = SymLinkHandling::asLink;
    else if (tmp == "Follow")  value = SymLinkHandling::follow;
    else return false;
    return true;
}


template <> inline
void writeText(const SyncDirection& value, std::string& output)
{
    switch (value)
    {
        case SyncDirection::left:  output = "left";  break;
        case SyncDirection::right: output = "right"; break;
        case SyncDirection::none:  output = "none";  break;
    }
}

template <> inline
bool readText(const std::string& input, SyncDirection& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "left")  value = SyncDirection::left;
    else if (tmp == "right") value = SyncDirection::right;
    else if (tmp == "none")  value = SyncDirection::none;
    else return false;
    return true;
}


template <> inline
void writeText(const DeletionVariant& value, std::string& output)
{
    switch (value)
    {
        case DeletionVariant::permanent:  output = "Permanent";  break;
        case DeletionVariant::recycler:   output = "RecycleBin"; break;
        case DeletionVariant::versioning: output = "Versioning"; break;
    }
}

template <> inline
bool readText(const std::string& input, DeletionVariant& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "Permanent")  value = DeletionVariant::permanent;
    else if (tmp == "RecycleBin") value = DeletionVariant::recycler;
    else if (tmp == "Versioning") value = DeletionVariant::versioning;
    else return false;
    return true;
}


template <> inline
void writeText(const VersioningStyle& value, std::string& output)
{
    switch (value)
    {
        case VersioningStyle::replace:         output = "Replace";          break;
        case VersioningStyle::timestampFolder: output = "TimeStamp-Folder"; break;
        case VersioningStyle::timestampFile:   output = "TimeStamp-File";   break;
    }
}

template <> inline
bool readText(const std::string& input, VersioningStyle& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "Replace")          value = VersioningStyle::replace;
    else if (tmp == "TimeStamp-Folder") value = VersioningStyle::timestampFolder;
    else if (tmp == "TimeStamp-File")   value = VersioningStyle::timestampFile;
    else return false;
    return true;
}


template <> inline
void writeText(const UnitSize& value, std::string& output)
{
    switch (value)
    {
        case UnitSize::none: output = "None"; break;
        case UnitSize::byte: output = "Byte"; break;
        case UnitSize::kb:   output = "KB";   break;
        case UnitSize::mb:   output = "MB";   break;
    }
}

template <> inline
bool readText(const std::string& input, UnitSize& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "None") value = UnitSize::none;
    else if (tmp == "Byte") value = UnitSize::byte;
    else if (tmp == "KB")   value = UnitSize::kb;
    else if (tmp == "MB")   value = UnitSize::mb;
    else return false;
    return true;
}


template <> inline
void writeText(const UnitTime& value, std::string& output)
{
    switch (value)
    {
        case UnitTime::none:      output = "None";   break;
        case UnitTime::today:     output = "Today";  break;
        case UnitTime::thisMonth: output = "Month";  break;
        case UnitTime::thisYear:  output = "Year";   break;
        case UnitTime::lastDays:  output = "x-days"; break;
    }
}

template <> inline
bool readText(const std::string& input, UnitTime& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "None")   value = UnitTime::none;
    else if (tmp == "Today")  value = UnitTime::today;
    else if (tmp == "Month")  value = UnitTime::thisMonth;
    else if (tmp == "Year")   value = UnitTime::thisYear;
    else if (tmp == "x-days") value = UnitTime::lastDays;
    else return false;
    return true;
}


template <> inline
void writeText(const PostSyncCondition& value, std::string& output)
{
    switch (value)
    {
        case PostSyncCondition::completion: output = "Completion"; break;
        case PostSyncCondition::errors:     output = "Errors";     break;
        case PostSyncCondition::success:    output = "Success";    break;
    }
}

template <> inline
bool readText(const std::string& input, PostSyncCondition& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "Completion") value = PostSyncCondition::completion;
    else if (tmp == "Errors")     value = PostSyncCondition::errors;
    else if (tmp == "Success")    value = PostSyncCondition::success;
    else return false;
    return true;
}


template <> inline
void writeText(const ResultsNotification& value, std::string& output)
{
    switch (value)
    {
        case ResultsNotification::always:       output = "Always";       break;
        case ResultsNotification::errorWarning: output = "ErrorWarning"; break;
        case ResultsNotification::errorOnly:    output = "ErrorOnly";    break;
    }
}

template <> inline
bool readText(const std::string& input, ResultsNotification& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "Always")       value = ResultsNotification::always;
    else if (tmp == "ErrorWarning") value = ResultsNotification::errorWarning;
    else if (tmp == "ErrorOnly")    value = ResultsNotification::errorOnly;
    else return false;
    return true;
}


template <> inline
void writeText(const BatchErrorHandling& value, std::string& output)
{
    switch (value)
    {
        case BatchErrorHandling::showPopup: output = "Show";   break;
        case BatchErrorHandling::cancel:    output = "Cancel"; break;
    }
}

template <> inline
bool readText(const std::string& input, BatchErrorHandling& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "Show")   value = BatchErrorHandling::showPopup;
    else if (tmp == "Cancel") value = BatchErrorHandling::cancel;
    else return false;
    return true;
}


template <> inline
void writeText(const PostBatchAction& value, std::string& output)
{
    switch (value)
    {
        case PostBatchAction::none:     output = "None";     break;
        case PostBatchAction::sleep:    output = "Sleep";    break;
        case PostBatchAction::shutdown: output = "Shutdown"; break;
    }
}

template <> inline
bool readText(const std::string& input, PostBatchAction& value)
{
    const std::string tmp = trimCpy(input);
    if      (tmp == "None")     value = PostBatchAction::none;
    else if (tmp == "Sleep")    value = PostBatchAction::sleep;
    else if (tmp == "Shutdown") value = PostBatchAction::shutdown;
    else return false;
    return true;
}
}


//################################################################################################
// XML readers

namespace
{
void readConfig(const XmlIn& in, CompConfig& cmpCfg)
{
    in["Variant" ](cmpCfg.compareVar);
    in["Symlinks"](cmpCfg.handleSymlinks);

    std::wstring timeShiftPhrase;
    if (in["IgnoreTimeShift"](timeShiftPhrase))
        cmpCfg.ignoreTimeShiftMinutes = fromTimeShiftPhrase(timeShiftPhrase);
}


void readConfig(const XmlIn& in, SyncDirectionConfig& dirCfg, int formatVer)
{
    if (formatVer < 21) //migration of old configs
    {
        std::string varName;
        in["Variant"](varName);
        trim(varName);

        if (varName == "TwoWay")
            dirCfg = getDefaultSyncCfg(SyncVariant::twoWay);
        else if (varName == "Mirror")
        {
            dirCfg = getDefaultSyncCfg(SyncVariant::mirror);

            bool detectMovedFiles = false;
            in["DetectMovedFiles"](detectMovedFiles);
            if (detectMovedFiles)
                if (const DirectionByDiff* diffDirs = std::get_if<DirectionByDiff>(&dirCfg.dirs))
                    dirCfg.dirs = getChangesDirDefault(*diffDirs);
        }
        else if (varName == "Update")
            dirCfg.dirs = DirectionByDiff
            {
                .leftOnly   = SyncDirection::right,
                .rightOnly  = SyncDirection::none,
                .leftNewer  = SyncDirection::right,
                .rightNewer = SyncDirection::none,
            };
        else
        {
            dirCfg.dirs = DirectionByDiff();

            XmlIn inCustDir = in["CustomDirections"];
            inCustDir["LeftOnly"  ](std::get<DirectionByDiff>(dirCfg.dirs).leftOnly);
            inCustDir["RightOnly" ](std::get<DirectionByDiff>(dirCfg.dirs).rightOnly);
            inCustDir["LeftNewer" ](std::get<DirectionByDiff>(dirCfg.dirs).leftNewer);
            inCustDir["RightNewer"](std::get<DirectionByDiff>(dirCfg.dirs).rightNewer);
        }
    }
    else
    {
        if (XmlIn inDirs = in["Differences"])
        {
            dirCfg.dirs = DirectionByDiff();
            inDirs.attribute("LeftOnly",   std::get<DirectionByDiff>(dirCfg.dirs).leftOnly);
            inDirs.attribute("LeftNewer",  std::get<DirectionByDiff>(dirCfg.dirs).leftNewer);
            inDirs.attribute("RightNewer", std::get<DirectionByDiff>(dirCfg.dirs).rightNewer);
            inDirs.attribute("RightOnly",  std::get<DirectionByDiff>(dirCfg.dirs).rightOnly);
        }
        else
        {
            dirCfg.dirs = DirectionByChange();

            XmlIn inDirsL = in["Changes"]["Left"];
            inDirsL.attribute("Create", std::get<DirectionByChange>(dirCfg.dirs).left.create);
            inDirsL.attribute("Update", std::get<DirectionByChange>(dirCfg.dirs).left.update);
            inDirsL.attribute("Delete", std::get<DirectionByChange>(dirCfg.dirs).left.delete_);

            XmlIn inDirsR = in["Changes"]["Right"];
            inDirsR.attribute("Create", std::get<DirectionByChange>(dirCfg.dirs).right.create);
            inDirsR.attribute("Update", std::get<DirectionByChange>(dirCfg.dirs).right.update);
            inDirsR.attribute("Delete", std::get<DirectionByChange>(dirCfg.dirs).right.delete_);
        }
    }
}


void readConfig(const XmlIn& in, SyncConfig& syncCfg, std::map<AfsDevice, size_t>& deviceParallelOps, int formatVer)
{
    readConfig(in, syncCfg.directionCfg, formatVer);

    in["DeletionPolicy"  ](syncCfg.deletionVariant);
    in["VersioningFolder"](syncCfg.versioningFolderPhrase);

    XmlIn verFolder = in["VersioningFolder"];

    size_t parallelOps = 1;
    if (verFolder.hasAttribute("Threads"))
        verFolder.attribute("Threads", parallelOps);

    const size_t parallelOpsPrev = getDeviceParallelOps(deviceParallelOps, syncCfg.versioningFolderPhrase);
    setDeviceParallelOps(deviceParallelOps, syncCfg.versioningFolderPhrase, std::max(parallelOps, parallelOpsPrev));

    in["VersioningFolder"].attribute("Style", syncCfg.versioningStyle);

    if (syncCfg.versioningStyle != VersioningStyle::replace)
    {
        if (verFolder.hasAttribute("MaxAge"))
            verFolder.attribute("MaxAge", syncCfg.versionMaxAgeDays);

        if (verFolder.hasAttribute("MinCount"))
            verFolder.attribute("MinCount", syncCfg.versionCountMin);
        if (verFolder.hasAttribute("MaxCount"))
            verFolder.attribute("MaxCount", syncCfg.versionCountMax);
    }
}


void readConfig(const XmlIn& in, FilterConfig& filter)
{
    std::vector<Zstring> tmpIn;
    if (in["Include"](tmpIn))
        filter.includeFilter = mergeFilterLines(tmpIn);

    std::vector<Zstring> tmpEx;
    if (in["Exclude"](tmpEx))
        filter.excludeFilter = mergeFilterLines(tmpEx);

    in["SizeMin"](filter.sizeMin);
    in["SizeMin"].attribute("Unit", filter.unitSizeMin);

    in["SizeMax"](filter.sizeMax);
    in["SizeMax"].attribute("Unit", filter.unitSizeMax);

    in["TimeSpan"](filter.timeSpan);
    in["TimeSpan"].attribute("Type", filter.unitTimeSpan);
}


void readConfig(const XmlIn& in, LocalPairConfig& lpc, std::map<AfsDevice, size_t>& deviceParallelOps, int formatVer)
{
    in["Left" ](lpc.folderPathPhraseLeft);
    in["Right"](lpc.folderPathPhraseRight);

    size_t parallelOpsL = 1;
    size_t parallelOpsR = 1;
    if (in["Left" ].hasAttribute("Threads")) in["Left" ].attribute("Threads", parallelOpsL);
    if (in["Right"].hasAttribute("Threads")) in["Right"].attribute("Threads", parallelOpsR);

    auto setParallelOps = [&](const Zstring& folderPathPhrase, size_t parallelOps)
    {
        const size_t parallelOpsPrev = getDeviceParallelOps(deviceParallelOps, folderPathPhrase);
        /**/                           setDeviceParallelOps(deviceParallelOps, folderPathPhrase, std::max(parallelOps, parallelOpsPrev));
    };
    setParallelOps(lpc.folderPathPhraseLeft,  parallelOpsL);
    setParallelOps(lpc.folderPathPhraseRight, parallelOpsR);

    if (XmlIn inLocalCmp = in["Compare"])
    {
        CompConfig cmpCfg;
        readConfig(inLocalCmp, cmpCfg);
        lpc.localCmpCfg = cmpCfg;
    }

    if (XmlIn inLocalSync = in["Synchronize"])
    {
        SyncConfig syncCfg;
        readConfig(inLocalSync, syncCfg, deviceParallelOps, formatVer);
        lpc.localSyncCfg = syncCfg;
    }

    if (XmlIn inLocFilter = in["Filter"])
        readConfig(inLocFilter, lpc.localFilter);
}


void readConfig(const XmlIn& in, MainConfiguration& mainCfg, int formatVer)
{
    readConfig(in["Compare"], mainCfg.cmpCfg);

    readConfig(in["Synchronize"], mainCfg.syncCfg, mainCfg.deviceParallelOps, formatVer);

    if (formatVer < 20) //migration
        if (mainCfg.cmpCfg.compareVar == CompareVariant::content ||
            mainCfg.cmpCfg.compareVar == CompareVariant::size)
            if (std::string varName;
                in["Synchronize"]["Variant"](varName))
            {
                if (varName == "Update")
                    std::get<DirectionByDiff>(mainCfg.syncCfg.directionCfg.dirs).rightNewer = SyncDirection::right;
                else if (varName == "Custom")
                {
                    SyncDirection different = SyncDirection::none;
                    in["Synchronize"]["CustomDirections"]["Different"](different);

                    std::get<DirectionByDiff>(mainCfg.syncCfg.directionCfg.dirs).leftNewer =
                        std::get<DirectionByDiff>(mainCfg.syncCfg.directionCfg.dirs).rightNewer = different;
                }
            }

    if (formatVer < 23) //migration
    {
        bool detectMovedFiles = false;
        in["Synchronize"]["DetectMovedFiles"](detectMovedFiles);
        if (detectMovedFiles)
            if (getSyncVariant(mainCfg.syncCfg.directionCfg) == SyncVariant::mirror)
            {
                if (const DirectionByDiff* diffDirs = std::get_if<DirectionByDiff>(&mainCfg.syncCfg.directionCfg.dirs))
                    mainCfg.syncCfg.directionCfg.dirs = getChangesDirDefault(*diffDirs);
            }
    }

    readConfig(in["Filter"], mainCfg.globalFilter);

    bool firstItem = true;
    in["FolderPairs"].visitChildren([&](const XmlIn& inPair)
    {
        LocalPairConfig lpc;
        readConfig(inPair, lpc, mainCfg.deviceParallelOps, formatVer);

        if (formatVer < 20) //migration
            if (lpc.localSyncCfg)
            {
                const CompConfig& cmpCfg = lpc.localCmpCfg ? *lpc.localCmpCfg : mainCfg.cmpCfg;
                if (cmpCfg.compareVar == CompareVariant::content ||
                    cmpCfg.compareVar == CompareVariant::size)
                    if (std::string varName;
                        inPair["Synchronize"]["Variant"](varName))
                    {
                        if (varName == "Update")
                            std::get<DirectionByDiff>(lpc.localSyncCfg->directionCfg.dirs).rightNewer = SyncDirection::right;
                        else if (varName == "Custom")
                            if (inPair["Synchronize"]["CustomDirections"]["Different"])
                            {
                                SyncDirection different = SyncDirection::none;
                                inPair["Synchronize"]["CustomDirections"]["Different"](different);

                                std::get<DirectionByDiff>(lpc.localSyncCfg->directionCfg.dirs).leftNewer =
                                    std::get<DirectionByDiff>(lpc.localSyncCfg->directionCfg.dirs).rightNewer = different;
                            }
                    }
            }
        if (formatVer < 23) //migration
            if (lpc.localSyncCfg)
            {
                bool detectMovedFiles = false;
                inPair["Synchronize"]["DetectMovedFiles"](detectMovedFiles);
                if (detectMovedFiles)
                    if (getSyncVariant(lpc.localSyncCfg->directionCfg) == SyncVariant::mirror)
                    {
                        if (const DirectionByDiff* diffDirs = std::get_if<DirectionByDiff>(&lpc.localSyncCfg->directionCfg.dirs))
                            lpc.localSyncCfg->directionCfg.dirs = getChangesDirDefault(*diffDirs);
                    }
            }

        if (firstItem)
        {
            firstItem = false;
            mainCfg.firstPair = lpc;
            mainCfg.additionalPairs.clear();
        }
        else
            mainCfg.additionalPairs.push_back(lpc);
    });

    in["Errors"].attribute("Ignore", mainCfg.ignoreErrors);
    in["Errors"].attribute("Retry",  mainCfg.autoRetryCount);
    in["Errors"].attribute("Delay",  mainCfg.autoRetryDelay);

    in["PostSyncCommand"](mainCfg.postSyncCommand);
    in["PostSyncCommand"].attribute("Condition", mainCfg.postSyncCondition);

    in["LogFolder"](mainCfg.altLogFolderPathPhrase);

    in["EmailNotification"](mainCfg.emailNotifyAddress);
    in["EmailNotification"].attribute("Condition", mainCfg.emailNotifyCondition);
}


void readConfig(const XmlIn& in, FfsGuiConfig& cfg, int formatVer)
{
    if (formatVer >= 18)
        in["Notes"](cfg.notes);

    readConfig(in, cfg.mainCfg, formatVer);
}


void readConfig(const XmlIn& in, FfsBatchConfig& cfg, int formatVer)
{
    if (formatVer < 19)
        readConfig(in, cfg.guiCfg.mainCfg, formatVer);
    else
        readConfig(in, cfg.guiCfg, formatVer);

    XmlIn inBatch = in["Batch"];
    inBatch["ProgressDialog"].attribute("Minimized", cfg.batchExCfg.runMinimized);
    inBatch["ProgressDialog"].attribute("AutoClose", cfg.batchExCfg.autoCloseSummary);
    inBatch["ErrorDialog"](cfg.batchExCfg.batchErrorHandling);
    inBatch["PostSyncAction"](cfg.batchExCfg.postBatchAction);
}
}


std::pair<FfsBatchConfig, std::wstring> fff::readBatchConfig(const Zstring& filePath)
{
    XmlDoc doc = loadXml(filePath); //throw FileError

    const std::string cfgType = [&]
    {
        if (doc.root().getName() == "FreeFileSync")
        {
            std::string type;
            if (doc.root().getAttribute("XmlType", type))
                return type;
        }
        return std::string();
    }();

    if (cfgType != "BATCH")
        throw FileError(replaceCpy(_("File %x does not contain a valid configuration."), L"%x", fmtPath(filePath)));

    int formatVer = 0;
    doc.root().getAttribute("XmlFormat", formatVer);

    XmlIn in(doc);
    FfsBatchConfig cfg;
    readConfig(in, cfg, formatVer);

    std::wstring warningMsg;
    if (const std::wstring& errors = in.getErrors();
        !errors.empty())
        warningMsg = replaceCpy(_("Configuration file %x is incomplete. The missing elements have been set to their default values."), L"%x", fmtPath(filePath)) + L"\n\n" +
                     _("The following XML elements could not be read:") + L'\n' + errors;

    return {cfg, warningMsg};
}
