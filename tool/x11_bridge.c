/*
 * MicroOS native X11 bridge.
 *
 * This is Misty OS's own transport between a normal X11 server in the
 * PRoot guest and the Android surface that displays it.  It replaces the
 * VNC/noVNC stack: Xvfb + openbox keep running inside the guest, while this
 * small MIT-licensed program mirrors damaged rectangles to the app and
 * injects touch/keyboard events with XTEST.
 *
 * Wire protocol (all integers big-endian):
 *
 *   header: u8 type, u8 flags, u16 reserved, u32 payload_length
 *
 *   server -> app
 *     1  FRAME   u16 x, y, w, h followed by w*h BGRX pixels
 *     2  CURSOR  i16 x, y, u8 visible, u8 shape
 *     3  NOTICE  UTF-8 diagnostic text
 *     4  JPEG    u16 x, y, w, h followed by a baseline JPEG of that rect
 *     5  HELLO   "MX11", u16 version, u16 width, u16 height, u16 stride
 *
 * Large rectangles (video, full-screen damage) are sent as JPEG so the
 * transport remains fast over a local Unix socket. Small text updates stay
 * raw and pixel-exact.
 *
 *   app -> server
 *     16 POINTER i16 x, y, u8 action (0 move, 1 down, 2 up), u8 button
 *     17 WHEEL   i16 x, y, i16 dx, i16 dy (positive = down/right)
 *     18 KEY     u32 keysym, u8 down, u8 repeat, u16 reserved
 *     19 TEXT    UTF-8 text (typed one keysym at a time)
 *     20 RELEASE release every button and key
 *
 * The bridge deliberately has no dependency on Android or on any GPL code.
 * Xlib, XTEST, XDamage and XFixes are MIT-licensed X.Org components.
 */

#define _GNU_SOURCE

#include <X11/XKBlib.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xdamage.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/XTest.h>
#include <X11/keysym.h>

#include <stdio.h>
#include <jpeglib.h>
#include <setjmp.h>

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
#define MAX_CLIENT_BACKLOG (32u * 1024u * 1024u)
#define MAX_INPUT_BUFFER (1024u * 1024u)
#define SCRATCH_SLOTS 48
#define FRAME_INTERVAL_MS 16
#define CURSOR_INTERVAL_MS 33
#define MAX_PENDING_FRAME_BYTES (2u * 1024u * 1024u)

enum {
    MSG_FRAME = 1,
    MSG_CURSOR = 2,
    MSG_NOTICE = 3,
    MSG_FRAME_JPEG = 4,
    MSG_HELLO = 5,

    MSG_POINTER = 16,
    MSG_WHEEL = 17,
    MSG_KEY = 18,
    MSG_TEXT = 19,
    MSG_RELEASE = 20
};

typedef struct {
    unsigned char *data;
    size_t len;
    size_t sent;
    size_t cap;
} OutBuf;

static Display *dpy;
static Window root;
static int screen;
static int screen_width;
static int screen_height;
static int damage_event_base = -1;
static int damage_error_base = -1;
static Damage damage = 0;

static int listen_fd = -1;
static int client_fd = -1;
static OutBuf out;
static unsigned char input_buffer[65536];
static size_t input_length;
static int running = 1;
static int need_full_frame;

static int pressed_buttons[8];
static int pressed_keys[256];

static KeySym scratch_syms[SCRATCH_SLOTS];
static KeyCode scratch_codes[SCRATCH_SLOTS];
static int scratch_free[SCRATCH_SLOTS];
static int scratch_free_count;
static int scratch_next;

static int last_cursor_x = -1;
static int last_cursor_y = -1;

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

static void put_u16(unsigned char *p, uint16_t value) {
    p[0] = (unsigned char)(value >> 8);
    p[1] = (unsigned char)value;
}

static void put_u32(unsigned char *p, uint32_t value) {
    p[0] = (unsigned char)(value >> 24);
    p[1] = (unsigned char)(value >> 16);
    p[2] = (unsigned char)(value >> 8);
    p[3] = (unsigned char)value;
}

