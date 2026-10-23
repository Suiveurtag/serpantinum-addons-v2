#pragma once
#include <cstdint>
#include <cstring>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

struct GlassFrame {
    uint32_t magic = 0x53475055, version = 1;
    uint32_t width = 0, height = 0, stride = 0, offset = 0;
    uint32_t format = 0, slot = 0;
    uint64_t serial = 0, modifier = 0;
    bool valid() const {
        return magic == 0x53475055 && version == 1 && width > 0 && height > 0 &&
            width <= 16384 && height <= 16384 && stride >= width * 4 && slot < 3 &&
            format == 0x34325241;
    }
};
static_assert(sizeof(GlassFrame) == 48);

inline sockaddr_un glassAddress(const char* output) {
    sockaddr_un address {};
    address.sun_family = AF_UNIX;
    // Abstract sockets disappear with their owning process. The UID isolates users.
    std::string name = "serpantinum.glass." + std::to_string(getuid()) + "." + output;
    if (name.size() >= sizeof(address.sun_path) - 1) return address;
    std::memcpy(address.sun_path + 1, name.data(), name.size());
    return address;
}

inline bool glassPeerIsUser(int fd) {
    ucred peer {}; socklen_t length = sizeof(peer);
    return getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &peer, &length) == 0 && peer.uid == getuid();
}
