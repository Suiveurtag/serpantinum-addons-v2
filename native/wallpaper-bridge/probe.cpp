#include "protocol.h"
#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <gbm.h>
#include <QImage>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <vector>

int main(int argc, char** argv) {
    if (argc != 3) { std::fprintf(stderr, "usage: glass-frame-probe OUTPUT IMAGE.png\n"); return 2; }
    const char* node = std::getenv("SERPANTINUM_DRM_DEVICE");
    if (!node) return 2;
    int deviceFd = open(node, O_RDWR | O_CLOEXEC);
    if (deviceFd < 0) return 3;
    auto* device = gbm_create_device(deviceFd);
    if (!device) return 3;
    auto display = eglGetPlatformDisplayEXT(EGL_PLATFORM_GBM_KHR, device, nullptr);
    if (!eglInitialize(display, nullptr, nullptr) || !eglBindAPI(EGL_OPENGL_API)) return 3;
    EGLConfig config; EGLint count;
    const EGLint configAttrs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_SURFACE_TYPE, 0, EGL_NONE};
    if (!eglChooseConfig(display, configAttrs, &config, 1, &count) || !count) return 3;
    auto context = eglCreateContext(display, config, EGL_NO_CONTEXT, nullptr);
    if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context)) return 3;
    int socketFd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    auto address = glassAddress(argv[1]);
    if (connect(socketFd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) || !glassPeerIsUser(socketFd)) return 4;
    timeval timeout {5, 0}; setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    GlassFrame packet; char control[CMSG_SPACE(sizeof(int))] {}; iovec data {&packet, sizeof(packet)}; msghdr msg {};
    msg.msg_iov = &data; msg.msg_iovlen = 1; msg.msg_control = control; msg.msg_controllen = sizeof(control);
    auto received = recvmsg(socketFd, &msg, MSG_CMSG_CLOEXEC);
    int fd = -1;
    auto* cmsg = CMSG_FIRSTHDR(&msg);
    if (cmsg && cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS) std::memcpy(&fd, CMSG_DATA(cmsg), sizeof(fd));
    if (received != sizeof(packet) || !packet.valid() || fd < 0 || (msg.msg_flags & (MSG_TRUNC | MSG_CTRUNC))) return 5;
    const EGLAttrib attrs[] = {EGL_WIDTH, packet.width, EGL_HEIGHT, packet.height, EGL_LINUX_DRM_FOURCC_EXT, packet.format,
        EGL_DMA_BUF_PLANE0_FD_EXT, fd, EGL_DMA_BUF_PLANE0_OFFSET_EXT, packet.offset, EGL_DMA_BUF_PLANE0_PITCH_EXT, packet.stride,
        EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, uint32_t(packet.modifier), EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, uint32_t(packet.modifier >> 32), EGL_NONE};
    auto image = eglCreateImage(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs);
    if (image == EGL_NO_IMAGE) return 6;
    GLuint texture, framebuffer; glGenTextures(1, &texture); glBindTexture(GL_TEXTURE_2D, texture);
    glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image); glGenFramebuffers(1, &framebuffer); glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) return 6;
    std::vector<uint8_t> pixels(size_t(packet.width)*packet.height*4);
    glReadPixels(0, 0, packet.width, packet.height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
    const bool saved = QImage(pixels.data(), packet.width, packet.height, packet.width*4, QImage::Format_RGBA8888).save(argv[2]);
    send(socketFd, &packet.serial, sizeof(packet.serial), MSG_NOSIGNAL); close(socketFd);
    glDeleteFramebuffers(1, &framebuffer); glDeleteTextures(1, &texture); eglDestroyImage(display, image); close(fd);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT); eglDestroyContext(display, context); eglTerminate(display); gbm_device_destroy(device); close(deviceFd);
    return saved ? 0 : 7;
}