static uint16_t get_u16(const unsigned char *p) {
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static uint32_t get_u32(const unsigned char *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}

static int out_reserve(OutBuf *buffer, size_t extra) {
    if (buffer->len + extra > MAX_CLIENT_BACKLOG) return -1;
    if (buffer->len + extra <= buffer->cap) return 0;

    size_t capacity = buffer->cap ? buffer->cap : 65536;
    while (capacity < buffer->len + extra) {
        if (capacity > MAX_CLIENT_BACKLOG / 2) {
            capacity = MAX_CLIENT_BACKLOG;
            break;
        }
        capacity *= 2;
    }
    unsigned char *data = realloc(buffer->data, capacity);
    if (!data) return -1;
    buffer->data = data;
    buffer->cap = capacity;
    return 0;
}

static int out_append(OutBuf *buffer, const void *data, size_t length) {
    if (out_reserve(buffer, length) != 0) return -1;
    memcpy(buffer->data + buffer->len, data, length);
    buffer->len += length;
    return 0;
}

static void close_client(void);

static int queue_message(uint8_t type, const void *payload, uint32_t length) {
    if (client_fd < 0) return 0;
    if (out.sent == out.len) {
        out.sent = 0;
        out.len = 0;
    }

    unsigned char header[8];
    header[0] = type;
    header[1] = 0;
    header[2] = 0;
    header[3] = 0;
    put_u32(header + 4, length);

    if (out_append(&out, header, sizeof(header)) != 0 ||
        (length > 0 && out_append(&out, payload, length) != 0)) {
        close_client();
        return -1;
    }
    return 0;
}

static void queue_notice(const char *text) {
    if (client_fd < 0 || !text) return;
    queue_message(MSG_NOTICE, text, (uint32_t)strlen(text));
}

static void release_all_input(void) {
    if (!dpy) return;
    for (int button = 1; button <= 7; button++) {
        if (!pressed_buttons[button]) continue;
        XTestFakeButtonEvent(dpy, button, False, CurrentTime);
        pressed_buttons[button] = 0;
    }
    for (int keycode = 8; keycode < 256; keycode++) {
        if (!pressed_keys[keycode]) continue;
        XTestFakeKeyEvent(dpy, (KeyCode)keycode, False, CurrentTime);
        pressed_keys[keycode] = 0;
    }
    XFlush(dpy);
}

static void close_client(void) {
    if (client_fd >= 0) {
        close(client_fd);
        client_fd = -1;
    }
    input_length = 0;
    out.sent = 0;
    out.len = 0;
    release_all_input();
}

static void send_hello(void) {
    unsigned char payload[12];
    memcpy(payload, "MX11", 4);
    put_u16(payload + 4, PROTOCOL_VERSION);
    put_u16(payload + 6, (uint16_t)screen_width);
    put_u16(payload + 8, (uint16_t)screen_height);
    put_u16(payload + 10, (uint16_t)(screen_width * 4));
    queue_message(MSG_HELLO, payload, sizeof(payload));
}

static int scratch_keycode(KeySym symbol);

static KeyCode existing_keycode(KeySym symbol) {
    KeyCode keycode = XKeysymToKeycode(dpy, symbol);
    if (keycode == 0) return 0;
    if (XkbKeycodeToKeysym(dpy, keycode, 0, 0) == symbol) return keycode;
    return 0;
}

static KeyCode keycode_for_symbol(KeySym symbol) {
    KeyCode keycode = existing_keycode(symbol);
    if (keycode != 0) return keycode;
    return scratch_keycode(symbol);
}

static int scratch_keycode(KeySym symbol) {
    for (int index = 0; index < SCRATCH_SLOTS; index++) {
        if (scratch_codes[index] != 0 && scratch_syms[index] == symbol) {
            return scratch_codes[index];
        }
    }

    if (scratch_free_count == 0) return 0;

    int slot = scratch_next % scratch_free_count;
    scratch_next = (scratch_next + 1) % scratch_free_count;
    KeyCode keycode = (KeyCode)scratch_free[slot];
    XChangeKeyboardMapping(dpy, keycode, 1, &symbol, 1);
    XSync(dpy, False);
    scratch_syms[slot] = symbol;
    scratch_codes[slot] = keycode;
    return keycode;
}

static void fake_key(KeySym symbol, int down) {
    KeyCode keycode = keycode_for_symbol(symbol);
    if (keycode == 0) return;
    XTestFakeKeyEvent(dpy, keycode, down ? True : False, CurrentTime);
    pressed_keys[keycode & 0xff] = down ? 1 : 0;
}

static void handle_pointer(const unsigned char *payload, uint32_t length) {
    if (length < 6) return;
    int x = (int16_t)get_u16(payload);
    int y = (int16_t)get_u16(payload + 2);
    int action = payload[4];
    int button = payload[5];

    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= screen_width) x = screen_width - 1;
    if (y >= screen_height) y = screen_height - 1;

    XTestFakeMotionEvent(dpy, screen, x, y, CurrentTime);
    if (button >= 1 && button <= 7) {
        if (action == 1) {
            XTestFakeButtonEvent(dpy, button, True, CurrentTime);
            pressed_buttons[button] = 1;
        } else if (action == 2) {
            XTestFakeButtonEvent(dpy, button, False, CurrentTime);
            pressed_buttons[button] = 0;
        }
    }
    XFlush(dpy);
}

