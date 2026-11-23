/*
 * MicroOS guest audio bridge.
 *
 * PulseAudio writes 48 kHz stereo s16le samples into a FIFO using
 * module-pipe-sink.  This MIT-licensed helper forwards those samples to the
 * Android app over a Unix socket, where an AudioTrack plays them.  It keeps
 * draining the FIFO when no client is attached so PulseAudio never blocks.
 *
 * Wire protocol (big-endian):
 *   header: u8 type, u8 flags, u16 reserved, u32 payload_length
 *   HELLO:  type 5, payload "MXAU", u16 version, u16 rate,
 *           u8 channels, u8 bits, u16 reserved
 *   AUDIO:  type 1, payload is raw little-endian PCM
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define PROTOCOL_VERSION 1
#define AUDIO_RATE 48000
#define AUDIO_CHANNELS 2
#define AUDIO_FRAME_BYTES 3840 /* 20 ms of 48 kHz stereo s16le */

enum { MSG_AUDIO = 1, MSG_HELLO = 5 };

static int listen_fd = -1;
static int client_fd = -1;
static int fifo_fd = -1;
static volatile sig_atomic_t running = 1;

static void stop_running(int signal_number) {
    (void)signal_number;
    running = 0;
}

static void put_u16(unsigned char *data, uint16_t value) {
    data[0] = (unsigned char)(value >> 8);
    data[1] = (unsigned char)value;
}

static void put_u32(unsigned char *data, uint32_t value) {
    data[0] = (unsigned char)(value >> 24);
    data[1] = (unsigned char)(value >> 16);
    data[2] = (unsigned char)(value >> 8);
    data[3] = (unsigned char)value;
}

static int send_all(int fd, const void *data, size_t length) {
    const unsigned char *cursor = data;
    while (length > 0) {
        ssize_t sent = send(fd, cursor, length, MSG_NOSIGNAL);
        if (sent > 0) {
            cursor += sent;
            length -= (size_t)sent;
            continue;
        }
        if (sent < 0 && errno == EINTR) continue;
        return -1;
    }
    return 0;
}

static void drop_client(void) {
    if (client_fd >= 0) close(client_fd);
    client_fd = -1;
}

static int send_hello(void) {
    unsigned char header[8] = {MSG_HELLO, 0, 0, 0};
    unsigned char payload[12];
    memcpy(payload, "MXAU", 4);
    put_u16(payload + 4, PROTOCOL_VERSION);
    put_u16(payload + 6, AUDIO_RATE);
    payload[8] = AUDIO_CHANNELS;
    payload[9] = 16;
    payload[10] = 0;
    payload[11] = 0;
    put_u32(header + 4, sizeof(payload));
    if (send_all(client_fd, header, sizeof(header)) != 0 ||
        send_all(client_fd, payload, sizeof(payload)) != 0) {
        drop_client();
        return -1;
    }
    return 0;
}

static void send_audio(const unsigned char *samples, size_t length) {
    if (client_fd < 0 || length == 0) return;
    unsigned char header[8] = {MSG_AUDIO, 0, 0, 0};
    put_u32(header + 4, (uint32_t)length);
    if (send_all(client_fd, header, sizeof(header)) != 0 ||
        send_all(client_fd, samples, length) != 0) {
        drop_client();
    }
}

static int open_listener(const char *path) {
    listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listen_fd < 0) {
        perror("socket");
        return -1;
    }
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof(address.sun_path)) {
        fprintf(stderr, "audio socket path is too long\n");
        return -1;
    }
    strcpy(address.sun_path, path);
    unlink(path);
    if (bind(listen_fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        perror("bind");
        return -1;
    }
    chmod(path, 0666);
    if (listen(listen_fd, 4) != 0) {
        perror("listen");
        return -1;
    }
    int flags = fcntl(listen_fd, F_GETFL, 0);
    if (flags >= 0) fcntl(listen_fd, F_SETFL, flags | O_NONBLOCK);
    return 0;
}

static void accept_client(void) {
    int fd = accept4(listen_fd, NULL, NULL, SOCK_CLOEXEC);
    if (fd < 0) return;
    drop_client();
    client_fd = fd;

    /*
     * Never let a paused or wedged Android process stall the guest's audio
     * daemon. A timed-out send drops this client; the app reconnects and starts
     * from a fresh stream instead of playing several seconds of stale audio.
     */
    struct timeval send_timeout = {0, 200 * 1000};
    setsockopt(client_fd, SOL_SOCKET, SO_SNDTIMEO,
               &send_timeout, sizeof(send_timeout));
    int buffer_size = 256 * 1024;
    setsockopt(client_fd, SOL_SOCKET, SO_SNDBUF, &buffer_size, sizeof(buffer_size));
    if (send_hello() == 0) {
        fprintf(stderr, "audio client connected\n");
    }
}

static void open_fifo(const char *path) {
    if (mkfifo(path, 0666) != 0 && errno != EEXIST) {
        perror("mkfifo");
        return;
    }
    chmod(path, 0666);
    fifo_fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fifo_fd < 0) {
        perror("open fifo");
        return;
    }
    fprintf(stderr, "audio bridge: FIFO %s\n", path);
}

static void usage(const char *program) {
    fprintf(stderr,
            "Usage: %s [--socket /tmp/microos-audio.sock] "
            "[--fifo /tmp/microos-audio.pcm]\n",
            program);
}

int main(int argc, char **argv) {
    const char *socket_path = "/tmp/microos-audio.sock";
    const char *fifo_path = "/tmp/microos-audio.pcm";

    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--socket") == 0 && index + 1 < argc) {
            socket_path = argv[++index];
        } else if (strcmp(argv[index], "--fifo") == 0 && index + 1 < argc) {
            fifo_path = argv[++index];
        } else if (strcmp(argv[index], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, stop_running);
    signal(SIGTERM, stop_running);

    open_fifo(fifo_path);
    if (open_listener(socket_path) != 0) return 1;

    unsigned char samples[AUDIO_FRAME_BYTES];
    fprintf(stderr, "audio bridge: socket %s, 48 kHz stereo s16le\n", socket_path);

    while (running) {
        fd_set read_set;
        FD_ZERO(&read_set);
        int max_fd = -1;
        if (listen_fd >= 0) {
            FD_SET(listen_fd, &read_set);
            max_fd = listen_fd;
        }
        struct timeval timeout = {0, 10000};
        int ready = select(max_fd + 1, &read_set, NULL, NULL, &timeout);
        if (ready > 0 && listen_fd >= 0 &&
            FD_ISSET(listen_fd, &read_set)) {
            accept_client();
        }

        if (fifo_fd < 0) {
            open_fifo(fifo_path);
            continue;
        }
        ssize_t count = read(fifo_fd, samples, sizeof(samples));
        if (count > 0) {
            send_audio(samples, (size_t)count);
        } else if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK &&
                   errno != EINTR) {
            close(fifo_fd);
            fifo_fd = -1;
        }
    }

    drop_client();
    if (listen_fd >= 0) close(listen_fd);
    if (fifo_fd >= 0) close(fifo_fd);
    unlink(socket_path);
    return 0;
}
