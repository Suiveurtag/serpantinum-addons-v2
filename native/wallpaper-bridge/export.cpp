#include "protocol.h"
#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <gbm.h>
#include <array>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <vector>

namespace {
struct Slot { gbm_bo* bo = nullptr; EGLImage image = EGL_NO_IMAGE; GLuint texture = 0; bool retired = false; };
struct Client { int fd; int slot = -1; uint64_t serial = 0; std::chrono::steady_clock::time_point sent; };
struct Exporter {
    int listener = -1, deviceFd = -1;
    gbm_device* device = nullptr;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    std::array<Slot, 3> slots {};
    std::vector<Client> clients;
    uint32_t width = 0, height = 0;
    uint64_t serial = 0;
    bool failed = false;
    GlassFrame latest;
    int latestSlot = -1;
    uint64_t sourceGeneration = 0, copiedGeneration = 0;
    uint32_t sourceWidth = 0, sourceHeight = 0, sourceFormat = 0, planeCount = 0;
    uint64_t sourceModifier = 0;
    std::array<int, 4> sourceFds {-1,-1,-1,-1};
    std::array<uint32_t, 4> sourceStrides {}, sourceOffsets {};

    explicit Exporter(const char* output) {
        listener = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        auto address = glassAddress(output);
        if (listener < 0 || bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) || listen(listener, 16))
            failed = true;
    }
    void clearPool() {
        for (auto& slot : slots) {
            if (slot.texture) glDeleteTextures(1, &slot.texture);
            if (slot.image != EGL_NO_IMAGE) eglDestroyImage(display, slot.image);
            if (slot.bo) gbm_bo_destroy(slot.bo);
            slot = {};
        }
        width = height = 0; latestSlot = -1;
    }
    ~Exporter() {
        for (int fd : sourceFds) if (fd >= 0) close(fd);
        for (auto& client : clients) close(client.fd);
        if (context != EGL_NO_CONTEXT) {
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context);
            clearPool();
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            eglDestroyContext(display, context); eglTerminate(display);
        }
        if (device) gbm_device_destroy(device);
        if (deviceFd >= 0) close(deviceFd);
        if (listener >= 0) close(listener);
    }
    bool init() {
        if (context != EGL_NO_CONTEXT) return eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context);
        const char* node = std::getenv("SERPANTINUM_DRM_DEVICE");
        if (!node) return false;
        deviceFd = open(node, O_RDWR | O_CLOEXEC);
        if (deviceFd < 0 || !(device = gbm_create_device(deviceFd))) return false;
        display = eglGetPlatformDisplayEXT(EGL_PLATFORM_GBM_KHR, device, nullptr);
        if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr) || !eglBindAPI(EGL_OPENGL_API)) return false;
        EGLConfig config; EGLint count;
        const EGLint attributes[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_SURFACE_TYPE, 0, EGL_NONE };
        if (!eglChooseConfig(display, attributes, &config, 1, &count) || !count) return false;
        context = eglCreateContext(display, config, EGL_NO_CONTEXT, nullptr);
        return context != EGL_NO_CONTEXT && eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context);
    }
    void service() {
        for (;;) {
            int fd = accept4(listener, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
            if (fd < 0) break;
            if (clients.size() >= 32 || !glassPeerIsUser(fd)) close(fd);
            else clients.push_back({fd});
        }
        std::erase_if(clients, [this](Client& client) {
            uint64_t ack; auto result = recv(client.fd, &ack, sizeof(ack), MSG_DONTWAIT);
            if (result == sizeof(ack) && ack == client.serial) client.slot = -1;
            const bool dead = result == 0 || (result < 0 && errno != EAGAIN && errno != EWOULDBLOCK);
            const bool stalled = client.slot >= 0 && std::chrono::steady_clock::now() - client.sent > std::chrono::seconds(2);
            if (dead || stalled) {
                if (client.slot >= 0) slots[client.slot].retired = true;
                close(client.fd); return true;
            }
            return false;
        });
    }
    void sendLatest() {
        if (latestSlot < 0) return;
        auto& packet = latest;
        const auto index = latestSlot;
        int fd = gbm_bo_get_fd(slots[index].bo);
        for (auto& client : clients) if (client.slot < 0 && client.serial != packet.serial) {
            char ancillary[CMSG_SPACE(sizeof(int))] {}; iovec data { &packet, sizeof(packet) }; msghdr msg {};
            msg.msg_iov = &data; msg.msg_iovlen = 1; msg.msg_control = ancillary; msg.msg_controllen = sizeof(ancillary);
            auto* cmsg = CMSG_FIRSTHDR(&msg); cmsg->cmsg_level = SOL_SOCKET; cmsg->cmsg_type = SCM_RIGHTS; cmsg->cmsg_len = CMSG_LEN(sizeof(int));
            std::memcpy(CMSG_DATA(cmsg), &fd, sizeof(fd));
            if (sendmsg(client.fd, &msg, MSG_NOSIGNAL | MSG_DONTWAIT) == sizeof(packet)) {
                client.slot = index; client.serial = packet.serial; client.sent = std::chrono::steady_clock::now();
            }
        }
        close(fd);
    }
    void poll() {
        if (failed) return;
        service();
        if (planeCount && sourceGeneration != copiedGeneration &&
            std::any_of(clients.begin(), clients.end(), [](auto& c) { return c.slot < 0; })) {
            frame(sourceWidth, sourceHeight, sourceFormat, sourceModifier, planeCount,
                  sourceFds.data(), sourceStrides.data(), sourceOffsets.data(), false);
        } else sendLatest();
    }
    void frame(uint32_t w, uint32_t h, uint32_t format, uint64_t modifier, uint32_t n,
               const int* fds, const uint32_t* strides, const uint32_t* offsets, bool remember = true) {
        if (failed || !n || n > 4) return;
        if (remember) {
            std::array<int, 4> retained {-1,-1,-1,-1};
            for (uint32_t i = 0; i < n; ++i) {
                retained[i] = fcntl(fds[i], F_DUPFD_CLOEXEC, 0);
                if (retained[i] < 0) { for (int fd : retained) if (fd >= 0) close(fd); return; }
            }
            for (int fd : sourceFds) if (fd >= 0) close(fd);
            sourceFds = retained; planeCount = n; sourceWidth = w; sourceHeight = h;
            sourceFormat = format; sourceModifier = modifier;
            std::copy_n(strides, n, sourceStrides.begin()); std::copy_n(offsets, n, sourceOffsets.begin());
            ++sourceGeneration;
        }
        service();
        if (clients.empty()) {
            return;
        }
        if (std::none_of(clients.begin(), clients.end(), [](auto& c) { return c.slot < 0; })) return;
        if (!init()) { std::fprintf(stderr, "Serpantinum glass: EGL initialization failed\n"); failed = true; return; }
        if (width != w || height != h) {
            if (std::any_of(clients.begin(), clients.end(), [](auto& c) { return c.slot >= 0; })) return;
            clearPool(); width = w; height = h;
        }
        int index = -1;
        for (int i = 0; i < 3; ++i)
            if (std::none_of(clients.begin(), clients.end(), [i](auto& c) { return c.slot == i; })) { index = i; break; }
        if (index < 0 || n == 0 || n > 4) return;
        auto& slot = slots[index];
        // A disconnected/late reader may still hold the old FD. Retire its allocation.
        if (slot.retired) {
            if (slot.texture) glDeleteTextures(1, &slot.texture);
            if (slot.image != EGL_NO_IMAGE) eglDestroyImage(display, slot.image);
            if (slot.bo) gbm_bo_destroy(slot.bo);
            slot = {};
        }
        if (!slot.bo) {
            slot.bo = gbm_bo_create(device, w, h, GBM_FORMAT_ARGB8888, GBM_BO_USE_RENDERING | GBM_BO_USE_LINEAR);
            if (!slot.bo) { failed = true; return; }
            int fd = gbm_bo_get_fd(slot.bo);
            const EGLAttrib attrs[] = { EGL_WIDTH, w, EGL_HEIGHT, h, EGL_LINUX_DRM_FOURCC_EXT, GBM_FORMAT_ARGB8888,
                EGL_DMA_BUF_PLANE0_FD_EXT, fd, EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0,
                EGL_DMA_BUF_PLANE0_PITCH_EXT, gbm_bo_get_stride(slot.bo), EGL_NONE };
            slot.image = eglCreateImage(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs); close(fd);
            if (slot.image == EGL_NO_IMAGE) { failed = true; return; }
            glGenTextures(1, &slot.texture); glBindTexture(GL_TEXTURE_2D, slot.texture);
            glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, slot.image);
        }
        std::vector<EGLAttrib> attrs { EGL_WIDTH, w, EGL_HEIGHT, h, EGL_LINUX_DRM_FOURCC_EXT, format };
        const int fdAttr[] = {EGL_DMA_BUF_PLANE0_FD_EXT, EGL_DMA_BUF_PLANE1_FD_EXT, EGL_DMA_BUF_PLANE2_FD_EXT, EGL_DMA_BUF_PLANE3_FD_EXT};
        const int offsetAttr[] = {EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGL_DMA_BUF_PLANE1_OFFSET_EXT, EGL_DMA_BUF_PLANE2_OFFSET_EXT, EGL_DMA_BUF_PLANE3_OFFSET_EXT};
        const int pitchAttr[] = {EGL_DMA_BUF_PLANE0_PITCH_EXT, EGL_DMA_BUF_PLANE1_PITCH_EXT, EGL_DMA_BUF_PLANE2_PITCH_EXT, EGL_DMA_BUF_PLANE3_PITCH_EXT};
        const int loAttr[] = {EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT};
        const int hiAttr[] = {EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT};
        for (uint32_t i = 0; i < n; ++i) {
            attrs.insert(attrs.end(), {fdAttr[i], fds[i], offsetAttr[i], offsets[i], pitchAttr[i], strides[i]});
            if (modifier != UINT64_MAX) attrs.insert(attrs.end(), {loAttr[i], uint32_t(modifier), hiAttr[i], uint32_t(modifier >> 32)});
        }
        attrs.push_back(EGL_NONE);
        EGLImage source = eglCreateImage(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs.data());
        if (source == EGL_NO_IMAGE) { std::fprintf(stderr, "Serpantinum glass: DMA-BUF import failed %x\n", eglGetError()); failed = true; return; }
        GLuint texture, fb[2]; glGenTextures(1, &texture); glBindTexture(GL_TEXTURE_2D, texture);
        glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, source); glGenFramebuffers(2, fb);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, fb[0]); glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fb[1]); glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, slot.texture, 0);
        bool valid = glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE && glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
        if (valid) { glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST); glFinish(); valid = glGetError() == GL_NO_ERROR; }
        glDeleteFramebuffers(2, fb); glDeleteTextures(1, &texture); eglDestroyImage(display, source);
        if (!valid) { failed = true; std::fprintf(stderr, "Serpantinum glass: GPU copy failed\n"); return; }
        GlassFrame packet; packet.width = w; packet.height = h; packet.stride = gbm_bo_get_stride(slot.bo);
        packet.format = GBM_FORMAT_ARGB8888; packet.slot = index; packet.serial = ++serial; packet.modifier = gbm_bo_get_modifier(slot.bo);
        latest = packet; latestSlot = index; copiedGeneration = sourceGeneration;
        sendLatest();
    }
};
}
extern "C" void* glass_create(const char* output) { return new Exporter(output); }
extern "C" void glass_destroy(void* exporter) { delete static_cast<Exporter*>(exporter); }
extern "C" void glass_frame(void* exporter, uint32_t w, uint32_t h, uint32_t format, uint64_t modifier,
    uint32_t n, const int* fds, const uint32_t* strides, const uint32_t* offsets) {
    static_cast<Exporter*>(exporter)->frame(w, h, format, modifier, n, fds, strides, offsets);
}

extern "C" void glass_poll(void* exporter) { static_cast<Exporter*>(exporter)->poll(); }