static void handle_wheel(const unsigned char *payload, uint32_t length) {
    if (length < 8) return;
    int x = (int16_t)get_u16(payload);
    int y = (int16_t)get_u16(payload + 2);
    int dx = (int16_t)get_u16(payload + 4);
    int dy = (int16_t)get_u16(payload + 6);

    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= screen_width) x = screen_width - 1;
    if (y >= screen_height) y = screen_height - 1;
    if (dx > 20) dx = 20;
    if (dx < -20) dx = -20;
    if (dy > 20) dy = 20;
    if (dy < -20) dy = -20;

    XTestFakeMotionEvent(dpy, screen, x, y, CurrentTime);

    int vertical_button = dy > 0 ? 5 : 4;
    for (int i = 0; i < abs(dy); i++) {
        XTestFakeButtonEvent(dpy, vertical_button, True, CurrentTime);
        XTestFakeButtonEvent(dpy, vertical_button, False, CurrentTime);
    }
    int horizontal_button = dx > 0 ? 7 : 6;
    for (int i = 0; i < abs(dx); i++) {
        XTestFakeButtonEvent(dpy, horizontal_button, True, CurrentTime);
        XTestFakeButtonEvent(dpy, horizontal_button, False, CurrentTime);
    }
    XFlush(dpy);
}

static void handle_key(const unsigned char *payload, uint32_t length) {
    if (length < 6) return;
    KeySym symbol = (KeySym)get_u32(payload);
    int down = payload[4] != 0;
    if (symbol == NoSymbol) return;
    fake_key(symbol, down);
    XFlush(dpy);
}

static uint32_t next_codepoint(const unsigned char *data, size_t length,
                               size_t *offset) {
    if (*offset >= length) return 0;
    unsigned char first = data[*offset];
    if (first < 0x80) {
        (*offset)++;
        return first;
    }
    int extra;
    uint32_t value;
    if ((first & 0xe0) == 0xc0) {
        extra = 1;
        value = first & 0x1f;
    } else if ((first & 0xf0) == 0xe0) {
        extra = 2;
        value = first & 0x0f;
    } else if ((first & 0xf8) == 0xf0) {
        extra = 3;
        value = first & 0x07;
    } else {
        (*offset)++;
        return 0xfffd;
    }
    if (*offset + (size_t)extra >= length) {
        *offset = length;
        return 0xfffd;
    }
    for (int i = 1; i <= extra; i++) {
        unsigned char byte = data[*offset + (size_t)i];
        if ((byte & 0xc0) != 0x80) {
            (*offset)++;
            return 0xfffd;
        }
        value = (value << 6) | (byte & 0x3f);
    }
    *offset += (size_t)extra + 1;
    return value;
}

