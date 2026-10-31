// Minimal stand-in for FreeFileSync's wx+/image_holder.h used by the headless CLI.
// The real header pulls in GIO/Gtk icon handling and wxImage, neither of which is
// needed by the synchronization engine.
#pragma once

#include <memory>

namespace zen
{
struct ImageHolder
{
    int getWidth () const { return 0; }
    int getHeight() const { return 0; }
    unsigned char* getRgb  () { return nullptr; }
    unsigned char* getAlpha() { return nullptr; }
    explicit operator bool() const { return false; }
};

struct FileIconHolder
{
    explicit operator bool() const { return false; }
};
}
