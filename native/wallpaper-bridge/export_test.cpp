#include "protocol.h"
#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <gbm.h>
#include <cassert>
#include <cstdlib>
#include <fcntl.h>
extern "C" void* glass_create(const char*);
extern "C" void glass_destroy(void*);
extern "C" void glass_poll(void*);
extern "C" void glass_frame(void*, uint32_t,uint32_t,uint32_t,uint64_t,uint32_t,const int*,const uint32_t*,const uint32_t*);
struct Received { GlassFrame frame; int fd; };
Received receive(int fd) {
    Received result {}; result.fd = -1;
    char control[CMSG_SPACE(sizeof(int))] {}; iovec data {&result.frame,sizeof(result.frame)}; msghdr message {};
    message.msg_iov=&data; message.msg_iovlen=1; message.msg_control=control; message.msg_controllen=sizeof(control);
    assert(recvmsg(fd,&message,MSG_DONTWAIT|MSG_CMSG_CLOEXEC)==sizeof(result.frame));
    assert(result.frame.valid());
    auto* c=CMSG_FIRSTHDR(&message); assert(c && c->cmsg_type==SCM_RIGHTS);
    std::memcpy(&result.fd,CMSG_DATA(c),sizeof(int)); assert(result.fd>=0);
    return result;
}
int connectClient() {
    int fd=socket(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0); assert(fd>=0);
    auto address=glassAddress("test-pool"); assert(connect(fd,reinterpret_cast<sockaddr*>(&address),sizeof(address))==0);
    return fd;
}
int main() {
    const char* node=std::getenv("SERPANTINUM_DRM_DEVICE"); if (!node) return 77;
    int deviceFd=open(node,O_RDWR|O_CLOEXEC); assert(deviceFd>=0);
    auto* device=gbm_create_device(deviceFd); assert(device);
    auto* bo=gbm_bo_create(device,64,32,GBM_FORMAT_ARGB8888,GBM_BO_USE_RENDERING|GBM_BO_USE_LINEAR); assert(bo);
    int source=gbm_bo_get_fd(bo); uint32_t stride=gbm_bo_get_stride(bo),offset=0;
    auto* broker=glass_create("test-pool");
    auto submit=[&] {glass_frame(broker,64,32,GBM_FORMAT_ARGB8888,gbm_bo_get_modifier(bo),1,&source,&stride,&offset);};
    submit(); int client=connectClient(); glass_poll(broker); auto first=receive(client);
    for(int i=0;i<12;++i) submit();
    char byte; assert(recv(client,&byte,1,MSG_DONTWAIT)<0 && errno==EAGAIN);
    uint64_t bad=first.frame.serial+100; assert(send(client,&bad,sizeof(bad),0)==sizeof(bad)); submit();
    assert(recv(client,&byte,1,MSG_DONTWAIT)<0 && errno==EAGAIN);
    assert(send(client,&first.frame.serial,sizeof(uint64_t),0)==sizeof(uint64_t)); submit();
    auto next=receive(client); assert(next.frame.serial>first.frame.serial); assert(next.frame.slot<3);
    // A newly visible panel gets the retained frame even while scene rendering is paused.
    int late=connectClient(); glass_poll(broker); auto frozen=receive(late); assert(frozen.frame.serial==next.frame.serial);
    close(client); submit(); close(late); glass_poll(broker);
    close(first.fd); close(next.fd); close(frozen.fd); close(source);
    glass_destroy(broker); gbm_bo_destroy(bo); gbm_device_destroy(device); close(deviceFd);
}