static void handle_text(const unsigned char *payload, uint32_t length) {
    size_t offset = 0;
    while (offset < length) {
        uint32_t codepoint = next_codepoint(payload, length, &offset);
        if (codepoint == 0) continue;

        KeySym symbol;
        if (codepoint == '\n' || codepoint == '\r') {
            symbol = XK_Return;
        } else if (codepoint == '\t') {
            symbol = XK_Tab;
        } else if (codepoint == '\b') {
            symbol = XK_BackSpace;
        } else if (codepoint >= 0x20 && codepoint <= 0x7e) {
            symbol = (KeySym)codepoint;
        } else if (codepoint >= 0xa0 && codepoint <= 0xff) {
            symbol = (KeySym)codepoint;
        } else {
            symbol = (KeySym)(0x01000000u | codepoint);
        }

        KeyCode keycode = keycode_for_symbol(symbol);
        if (keycode == 0) continue;
        XTestFakeKeyEvent(dpy, keycode, True, CurrentTime);
        XTestFakeKeyEvent(dpy, keycode, False, CurrentTime);
    }
    XFlush(dpy);
}

static void handle_message(uint8_t type, const unsigned char *payload,
                           uint32_t length) {
    switch (type) {
        case MSG_POINTER:
            handle_pointer(payload, length);
            break;
        case MSG_WHEEL:
            handle_wheel(payload, length);
            break;
        case MSG_KEY:
            handle_key(payload, length);
            break;
        case MSG_TEXT:
            handle_text(payload, length);
            break;
        case MSG_RELEASE:
            release_all_input();
            break;
        default:
            break;
    }
}

static void read_client_input(void) {
    unsigned char buffer[8192];
    while (client_fd >= 0) {
        ssize_t count = recv(client_fd, buffer, sizeof(buffer), 0);
        if (count > 0) {
            if (input_length + (size_t)count > MAX_INPUT_BUFFER) {
                close_client();
                return;
            }
            memcpy(input_buffer + input_length, buffer, (size_t)count);
            input_length += (size_t)count;

            size_t offset = 0;
            while (input_length - offset >= 8) {
                uint8_t type = input_buffer[offset];
                uint32_t length = get_u32(input_buffer + offset + 4);
                if (length > MAX_INPUT_BUFFER) {
                    close_client();
                    return;
                }
                if (input_length - offset - 8 < length) break;
                handle_message(type, input_buffer + offset + 8, length);
                offset += 8 + length;
            }
            if (offset > 0) {
                memmove(input_buffer, input_buffer + offset,
                        input_length - offset);
                input_length -= offset;
            }
            continue;
        }
        if (count == 0) {
            close_client();
            return;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) return;
        close_client();
        return;
    }
}

static void flush_client_output(void) {
    while (client_fd >= 0 && out.sent < out.len) {
        ssize_t count = send(client_fd, out.data + out.sent,
                             out.len - out.sent, MSG_NOSIGNAL);
        if (count > 0) {
            out.sent += (size_t)count;
            continue;
        }
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
        close_client();
        return;
    }
    if (out.sent == out.len) out.sent = out.len = 0;
}

typedef struct {
    struct jpeg_error_mgr pub;
    jmp_buf jump;
} JpegError;

static void jpeg_error_exit(j_common_ptr cinfo) {
    JpegError *error = (JpegError *)cinfo->err;
    longjmp(error->jump, 1);
}

/*
 * Encode one damaged rectangle as a baseline JPEG. JPEG is only used for
 * large, fast-changing regions (video and full-screen redraws); text updates
 * remain raw so glyphs stay pixel-exact.
 */
