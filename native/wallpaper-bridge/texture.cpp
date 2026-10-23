#include "texture.h"
#include "protocol.h"
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <QSGTextureProvider>
#include <QtQuick/qsgtexture_platform.h>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QSocketNotifier>
#include <QTimer>
#include <QMutex>
#include <QMutexLocker>
#include <QPointer>
#include <QRunnable>
#include <QDebug>
#include <atomic>
#include <EGL/egl.h>
#include <EGL/eglext.h>

class FrameStream : public QObject {
    Q_OBJECT
public:
    QQuickWindow* window;
    QString output;
    std::atomic<int> users = 0;
    bool available = false;
    explicit FrameStream(QQuickWindow* w, const QString& o) : QObject(w), window(w), output(o) {
        retry.setInterval(1000);
        connect(&retry, &QTimer::timeout, this, &FrameStream::open);
        connect(w, &QQuickWindow::sceneGraphInvalidated, this, [this] { clearTexture(); }, Qt::DirectConnection);
    }
    ~FrameStream() override { closeSocket(); }
    void retain() { if (++users == 1) { open(); if (socketFd < 0) retry.start(); } }
    void release() {
        if (--users == 0) {
            retry.stop(); closeSocket();
            window->scheduleRenderJob(QRunnable::create([this] { if (!users) clearTexture(); }), QQuickWindow::AfterRenderingStage);
        }
    }
    QSGTexture* texture() {
        QMutexLocker guard(&mutex);
        if (pendingFd < 0) return qtTexture;
        auto* context = QOpenGLContext::currentContext();
        if (!context || window->rendererInterface()->graphicsApi() != QSGRendererInterface::OpenGL) {
            qWarning() << "Serpantinum glass requires the OpenGL scene graph"; discard(); return nullptr;
        }
        auto* gl = context->extraFunctions();
        GLint oldTexture; gl->glGetIntegerv(GL_TEXTURE_BINDING_2D, &oldTexture);
        auto display = eglGetCurrentDisplay();
        const EGLAttrib attrs[] = { EGL_WIDTH, pending.width, EGL_HEIGHT, pending.height,
            EGL_LINUX_DRM_FOURCC_EXT, pending.format, EGL_DMA_BUF_PLANE0_FD_EXT, pendingFd,
            EGL_DMA_BUF_PLANE0_OFFSET_EXT, pending.offset, EGL_DMA_BUF_PLANE0_PITCH_EXT, pending.stride,
            EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, uint32_t(pending.modifier),
            EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, uint32_t(pending.modifier >> 32), EGL_NONE };
        EGLImage image = eglCreateImage(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs);
        if (image == EGL_NO_IMAGE) { qWarning() << "Serpantinum glass: EGL import failed" << eglGetError(); discard(); return nullptr; }
        if (size != QSize(pending.width, pending.height)) {
            clearTextureUnlocked(); size = QSize(pending.width, pending.height);
            gl->glGenTextures(1, &privateTexture); gl->glBindTexture(GL_TEXTURE_2D, privateTexture);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            gl->glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, size.width(), size.height(), 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
            qtTexture = QNativeInterface::QSGOpenGLTexture::fromNative(privateTexture, window, size);
        }
        GLuint imported, fbo[2]; gl->glGenTextures(1, &imported); gl->glBindTexture(GL_TEXTURE_2D, imported);
        auto targetImage = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(context->getProcAddress("glEGLImageTargetTexture2DOES"));
        if (!targetImage) { gl->glDeleteTextures(1, &imported); gl->glBindTexture(GL_TEXTURE_2D, oldTexture); eglDestroyImage(display, image); discard(); return nullptr; }
        targetImage(GL_TEXTURE_2D, image);
        gl->glGenFramebuffers(2, fbo);
        GLint oldRead, oldDraw; gl->glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &oldRead); gl->glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &oldDraw);
        gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo[0]); gl->glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, imported, 0);
        gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo[1]); gl->glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, privateTexture, 0);
        const bool scissor = gl->glIsEnabled(GL_SCISSOR_TEST);
        gl->glDisable(GL_SCISSOR_TEST);
        bool valid = gl->glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE && gl->glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
        if (valid) { gl->glBlitFramebuffer(0, 0, size.width(), size.height(), 0, 0, size.width(), size.height(), GL_COLOR_BUFFER_BIT, GL_NEAREST); gl->glFinish(); }
        if (scissor) gl->glEnable(GL_SCISSOR_TEST);
        gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, oldRead); gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, oldDraw);
        gl->glDeleteFramebuffers(2, fbo); gl->glDeleteTextures(1, &imported); eglDestroyImage(display, image);
        gl->glBindTexture(GL_TEXTURE_2D, oldTexture);
        discard();
        if (!valid) qWarning() << "Serpantinum glass: incomplete import framebuffer";
        return valid ? qtTexture : nullptr;
    }
signals:
    void frameAvailable();
