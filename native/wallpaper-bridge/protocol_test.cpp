#include "protocol.h"
#include <cassert>
int main() {
    GlassFrame frame;
    assert(!frame.valid());
    frame.width = 1920; frame.height = 1080; frame.stride = 7680; frame.format = 0x34325241;
    assert(frame.valid());
    frame.slot = 3; assert(!frame.valid()); frame.slot = 0;
    frame.stride = 16; assert(!frame.valid()); frame.stride = 7680;
    frame.width = UINT32_MAX; assert(!frame.valid());
    auto address = glassAddress("DP-1");
    assert(address.sun_family == AF_UNIX && address.sun_path[0] == 0 && address.sun_path[1] != 0);
    int pair[2]; assert(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair) == 0);
    assert(glassPeerIsUser(pair[0])); close(pair[0]); close(pair[1]);
}