static int encode_jpeg(XImage *image, int width, int height,
                       unsigned char **output, unsigned long *output_size) {
    struct jpeg_compress_struct cinfo;
    JpegError error;
    unsigned char *row = NULL;

    *output = NULL;
    *output_size = 0;

    cinfo.err = jpeg_std_error(&error.pub);
    error.pub.error_exit = jpeg_error_exit;
    if (setjmp(error.jump)) {
        jpeg_destroy_compress(&cinfo);
        free(row);
        free(*output);
        *output = NULL;
        return -1;
    }

    jpeg_create_compress(&cinfo);
    jpeg_mem_dest(&cinfo, output, output_size);

    cinfo.image_width = (JDIMENSION)width;
    cinfo.image_height = (JDIMENSION)height;
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, 76, TRUE);
    cinfo.dct_method = JDCT_FASTEST;
    jpeg_start_compress(&cinfo, TRUE);

    row = malloc((size_t)width * 3u);
    if (!row) {
        jpeg_destroy_compress(&cinfo);
        free(*output);
        *output = NULL;
        return -1;
    }

    while (cinfo.next_scanline < cinfo.image_height) {
        int py = (int)cinfo.next_scanline;
        if (image->bits_per_pixel == 32 && image->byte_order == LSBFirst &&
            image->bytes_per_line >= width * 4) {
            const unsigned char *source =
                (const unsigned char *)image->data +
                (size_t)py * image->bytes_per_line;
            for (int px = 0; px < width; px++) {
                row[px * 3] = source[px * 4 + 2];
                row[px * 3 + 1] = source[px * 4 + 1];
                row[px * 3 + 2] = source[px * 4];
            }
        } else {
            for (int px = 0; px < width; px++) {
                unsigned long pixel = XGetPixel(image, px, py);
                row[px * 3] = (unsigned char)((pixel >> 16) & 0xff);
                row[px * 3 + 1] = (unsigned char)((pixel >> 8) & 0xff);
                row[px * 3 + 2] = (unsigned char)(pixel & 0xff);
            }
        }
        JSAMPROW rows[1] = {row};
        jpeg_write_scanlines(&cinfo, rows, 1);
    }

    jpeg_finish_compress(&cinfo);
    jpeg_destroy_compress(&cinfo);
    free(row);
    return 0;
}

static int send_frame_rect(int x, int y, int width, int height) {
    if (client_fd < 0 || width <= 0 || height <= 0) return 0;
    if (x < 0) {
        width += x;
        x = 0;
    }
    if (y < 0) {
        height += y;
        y = 0;
    }
    if (x + width > screen_width) width = screen_width - x;
    if (y + height > screen_height) height = screen_height - y;
    if (width <= 0 || height <= 0) return 0;

    /*
     * Keep latency low on a phone that occasionally decodes slower than the
     * guest produces video frames. Dropping a whole frame at a message boundary
     * is safe; blocking here would add seconds of lag and eventually freeze the
     * guest's X clients. The damage that was just consumed is recovered by a
     * full-frame refresh once the socket drains, so the display cannot keep a
     * stale rectangle.
     */
    if (out.len - out.sent > MAX_PENDING_FRAME_BYTES) {
        need_full_frame = 1;
        return 0;
    }

    XImage *image = XGetImage(dpy, root, x, y, (unsigned)width,
                              (unsigned)height, AllPlanes, ZPixmap);
    if (!image) {
        need_full_frame = 1;
        return 0;
    }

    size_t pixel_bytes = (size_t)width * (size_t)height * 4u;
    if (out.len + 16u + pixel_bytes > MAX_CLIENT_BACKLOG) {
        XDestroyImage(image);
        close_client();
        return 0;
    }

    if ((long)width * (long)height >= 256L * 256L) {
        unsigned char *jpeg_data = NULL;
        unsigned long jpeg_size = 0;
        if (encode_jpeg(image, width, height, &jpeg_data, &jpeg_size) == 0 &&
            jpeg_data != NULL && jpeg_size > 0 &&
            jpeg_size + 16u <= MAX_CLIENT_BACKLOG - out.len) {
            unsigned char jpeg_header[8];
            jpeg_header[0] = MSG_FRAME_JPEG;
            jpeg_header[1] = 0;
            jpeg_header[2] = 0;
            jpeg_header[3] = 0;
            put_u32(jpeg_header + 4, (uint32_t)(8u + jpeg_size));
            unsigned char jpeg_rect[8];
            put_u16(jpeg_rect, (uint16_t)x);
            put_u16(jpeg_rect + 2, (uint16_t)y);
            put_u16(jpeg_rect + 4, (uint16_t)width);
            put_u16(jpeg_rect + 6, (uint16_t)height);
            if (out_append(&out, jpeg_header, sizeof(jpeg_header)) == 0 &&
                out_append(&out, jpeg_rect, sizeof(jpeg_rect)) == 0 &&
                out_append(&out, jpeg_data, (size_t)jpeg_size) == 0) {
                free(jpeg_data);
                XDestroyImage(image);
                return 1;
            }
            free(jpeg_data);
            XDestroyImage(image);
            close_client();
            return 0;
        }
        free(jpeg_data);
    }

    unsigned char header[8];
    header[0] = MSG_FRAME;
    header[1] = 0;
    header[2] = 0;
    header[3] = 0;
    put_u32(header + 4, (uint32_t)(8u + pixel_bytes));
    unsigned char rect[8];
    put_u16(rect, (uint16_t)x);
    put_u16(rect + 2, (uint16_t)y);
    put_u16(rect + 4, (uint16_t)width);
    put_u16(rect + 6, (uint16_t)height);

    if (out_append(&out, header, sizeof(header)) != 0 ||
        out_append(&out, rect, sizeof(rect)) != 0) {
        XDestroyImage(image);
        close_client();
        return 0;
    }

    if (image->bits_per_pixel == 32 && image->byte_order == LSBFirst &&
        image->bytes_per_line >= width * 4) {
        /* Xvfb uses 32-bit ZPixmap: B, G, R, X in memory. */
        for (int row = 0; row < height; row++) {
            if (out_append(&out, image->data + (size_t)row * image->bytes_per_line,
                           (size_t)width * 4u) != 0) {
                XDestroyImage(image);
                close_client();
                return 0;
            }
        }
    } else {
        unsigned char *row = malloc((size_t)width * 4u);
        if (!row) {
            XDestroyImage(image);
            close_client();
            return 0;
        }
        for (int py = 0; py < height; py++) {
            for (int px = 0; px < width; px++) {
                unsigned long pixel = XGetPixel(image, px, py);
                unsigned char *target = row + (size_t)px * 4u;
                target[0] = (unsigned char)(pixel & 0xff);
                target[1] = (unsigned char)((pixel >> 8) & 0xff);
                target[2] = (unsigned char)((pixel >> 16) & 0xff);
                target[3] = 0;
            }
            if (out_append(&out, row, (size_t)width * 4u) != 0) {
                free(row);
                XDestroyImage(image);
                close_client();
                return 0;
            }
        }
        free(row);
    }
    XDestroyImage(image);
    return 1;
}