private:
    QTimer retry;
    QSocketNotifier* notifier = nullptr;
    QMutex mutex;
    int socketFd = -1, pendingFd = -1;
    GlassFrame pending;
    GLuint privateTexture = 0;
    QSGTexture* qtTexture = nullptr;
    QSize size;
    void clearTextureUnlocked() {
        delete qtTexture; qtTexture = nullptr;
        if (privateTexture && QOpenGLContext::currentContext()) QOpenGLContext::currentContext()->extraFunctions()->glDeleteTextures(1, &privateTexture);
        privateTexture = 0; size = {};
    }
    void clearTexture() { QMutexLocker guard(&mutex); clearTextureUnlocked(); }
    void discard() {
        if (pendingFd >= 0) {
            close(pendingFd); pendingFd = -1;
            if (socketFd >= 0) send(socketFd, &pending.serial, sizeof(pending.serial), MSG_NOSIGNAL | MSG_DONTWAIT);
        }
    }
    void closeSocket() {
        delete notifier; notifier = nullptr;
        QMutexLocker guard(&mutex); discard();
        if (socketFd >= 0) close(socketFd);
        socketFd = -1; available = false;
        if (users) retry.start();
    }
    void open() {
        if (!users || socketFd >= 0) return;
        int fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
        auto name = output.toUtf8(); auto address = glassAddress(name.constData());
        if (fd < 0) return;
        if (::connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) || !glassPeerIsUser(fd)) { close(fd); return; }
        socketFd = fd;
        retry.stop();
        notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this, [this] {
            GlassFrame packet; char control[CMSG_SPACE(sizeof(int) * 4)] {}; iovec data { &packet, sizeof(packet) }; msghdr msg {};
            msg.msg_iov = &data; msg.msg_iovlen = 1; msg.msg_control = control; msg.msg_controllen = sizeof(control);
            auto result = recvmsg(socketFd, &msg, MSG_DONTWAIT | MSG_CMSG_CLOEXEC);
            if (result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
            int received = -1, count = 0;
            for (auto* cmsg = CMSG_FIRSTHDR(&msg); cmsg; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
                if (cmsg->cmsg_level != SOL_SOCKET || cmsg->cmsg_type != SCM_RIGHTS) continue;
                size_t n = (cmsg->cmsg_len - CMSG_LEN(0)) / sizeof(int);
                for (size_t i = 0; i < n; ++i) { int fd; std::memcpy(&fd, CMSG_DATA(cmsg) + i * sizeof(int), sizeof(fd)); if (++count == 1) received = fd; else close(fd); }
            }
            if (result != sizeof(packet) || count != 1 || !packet.valid() || (msg.msg_flags & (MSG_TRUNC | MSG_CTRUNC))) {
                if (received >= 0) close(received); closeSocket(); emit frameAvailable(); return;
            }
            {
                QMutexLocker guard(&mutex); discard(); pending = packet; pendingFd = received; available = true;
            }
            emit frameAvailable();
        });
    }
};

class TextureProvider : public QSGTextureProvider {
public:
    QSGTexture* current = nullptr;
    QSGTexture* texture() const override { return current; }
};

GlassTexture::GlassTexture(QQuickItem* parent) : QQuickItem(parent) {
    setFlag(ItemHasContents, true);
    connect(this, &QQuickItem::windowChanged, this, &GlassTexture::reconnect);
}
GlassTexture::~GlassTexture() { releaseResources(); if (m_stream) { disconnect(m_stream, nullptr, this, nullptr); m_stream->release(); } }
bool GlassTexture::ready() const { return m_stream && m_stream->available; }
void GlassTexture::setOutputName(const QString& value) { if (value == m_output) return; m_output = value; emit outputNameChanged(); reconnect(); }
void GlassTexture::setActive(bool value) { if (m_active == value) return; m_active = value; emit activeChanged(); reconnect(); }
void GlassTexture::reconnect() {
    if (m_stream) { disconnect(m_stream, nullptr, this, nullptr); m_stream->release(); m_stream = nullptr; }
    if (m_active && window() && !m_output.isEmpty()) {
        for (auto* child : window()->children()) if (auto* stream = qobject_cast<FrameStream*>(child); stream && stream->output == m_output) { m_stream = stream; break; }
        if (!m_stream) m_stream = new FrameStream(window(), m_output);
        m_stream->retain(); connect(m_stream, &FrameStream::frameAvailable, this, [this] { emit readyChanged(); update(); });
    }
    emit readyChanged(); update();
}
QSGTextureProvider* GlassTexture::textureProvider() const { if (!m_provider) m_provider = new TextureProvider; return m_provider; }
QSGNode* GlassTexture::updatePaintNode(QSGNode* old, UpdatePaintNodeData*) {
    auto* provider = static_cast<TextureProvider*>(textureProvider());
    provider->current = m_stream ? m_stream->texture() : nullptr; emit provider->textureChanged();
    if (!provider->current) { delete old; return nullptr; }
    auto* node = old ? static_cast<QSGSimpleTextureNode*>(old) : new QSGSimpleTextureNode;
    node->setOwnsTexture(false); node->setTexture(provider->current); node->setRect(boundingRect());
    node->setFiltering(QSGTexture::Linear); node->markDirty(QSGNode::DirtyMaterial); return node;
}
void GlassTexture::releaseResources() {
    if (m_provider && window()) { auto* provider = m_provider; m_provider = nullptr; window()->scheduleRenderJob(QRunnable::create([provider] { delete provider; }), QQuickWindow::AfterRenderingStage); }
}
#include "texture.moc"