static int send_full_frame(void) {
    return send_frame_rect(0, 0, screen_width, screen_height);
}

static void send_damage(void) {
    if (client_fd < 0 || damage == 0) return;

    XserverRegion region = XFixesCreateRegion(dpy, NULL, 0);
    if (region == None) return;
    XDamageSubtract(dpy, damage, None, region);

    int rectangle_count = 0;
    XRectangle *rectangles = XFixesFetchRegion(dpy, region, &rectangle_count);
    XFixesDestroyRegion(dpy, region);
    if (!rectangles || rectangle_count <= 0) {
        if (rectangles) XFree(rectangles);
        return;
    }

    long total_area = 0;
    int left = screen_width;
    int top = screen_height;
    int right = 0;
    int bottom = 0;
    for (int index = 0; index < rectangle_count; index++) {
        XRectangle rect = rectangles[index];
        if (rect.width <= 0 || rect.height <= 0) continue;
        total_area += (long)rect.width * (long)rect.height;
        if (rect.x < left) left = rect.x;
        if (rect.y < top) top = rect.y;
        if (rect.x + rect.width > right) right = rect.x + rect.width;
        if (rect.y + rect.height > bottom) bottom = rect.y + rect.height;
    }

    if (rectangle_count > 48 ||
        total_area > (long)screen_width * (long)screen_height * 55L / 100L) {
        if (right > left && bottom > top) {
            send_frame_rect(left, top, right - left, bottom - top);
        }
    } else {
        for (int index = 0; index < rectangle_count; index++) {
            XRectangle rect = rectangles[index];
            send_frame_rect(rect.x, rect.y, rect.width, rect.height);
        }
    }
    XFree(rectangles);
}

static void send_cursor(int force) {
    if (client_fd < 0) return;
    Window returned_root;
    Window returned_child;
    int root_x = 0;
    int root_y = 0;
    int window_x = 0;
    int window_y = 0;
    unsigned int mask = 0;
    if (!XQueryPointer(dpy, root, &returned_root, &returned_child,
                       &root_x, &root_y, &window_x, &window_y, &mask)) {
        return;
    }
    if (!force && root_x == last_cursor_x && root_y == last_cursor_y) return;

    last_cursor_x = root_x;
    last_cursor_y = root_y;
    unsigned char payload[8];
    put_u16(payload, (uint16_t)(int16_t)root_x);
    put_u16(payload + 2, (uint16_t)(int16_t)root_y);
    payload[4] = 1; /* visible */
    payload[5] = 0; /* arrow */
    payload[6] = 0;
    payload[7] = 0;
    queue_message(MSG_CURSOR, payload, sizeof(payload));
}

static void accept_client(void) {
    int fd = accept4(listen_fd, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
    if (fd < 0) return;
    close_client();
    client_fd = fd;

    int size = 1 << 20;
    setsockopt(client_fd, SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
    setsockopt(client_fd, SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));

    out.sent = 0;
    out.len = 0;
    input_length = 0;
    last_cursor_x = -1;
    last_cursor_y = -1;
    need_full_frame = 1;

    send_hello();
    queue_notice("native X11 bridge connected\n");
}

static int open_listener(const char *socket_path) {
    if (!socket_path || !*socket_path) return -1;
    listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listen_fd < 0) {
        perror("socket");
        return -1;
    }

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    if (strlen(socket_path) >= sizeof(address.sun_path)) {
        fprintf(stderr, "socket path is too long: %s\n", socket_path);
        close(listen_fd);
        listen_fd = -1;
        return -1;
    }
    strcpy(address.sun_path, socket_path);
    unlink(socket_path);
    if (bind(listen_fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        perror("bind");
        close(listen_fd);
        listen_fd = -1;
        return -1;
    }
    chmod(socket_path, 0666);
    if (listen(listen_fd, 4) != 0) {
        perror("listen");
        close(listen_fd);
        listen_fd = -1;
        return -1;
    }

    int flags = fcntl(listen_fd, F_GETFL, 0);
    if (flags >= 0) fcntl(listen_fd, F_SETFL, flags | O_NONBLOCK);
    return 0;
}

static void prepare_scratch_keycodes(void) {
    int minimum = 8;
    int maximum = 255;
    XDisplayKeycodes(dpy, &minimum, &maximum);
    scratch_free_count = 0;
    scratch_next = 0;

    for (int keycode = maximum; keycode >= minimum &&
         scratch_free_count < SCRATCH_SLOTS; keycode--) {
        int per_keycode = 0;
        KeySym *mapping = XGetKeyboardMapping(dpy, (KeyCode)keycode, 1,
                                              &per_keycode);
        int used = 0;
        if (mapping) {
            for (int index = 0; index < per_keycode; index++) {
                if (mapping[index] != NoSymbol) {
                    used = 1;
                    break;
                }
            }
            XFree(mapping);
        }
        if (!used) {
            scratch_free[scratch_free_count++] = keycode;
        }
    }

    if (scratch_free_count == 0) {
        fprintf(stderr, "no free keycodes available for text input\n");
    }
}

static int handle_x_events(void) {
    int damaged = 0;
    while (XPending(dpy) > 0) {
        XEvent event;
        XNextEvent(dpy, &event);
        if (damage_event_base >= 0 &&
            event.type == damage_event_base + XDamageNotify) {
            damaged = 1;
        } else if (event.type == DestroyNotify &&
                   event.xdestroywindow.window == root) {
            running = 0;
        }
    }
    return damaged;
}

static void usage(const char *program) {
    fprintf(stderr,
            "Usage: %s [--display :0] [--socket /tmp/microos-x11.sock]\n",
            program);
}

int main(int argc, char **argv) {
    const char *display_name = getenv("DISPLAY");
    const char *socket_path = "/tmp/microos-x11.sock";

    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--display") == 0 && index + 1 < argc) {
            display_name = argv[++index];
        } else if (strcmp(argv[index], "--socket") == 0 && index + 1 < argc) {
            socket_path = argv[++index];
        } else if (strcmp(argv[index], "--help") == 0 ||
                   strcmp(argv[index], "-h") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGTERM, SIG_IGN);

    dpy = XOpenDisplay(display_name);
    if (!dpy) {
        fprintf(stderr, "cannot open X display %s\n",
                display_name ? display_name : "(null)");
        return 1;
    }

    screen = DefaultScreen(dpy);
    root = RootWindow(dpy, screen);
    screen_width = DisplayWidth(dpy, screen);
    screen_height = DisplayHeight(dpy, screen);
    if (screen_width <= 0 || screen_height <= 0) {
        fprintf(stderr, "X display has no usable root window\n");
        return 1;
    }

    if (XDamageQueryExtension(dpy, &damage_event_base, &damage_error_base)) {
        damage = XDamageCreate(dpy, root, XDamageReportNonEmpty);
        if (!damage) {
            fprintf(stderr, "XDamageCreate failed; falling back to redraws\n");
        }
    } else {
        fprintf(stderr, "XDamage extension unavailable\n");
    }

    prepare_scratch_keycodes();
    if (open_listener(socket_path) != 0) return 1;

    fprintf(stderr, "native X11 bridge: display %s, %dx%d, socket %s\n",
            display_name ? display_name : "(default)", screen_width,
            screen_height, socket_path);

    uint64_t last_frame = 0;
    uint64_t last_cursor = 0;
    int damaged = 0;

    while (running) {
        fd_set read_set;
        fd_set write_set;
        FD_ZERO(&read_set);
        FD_ZERO(&write_set);

        int max_fd = -1;
        int x_fd = ConnectionNumber(dpy);
        FD_SET(x_fd, &read_set);
        max_fd = x_fd;

        if (listen_fd >= 0) {
            FD_SET(listen_fd, &read_set);
            if (listen_fd > max_fd) max_fd = listen_fd;
        }
        if (client_fd >= 0) {
            FD_SET(client_fd, &read_set);
            if (client_fd > max_fd) max_fd = client_fd;
            if (out.sent < out.len) {
                FD_SET(client_fd, &write_set);
            }
        }

        struct timeval timeout;
        timeout.tv_sec = 0;
        if (client_fd >= 0 && (need_full_frame || damaged)) {
            timeout.tv_usec = 16 * 1000;
        } else if (client_fd >= 0) {
            timeout.tv_usec = 100 * 1000;
        } else {
            timeout.tv_usec = 500 * 1000;
        }

        int ready = select(max_fd + 1, &read_set, &write_set, NULL, &timeout);
        if (ready < 0 && errno != EINTR) {
            perror("select");
            break;
        }

        if (ready > 0) {
            if (listen_fd >= 0 && FD_ISSET(listen_fd, &read_set)) {
                accept_client();
            }
            if (client_fd >= 0 && FD_ISSET(client_fd, &read_set)) {
                read_client_input();
            }
            if (client_fd >= 0 && FD_ISSET(client_fd, &write_set)) {
                flush_client_output();
            }
            if (FD_ISSET(x_fd, &read_set)) {
                if (handle_x_events()) damaged = 1;
            }
        }

        uint64_t current = now_ms();
        if (client_fd >= 0 && need_full_frame &&
            current - last_frame >= FRAME_INTERVAL_MS) {
            if (damage != 0) {
                XserverRegion region = XFixesCreateRegion(dpy, NULL, 0);
                if (region != None) {
                    XDamageSubtract(dpy, damage, None, region);
                    XFixesDestroyRegion(dpy, region);
                }
            }
            if (send_full_frame()) {
                need_full_frame = 0;
            }
            send_cursor(1);
            last_frame = current;
            last_cursor = current;
            damaged = 0;
        } else if (client_fd >= 0 && damaged &&
                   current - last_frame >= FRAME_INTERVAL_MS) {
            send_damage();
            last_frame = current;
            damaged = 0;
        }

        if (client_fd >= 0 && current - last_cursor >= CURSOR_INTERVAL_MS) {
            send_cursor(0);
            last_cursor = current;
        }

        if (client_fd >= 0) flush_client_output();
    }

    close_client();
    if (damage != 0) XDamageDestroy(dpy, damage);
    if (listen_fd >= 0) close(listen_fd);
    if (socket_path && *socket_path) unlink(socket_path);
    if (dpy) XCloseDisplay(dpy);
    free(out.data);
    return 0;
}
