package com.matthewcodergamer.micro_os;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.SurfaceTexture;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.text.InputType;
import android.util.Log;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.TextureView;
import android.view.ViewConfiguration;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * Android surface for the native X11 desktop.
 *
 * The guest runs a normal X server (Xvfb) and MicroOS's small MIT-licensed
 * bridge mirrors damaged rectangles over a Unix socket. This view turns those
 * rectangles into a Bitmap, draws the pointer, and sends touch/keyboard input
 * back over the same socket. It does not embed Termux:X11 or any GPL code.
 */
public final class MicroOSX11View extends TextureView
        implements TextureView.SurfaceTextureListener, PlatformView {

    public static final class Factory extends PlatformViewFactory {
        private final BinaryMessenger messenger;

        public Factory(BinaryMessenger messenger) {
            super(StandardMessageCodec.INSTANCE);
            this.messenger = messenger;
        }

        @NonNull
        @Override
        public PlatformView create(@NonNull Context context, int id, @Nullable Object args) {
            Map<?, ?> parameters = args instanceof Map
                    ? (Map<?, ?>) args : new HashMap<Object, Object>();
            MethodChannel channel = new MethodChannel(
                    messenger, "microos/x11/" + id);
            return new MicroOSX11View(context, parameters, channel);
        }
    }

    private static final String TAG = "MicroOSX11";
    private static final int MSG_FRAME = 1;
    private static final int MSG_CURSOR = 2;
    private static final int MSG_NOTICE = 3;
    private static final int MSG_FRAME_JPEG = 4;
    private static final int MSG_HELLO = 5;
    private static final int MSG_POINTER = 16;
    private static final int MSG_WHEEL = 17;
    private static final int MSG_KEY = 18;
    private static final int MSG_TEXT = 19;
    private static final int MSG_RELEASE = 20;
    private static final int MAX_MESSAGE = 64 * 1024 * 1024;
    private static final int MAX_FRAME_MESSAGE = 8 * 1024 * 1024;
    private static final int MAX_FRAME_DIMENSION = 4096;
    private static final long MAX_FRAME_PIXELS = 6_000_000L;

    private static final int MODE_TRACKPAD = 0;
    private static final int MODE_DIRECT = 1;

    private static final int TOUCH_IDLE = 0;
    private static final int TOUCH_TRACKPAD_PENDING = 1;
    private static final int TOUCH_TRACKPAD_MOVE = 2;
    private static final int TOUCH_TRACKPAD_HELD = 3;
    private static final int TOUCH_TRACKPAD_DRAG = 4;
    private static final int TOUCH_DIRECT = 5;
    private static final int TOUCH_SCROLL = 6;
    private static final int TOUCH_FINISHED = 7;

    private final MethodChannel channel;
    private final String socketPath;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Object writeLock = new Object();
    private final LinkedBlockingQueue<byte[]> outgoing = new LinkedBlockingQueue<>(1024);
    private final Object bitmapLock = new Object();
    private final Object drawLock = new Object();
    private final Paint bitmapPaint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.DITHER_FLAG);
    private final Paint cursorFill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint cursorStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path cursorPath = new Path();
    private final float density;
    private final int touchSlop;
    private final float[] mappedPoint = new float[2];
    private final RectF destination = new RectF();

    private volatile boolean running = true;
    private volatile boolean connected;
    private volatile boolean surfaceReady;
    private volatile int pointerMode = MODE_TRACKPAD;
    private volatile float cursorSpeed = 1.35f;
    private volatile int frameWidth;
    private volatile int frameHeight;
    private volatile float cursorX;
    private volatile float cursorY;

    private Thread readerThread;
    private Thread writerThread;
    private LocalSocket socket;
    private DataInputStream input;
    private DataOutputStream output;
    private Bitmap bitmap;
    private Canvas frameCanvas;
    private Bitmap jpegTile;
    private final Rect jpegDestination = new Rect();
    private final Rect jpegSource = new Rect();
    private byte[] tileBytes = new byte[0];
    private int[] tilePixels = new int[0];

    private volatile boolean drawPosted;
    private long lastDraw;
    private final Runnable drawRunnable = () -> {
        drawPosted = false;
        lastDraw = SystemClock.uptimeMillis();
        drawFrame();
    };

    private int touchMode = TOUCH_IDLE;
    private float downX;
    private float downY;
    private float lastX;
    private float lastY;
    private float lastMidX;
    private float lastMidY;
    private float scrollRemainderX;
    private float scrollRemainderY;
    private long gestureStarted;
    private int maximumPointers;
    private boolean gestureMoved;
    private int activePointerId = -1;
    private int composingCodePoints;
    private String composingText = "";

    private final Runnable longPressRunnable = () -> {
        if (!running) return;
        if (touchMode == TOUCH_TRACKPAD_PENDING) {
            touchMode = TOUCH_TRACKPAD_HELD;
            performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        }
    };

    public MicroOSX11View(Context context, Map<?, ?> parameters,
                          MethodChannel channel) {
        super(context);
        this.channel = channel;
        Object path = parameters.get("socketPath");
        this.socketPath = path instanceof String ? (String) path : "";
        density = getResources().getDisplayMetrics().density;
        touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();

        setFocusable(true);
        setFocusableInTouchMode(true);
        setKeepScreenOn(true);
        setBackgroundColor(Color.BLACK);
        setSurfaceTextureListener(this);

        cursorFill.setStyle(Paint.Style.FILL);
        cursorFill.setColor(Color.WHITE);
        cursorStroke.setStyle(Paint.Style.STROKE);
        cursorStroke.setColor(0xFF101820);
        cursorStroke.setStrokeWidth(Math.max(1.2f, 1.4f * density));
        cursorStroke.setStrokeJoin(Paint.Join.ROUND);
        cursorStroke.setStrokeCap(Paint.Cap.ROUND);

        buildCursorPath();

        channel.setMethodCallHandler(this::onMethodCall);
        post(this::requestFocus);

        readerThread = new Thread(this::connectionLoop, "microos-x11-reader");
        readerThread.start();
        writerThread = new Thread(this::writerLoop, "microos-x11-writer");
        writerThread.start();
    }

    private void writerLoop() {
        while (running) {
            byte[] message;
            try {
                message = outgoing.poll(250, TimeUnit.MILLISECONDS);
            } catch (InterruptedException interrupted) {
                break;
            }
            if (message == null) continue;
            synchronized (writeLock) {
                DataOutputStream stream = output;
                if (stream == null || !connected) continue;
                try {
                    stream.write(message);
                    stream.flush();
                } catch (IOException error) {
                    closeSocket();
                    connected = false;
                }
            }
        }
    }

    @NonNull
    @Override
    public android.view.View getView() {
        return this;
    }

    private void buildCursorPath() {
        float scale = Math.max(0.9f, density * 0.82f);
        cursorPath.reset();
        cursorPath.moveTo(0f, 0f);
        cursorPath.lineTo(0f, 19f * scale);
        cursorPath.lineTo(4.9f * scale, 14.7f * scale);
        cursorPath.lineTo(7.9f * scale, 21.2f * scale);
        cursorPath.lineTo(10.9f * scale, 19.7f * scale);
        cursorPath.lineTo(8.0f * scale, 13.3f * scale);
        cursorPath.lineTo(13.8f * scale, 13.3f * scale);
        cursorPath.close();
    }

    private void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "sendKey": {
                Integer keysym = call.argument("keysym");
                Boolean down = call.argument("down");
                if (keysym != null) sendKey(keysym, down == null || down);
                result.success(true);
                break;
            }
            case "sendText": {
                String text = call.argument("text");
                if (text != null && !text.isEmpty()) sendText(text);
                result.success(true);
                break;
            }
            case "rightClick":
                sendPointer(Math.round(cursorX), Math.round(cursorY), 1, 3);
                sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 3);
                result.success(true);
                break;
            case "recenterCursor":
                cursorX = frameWidth / 2f;
                cursorY = frameHeight / 2f;
                sendPointer(Math.round(cursorX), Math.round(cursorY), 0, 0);
                requestDraw();
                result.success(true);
                break;
            case "setPointerMode": {
                String mode = call.argument("mode");
                pointerMode = "direct".equals(mode) ? MODE_DIRECT : MODE_TRACKPAD;
                requestDraw();
                result.success(true);
                break;
            }
            case "setCursorSpeed": {
                Double speed = call.argument("speed");
                if (speed != null) {
                    cursorSpeed = (float) Math.max(0.5, Math.min(3.0, speed));
                }
                result.success(true);
                break;
            }
            case "showKeyboard":
                showKeyboard();
                result.success(true);
                break;
            case "hideKeyboard":
                hideKeyboard();
                result.success(true);
                break;
            case "releaseAll":
                releaseAll();
                result.success(true);
                break;
            case "isConnected":
                result.success(connected);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    @Override
    public boolean onCheckIsTextEditor() {
        return true;
    }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD;
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN
                | EditorInfo.IME_ACTION_NONE;
        return new X11InputConnection();
    }

    private final class X11InputConnection extends BaseInputConnection {
        X11InputConnection() {
            super(MicroOSX11View.this, false);
        }

        @Override
        public boolean commitText(CharSequence text, int newCursorPosition) {
            String committed = text == null ? "" : text.toString();
            if (!composingText.isEmpty()) {
                if (committed.equals(composingText)) {
                    composingText = "";
                    composingCodePoints = 0;
                    return true;
                }
                sendBackspaces(composingCodePoints);
                composingText = "";
                composingCodePoints = 0;
            }
            sendText(committed);
            return true;
        }

        @Override
        public boolean setComposingText(CharSequence text, int newCursorPosition) {
            String next = text == null ? "" : text.toString();
            if (next.equals(composingText)) return true;

            if (!composingText.isEmpty() && next.startsWith(composingText)) {
                sendText(next.substring(composingText.length()));
            } else if (!composingText.isEmpty() && composingText.startsWith(next)) {
                int remove = countCodePoints(composingText.substring(next.length()));
                sendBackspaces(remove);
            } else {
                sendBackspaces(composingCodePoints);
                sendText(next);
            }

            composingText = next;
            composingCodePoints = countCodePoints(next);
            return true;
        }

        @Override
        public boolean finishComposingText() {
            composingText = "";
            composingCodePoints = 0;
            return true;
        }

        @Override
        public boolean deleteSurroundingText(int beforeLength, int afterLength) {
            sendBackspaces(beforeLength);
            for (int index = 0; index < afterLength; index++) {
                sendKey(0xffff, true);
                sendKey(0xffff, false);
            }
            return true;
        }

        @Override
        public boolean sendKeyEvent(KeyEvent event) {
            return handleAndroidKey(event);
        }

        @Override
        public boolean setSelection(int start, int end) {
            return true;
        }
    }

    private static int countCodePoints(String text) {
        if (text == null || text.isEmpty()) return 0;
        return text.codePointCount(0, text.length());
    }

    private void sendBackspaces(int count) {
        for (int index = 0; index < count; index++) {
            sendKey(0xff08, true);
            sendKey(0xff08, false);
        }
    }

    private void showKeyboard() {
        requestFocus();
        setFocusableInTouchMode(true);
        InputMethodManager manager = (InputMethodManager) getContext()
                .getSystemService(Context.INPUT_METHOD_SERVICE);
        if (manager == null) return;
        post(() -> {
            try {
                manager.showSoftInput(MicroOSX11View.this,
                        InputMethodManager.SHOW_IMPLICIT);
            } catch (RuntimeException ignored) {
                // The view can lose its window token while the app is pausing.
            }
        });
    }

    private void hideKeyboard() {
        InputMethodManager manager = (InputMethodManager) getContext()
                .getSystemService(Context.INPUT_METHOD_SERVICE);
        if (manager != null && getWindowToken() != null) {
            manager.hideSoftInputFromWindow(getWindowToken(), 0);
        }
    }

    private void connectionLoop() {
        String lastError = null;
        while (running) {
            LocalSocket candidate = null;
            try {
                candidate = new LocalSocket();
                candidate.connect(new LocalSocketAddress(socketPath,
                        LocalSocketAddress.Namespace.FILESYSTEM));
                candidate.setReceiveBufferSize(1 << 20);
                candidate.setSendBufferSize(1 << 20);
                synchronized (writeLock) {
                    socket = candidate;
                    input = new DataInputStream(new BufferedInputStream(
                            candidate.getInputStream(), 1 << 16));
                    output = new DataOutputStream(candidate.getOutputStream());
                }
                connected = true;
                lastError = null;
                notifyStatus("connected", null);
                readLoop();
            } catch (Exception error) {
                lastError = error.getMessage();
                if (lastError == null) lastError = error.getClass().getSimpleName();
            } catch (OutOfMemoryError error) {
                lastError = "Out of memory while reading the desktop stream";
                Log.e(TAG, lastError, error);
            } finally {
                closeSocket();
                connected = false;
                notifyStatus("disconnected", lastError);
            }
            if (!running) break;
            try {
                Thread.sleep(750);
            } catch (InterruptedException interrupted) {
                break;
            }
        }
    }

    private void readLoop() throws IOException {
        DataInputStream stream = input;
        if (stream == null) return;

        while (running && connected) {
            int type;
            try {
                type = stream.readUnsignedByte();
            } catch (EOFException end) {
                return;
            }
            stream.readUnsignedByte();
            stream.readUnsignedShort();
            long length = stream.readInt() & 0xffffffffL;
            if (length < 0 || length > MAX_MESSAGE) {
                throw new IOException("invalid X11 message length: " + length);
            }

            if (type == MSG_FRAME) {
                readFrame(stream, (int) length);
            } else if (type == MSG_FRAME_JPEG) {
                readFrameJpeg(stream, (int) length);
            } else if (type == MSG_CURSOR) {
                readCursor(stream, (int) length);
            } else if (type == MSG_HELLO) {
                readHello(stream, (int) length);
            } else if (type == MSG_NOTICE) {
                byte[] text = new byte[(int) length];
                stream.readFully(text);
                Log.i(TAG, new String(text, StandardCharsets.UTF_8).trim());
            } else {
                skipFully(stream, length);
            }
        }
    }

    private void readHello(DataInputStream stream, int length) throws IOException {
        if (length != 12) throw new IOException("bad X11 hello length: " + length);
        byte[] payload = new byte[12];
        stream.readFully(payload);
        if (payload[0] != 'M' || payload[1] != 'X'
                || payload[2] != '1' || payload[3] != '1') {
            throw new IOException("native X11 bridge protocol mismatch");
        }
        int version = readU16(payload, 4);
        int width = readU16(payload, 6);
        int height = readU16(payload, 8);
        if (version != 1 || width <= 0 || height <= 0
                || width > MAX_FRAME_DIMENSION || height > MAX_FRAME_DIMENSION
                || (long) width * height > MAX_FRAME_PIXELS) {
            throw new IOException("unsupported native X11 frame: "
                    + width + "x" + height + " v" + version);
        }
        setFrameSize(width, height);
    }

    private void readFrame(DataInputStream stream, int length) throws IOException {
        if (length < 8 || length > MAX_FRAME_MESSAGE) {
            throw new IOException("invalid X11 frame message: " + length);
        }
        byte[] rect = new byte[8];
        stream.readFully(rect);
        int x = readU16(rect, 0);
        int y = readU16(rect, 2);
        int width = readU16(rect, 4);
        int height = readU16(rect, 6);
        long pixelBytesLong = (long) width * (long) height * 4L;
        if (width <= 0 || height <= 0 || pixelBytesLong > MAX_FRAME_MESSAGE
                || length != 8L + pixelBytesLong) {
            throw new IOException("invalid X11 frame rectangle");
        }
        int pixelBytes = (int) pixelBytesLong;
        if (x < 0 || y < 0 || x + width > frameWidth || y + height > frameHeight) {
            skipFully(stream, pixelBytes);
            return;
        }

        if (tileBytes.length < pixelBytes) tileBytes = new byte[pixelBytes];
        if (tilePixels.length < width * height) tilePixels = new int[width * height];
        stream.readFully(tileBytes, 0, pixelBytes);

        for (int index = 0, pixel = 0; index < pixelBytes; index += 4, pixel++) {
            int blue = tileBytes[index] & 0xff;
            int green = tileBytes[index + 1] & 0xff;
            int red = tileBytes[index + 2] & 0xff;
            tilePixels[pixel] = 0xff000000 | (red << 16) | (green << 8) | blue;
        }

        synchronized (bitmapLock) {
            if (bitmap != null && !bitmap.isRecycled()) {
                bitmap.setPixels(tilePixels, 0, width, x, y, width, height);
            }
        }
        requestDraw();
    }

    private void readFrameJpeg(DataInputStream stream, int length)
            throws IOException {
        if (length < 9 || length > MAX_FRAME_MESSAGE) {
            throw new IOException("invalid X11 JPEG frame message: " + length);
        }
        byte[] rect = new byte[8];
        stream.readFully(rect);
        int x = readU16(rect, 0);
        int y = readU16(rect, 2);
        int width = readU16(rect, 4);
        int height = readU16(rect, 6);
        int jpegLength = length - 8;
        if (width <= 0 || height <= 0
                || (long) width * height > MAX_FRAME_PIXELS) {
            skipFully(stream, jpegLength);
            return;
        }
        if (x < 0 || y < 0 || x + width > frameWidth || y + height > frameHeight) {
            skipFully(stream, jpegLength);
            return;
        }

        if (tileBytes.length < jpegLength) tileBytes = new byte[jpegLength];
        stream.readFully(tileBytes, 0, jpegLength);

        Bitmap decoded = decodeJpegTile(jpegLength, width, height);
        if (decoded == null || decoded.isRecycled()) return;

        synchronized (bitmapLock) {
            if (bitmap != null && frameCanvas != null && !bitmap.isRecycled()) {
                jpegDestination.set(x, y, x + width, y + height);
                Rect source = null;
                if (decoded.getWidth() != width || decoded.getHeight() != height) {
                    jpegSource.set(0, 0, width, height);
                    source = jpegSource;
                }
                frameCanvas.drawBitmap(decoded, source, jpegDestination, bitmapPaint);
            }
        }
        requestDraw();
    }

    private Bitmap decodeJpegTile(int jpegLength, int width, int height) {
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        options.inMutable = true;
        synchronized (bitmapLock) {
            Bitmap reusable = jpegTile;
            if (reusable != null && !reusable.isRecycled()
                    && reusable.getWidth() >= width
                    && reusable.getHeight() >= height) {
                options.inBitmap = reusable;
            }
        }

        Bitmap decoded = null;
        try {
            decoded = BitmapFactory.decodeByteArray(tileBytes, 0, jpegLength, options);
        } catch (IllegalArgumentException | OutOfMemoryError firstFailure) {
            options.inBitmap = null;
            options.inMutable = false;
            try {
                decoded = BitmapFactory.decodeByteArray(
                        tileBytes, 0, jpegLength, options);
            } catch (OutOfMemoryError secondFailure) {
                return null;
            }
        }
        if (decoded == null) return null;

        synchronized (bitmapLock) {
            if (jpegTile != null && jpegTile != decoded && !jpegTile.isRecycled()) {
                jpegTile.recycle();
            }
            jpegTile = decoded;
        }
        return decoded;
    }

    private void readCursor(DataInputStream stream, int length) throws IOException {
        if (length < 8) {
            skipFully(stream, length);
            return;
        }
        byte[] payload = new byte[length];
        stream.readFully(payload);
        if (frameWidth <= 0 || frameHeight <= 0) return;
        int x = (short) readU16(payload, 0);
        int y = (short) readU16(payload, 2);
        cursorX = Math.max(0, Math.min(frameWidth - 1, x));
        cursorY = Math.max(0, Math.min(frameHeight - 1, y));
        requestDraw();
    }

    private void setFrameSize(int width, int height) {
        synchronized (bitmapLock) {
            if (width == frameWidth && height == frameHeight && bitmap != null) {
                return;
            }
            Bitmap next;
            try {
                next = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            } catch (IllegalArgumentException | OutOfMemoryError error) {
                Log.e(TAG, "cannot allocate " + width + "x" + height + " frame", error);
                notifyStatus("error", "Not enough memory for the desktop frame");
                return;
            }
            next.eraseColor(0xff0f131b);
            Bitmap old = bitmap;
            bitmap = next;
            if (frameCanvas == null) {
                frameCanvas = new Canvas(next);
            } else {
                frameCanvas.setBitmap(next);
            }
            if (old != null && old != next) old.recycle();
            if (jpegTile != null) {
                jpegTile.recycle();
                jpegTile = null;
            }
            frameWidth = width;
            frameHeight = height;
            cursorX = width / 2f;
            cursorY = height / 2f;
        }
        notifyStatus("connected", null);
        requestDraw();
    }

    private void skipFully(DataInputStream stream, long length) throws IOException {
        long remaining = length;
        while (remaining > 0) {
            long skipped = stream.skip(remaining);
            if (skipped <= 0) {
                if (stream.read() < 0) throw new EOFException();
                skipped = 1;
            }
            remaining -= skipped;
        }
    }

    private void closeSocket() {
        outgoing.clear();
        synchronized (writeLock) {
            output = null;
            input = null;
            if (socket != null) {
                try {
                    socket.close();
                } catch (IOException ignored) {
                }
                socket = null;
            }
        }
    }

    private void writeMessage(byte[] message) {
        if (!connected) return;
        if (!outgoing.offer(message)) {
            outgoing.poll();
            outgoing.offer(message);
        }
    }

    private static void putU16(byte[] data, int offset, int value) {
        data[offset] = (byte) (value >> 8);
        data[offset + 1] = (byte) value;
    }

    private static void putU32(byte[] data, int offset, int value) {
        data[offset] = (byte) (value >> 24);
        data[offset + 1] = (byte) (value >> 16);
        data[offset + 2] = (byte) (value >> 8);
        data[offset + 3] = (byte) value;
    }

    private static int readU16(byte[] data, int offset) {
        return ((data[offset] & 0xff) << 8) | (data[offset + 1] & 0xff);
    }

    private static byte[] message(int type, int payloadLength) {
        byte[] data = new byte[8 + payloadLength];
        data[0] = (byte) type;
        putU32(data, 4, payloadLength);
        return data;
    }

    private void sendPointer(int x, int y, int action, int button) {
        byte[] data = message(MSG_POINTER, 6);
        putU16(data, 8, clamp(x, 0, Math.max(0, frameWidth - 1)));
        putU16(data, 10, clamp(y, 0, Math.max(0, frameHeight - 1)));
        data[12] = (byte) action;
        data[13] = (byte) button;
        writeMessage(data);
    }

    private void sendWheel(int x, int y, int dx, int dy) {
        byte[] data = message(MSG_WHEEL, 8);
        putU16(data, 8, clamp(x, 0, Math.max(0, frameWidth - 1)));
        putU16(data, 10, clamp(y, 0, Math.max(0, frameHeight - 1)));
        putU16(data, 12, dx);
        putU16(data, 14, dy);
        writeMessage(data);
    }

    private void sendKey(int keysym, boolean down) {
        byte[] data = message(MSG_KEY, 6);
        putU32(data, 8, keysym);
        data[12] = (byte) (down ? 1 : 0);
        data[13] = 0;
        writeMessage(data);
    }

    private void sendText(String text) {
        if (text == null || text.isEmpty()) return;
        byte[] payload = text.getBytes(StandardCharsets.UTF_8);
        byte[] data = message(MSG_TEXT, payload.length);
        System.arraycopy(payload, 0, data, 8, payload.length);
        writeMessage(data);
    }

    private void releaseAll() {
        writeMessage(message(MSG_RELEASE, 0));
    }

    private void notifyStatus(String state, @Nullable String message) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("state", state);
        if (message != null) payload.put("message", message);
        if (frameWidth > 0) {
            payload.put("width", frameWidth);
            payload.put("height", frameHeight);
        }
        mainHandler.post(() -> {
            try {
                channel.invokeMethod("status", payload);
            } catch (Exception ignored) {
            }
        });
    }

    private void notifyThreeFingerTap() {
        mainHandler.post(() -> {
            try {
                channel.invokeMethod("threeFingerTap", null);
            } catch (Exception ignored) {
            }
        });
    }

    private static int clamp(int value, int minimum, int maximum) {
        if (maximum < minimum) return minimum;
        if (value < minimum) return minimum;
        if (value > maximum) return maximum;
        return value;
    }

    private static float clamp(float value, float minimum, float maximum) {
        if (maximum < minimum) return minimum;
        if (value < minimum) return minimum;
        if (value > maximum) return maximum;
        return value;
    }

    private void computeDestination(RectF out) {
        int viewWidth = getWidth();
        int viewHeight = getHeight();
        int width = frameWidth;
        int height = frameHeight;
        if (viewWidth <= 0 || viewHeight <= 0 || width <= 0 || height <= 0) {
            out.setEmpty();
            return;
        }
        float scale = Math.min((float) viewWidth / width,
                (float) viewHeight / height);
        float displayWidth = width * scale;
        float displayHeight = height * scale;
        float left = (viewWidth - displayWidth) / 2f;
        float top = (viewHeight - displayHeight) / 2f;
        out.set(left, top, left + displayWidth, top + displayHeight);
    }

    private void mapToFrame(float screenX, float screenY) {
        computeDestination(destination);
        if (destination.isEmpty()) {
            mappedPoint[0] = 0;
            mappedPoint[1] = 0;
            return;
        }
        mappedPoint[0] = clamp((screenX - destination.left)
                / destination.width() * frameWidth, 0, frameWidth - 1);
        mappedPoint[1] = clamp((screenY - destination.top)
                / destination.height() * frameHeight, 0, frameHeight - 1);
    }

    private void requestDraw() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            drawFrame();
            return;
        }
        if (drawPosted) return;
        drawPosted = true;
        long delay = 16 - (SystemClock.uptimeMillis() - lastDraw);
        mainHandler.postDelayed(drawRunnable, Math.max(0, delay));
    }

    private void drawFrame() {
        try {
            synchronized (drawLock) {
                if (!surfaceReady || !running) return;
                if (!isAvailable()) return;
                Canvas canvas;
                try {
                    canvas = lockCanvas();
                } catch (Exception error) {
                    return;
                }
                if (canvas == null) return;
                try {
                    canvas.drawColor(0xff0b0e14);
                    synchronized (bitmapLock) {
                        Bitmap current = bitmap;
                        if (current != null && !current.isRecycled()) {
                            computeDestination(destination);
                            if (!destination.isEmpty()) {
                                canvas.drawBitmap(current, null, destination, bitmapPaint);
                                if (pointerMode == MODE_TRACKPAD) {
                                    drawCursor(canvas, destination);
                                }
                            }
                        }
                    }
                } finally {
                    try {
                        unlockCanvasAndPost(canvas);
                    } catch (Exception ignored) {
                        // The surface can be torn down between lock and post.
                    }
                }
            }
        } catch (Exception error) {
            // A failed frame must never terminate the Android UI thread.
            Log.w(TAG, "frame draw skipped", error);
        }
    }

    private void drawCursor(Canvas canvas, RectF destination) {
        float x = destination.left + cursorX / frameWidth * destination.width();
        float y = destination.top + cursorY / frameHeight * destination.height();
        canvas.save();
        canvas.translate(x, y);
        canvas.drawPath(cursorPath, cursorFill);
        canvas.drawPath(cursorPath, cursorStroke);
        canvas.restore();
    }

    @Override
    public void onSurfaceTextureAvailable(@NonNull SurfaceTexture surface,
                                          int width, int height) {
        surfaceReady = true;
        drawFrame();
    }

    @Override
    public void onSurfaceTextureSizeChanged(@NonNull SurfaceTexture surface,
                                            int width, int height) {
        surfaceReady = true;
        requestDraw();
    }

    @Override
    public boolean onSurfaceTextureDestroyed(@NonNull SurfaceTexture surface) {
        surfaceReady = false;
        return true;
    }

    @Override
    public void onSurfaceTextureUpdated(@NonNull SurfaceTexture surface) {
        // Frames are pushed by the reader thread through lockCanvas().
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (!running || frameWidth <= 0 || frameHeight <= 0) return true;
        requestFocus();

        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
            maximumPointers = 1;
            gestureStarted = SystemClock.uptimeMillis();
            gestureMoved = false;
            scrollRemainderX = 0;
            scrollRemainderY = 0;
            activePointerId = event.getPointerId(0);
            downX = lastX = event.getX(0);
            downY = lastY = event.getY(0);
            if (pointerMode == MODE_DIRECT) {
                startDirect(event);
            } else {
                touchMode = TOUCH_TRACKPAD_PENDING;
                mainHandler.postDelayed(longPressRunnable, 470);
            }
            return true;
        }

        if (action == MotionEvent.ACTION_POINTER_DOWN) {
            maximumPointers = Math.max(maximumPointers, event.getPointerCount());
            mainHandler.removeCallbacks(longPressRunnable);
            if (touchMode == TOUCH_DIRECT) {
                sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 1);
            } else if (touchMode == TOUCH_TRACKPAD_DRAG) {
                sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 1);
            }
            touchMode = TOUCH_SCROLL;
            gestureStarted = SystemClock.uptimeMillis();
            gestureMoved = false;
            lastMidX = (event.getX(0) + event.getX(1)) / 2f;
            lastMidY = (event.getY(0) + event.getY(1)) / 2f;
            return true;
        }

        if (action == MotionEvent.ACTION_MOVE) {
            if (touchMode == TOUCH_SCROLL) {
                int pointerCount = event.getPointerCount();
                if (pointerCount >= 2) {
                    float midX = (event.getX(0) + event.getX(1)) / 2f;
                    float midY = (event.getY(0) + event.getY(1)) / 2f;
                    float deltaX = lastMidX - midX;
                    float deltaY = lastMidY - midY;
                    if (Math.abs(deltaX) + Math.abs(deltaY) > 1f) {
                        gestureMoved = true;
                    }
                    scrollRemainderX += deltaX * 0.34f;
                    scrollRemainderY += deltaY * 0.34f;
                    int stepsX = (int) scrollRemainderX;
                    int stepsY = (int) scrollRemainderY;
                    scrollRemainderX -= stepsX;
                    scrollRemainderY -= stepsY;
                    if (stepsX != 0 || stepsY != 0) {
                        mapToFrame(midX, midY);
                        sendWheel(Math.round(mappedPoint[0]),
                                Math.round(mappedPoint[1]), stepsX, stepsY);
                    }
                    lastMidX = midX;
                    lastMidY = midY;
                }
                return true;
            }

            if (event.getPointerCount() != 1) return true;
            float x = event.getX(0);
            float y = event.getY(0);
            float dx = x - lastX;
            float dy = y - lastY;
            float distance = (float) Math.hypot(x - downX, y - downY);
            if (distance > touchSlop) gestureMoved = true;

            if (touchMode == TOUCH_TRACKPAD_PENDING) {
                if (distance <= touchSlop) return true;
                mainHandler.removeCallbacks(longPressRunnable);
                touchMode = TOUCH_TRACKPAD_MOVE;
            }

            if (touchMode == TOUCH_TRACKPAD_HELD) {
                if (distance <= touchSlop) return true;
                touchMode = TOUCH_TRACKPAD_DRAG;
                sendPointer(Math.round(cursorX), Math.round(cursorY), 1, 1);
            }

            if (touchMode == TOUCH_TRACKPAD_MOVE
                    || touchMode == TOUCH_TRACKPAD_DRAG) {
                computeDestination(destination);
                if (!destination.isEmpty()) {
                    float scaleX = frameWidth / destination.width() * cursorSpeed;
                    float scaleY = frameHeight / destination.height() * cursorSpeed;
                    cursorX = clamp(cursorX + dx * scaleX, 0, frameWidth - 1);
                    cursorY = clamp(cursorY + dy * scaleY, 0, frameHeight - 1);
                    sendPointer(Math.round(cursorX), Math.round(cursorY), 0, 0);
                    requestDraw();
                }
                lastX = x;
                lastY = y;
                return true;
            }

            if (touchMode == TOUCH_DIRECT) {
                mapToFrame(x, y);
                cursorX = mappedPoint[0];
                cursorY = mappedPoint[1];
                sendPointer(Math.round(cursorX), Math.round(cursorY), 0, 0);
                lastX = x;
                lastY = y;
                return true;
            }
            return true;
        }

        if (action == MotionEvent.ACTION_UP
                || action == MotionEvent.ACTION_CANCEL) {
            mainHandler.removeCallbacks(longPressRunnable);
            boolean cancelled = action == MotionEvent.ACTION_CANCEL;

            if (touchMode == TOUCH_SCROLL) {
                long elapsed = SystemClock.uptimeMillis() - gestureStarted;
                if (!cancelled && maximumPointers >= 3 && elapsed < 420
                        && !gestureMoved) {
                    notifyThreeFingerTap();
                } else if (!cancelled && elapsed < 320 && !gestureMoved) {
                    mapToFrame(event.getX(0), event.getY(0));
                    int clickX = pointerMode == MODE_TRACKPAD
                            ? Math.round(cursorX) : Math.round(mappedPoint[0]);
                    int clickY = pointerMode == MODE_TRACKPAD
                            ? Math.round(cursorY) : Math.round(mappedPoint[1]);
                    sendPointer(clickX, clickY, 1, 3);
                    sendPointer(clickX, clickY, 2, 3);
                }
                touchMode = TOUCH_IDLE;
                gestureMoved = false;
                return true;
            }

            if (cancelled) {
                if (touchMode == TOUCH_DIRECT) {
                    sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 1);
                } else if (touchMode == TOUCH_TRACKPAD_DRAG) {
                    sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 1);
                }
                touchMode = TOUCH_IDLE;
                return true;
            }

            if (touchMode == TOUCH_TRACKPAD_PENDING) {
                sendPointer(Math.round(cursorX), Math.round(cursorY), 1, 1);
                sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 1);
            } else if (touchMode == TOUCH_TRACKPAD_HELD) {
                sendPointer(Math.round(cursorX), Math.round(cursorY), 1, 3);
                sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 3);
            } else if (touchMode == TOUCH_TRACKPAD_DRAG) {
                sendPointer(Math.round(cursorX), Math.round(cursorY), 2, 1);
            } else if (touchMode == TOUCH_DIRECT) {
                mapToFrame(event.getX(0), event.getY(0));
                sendPointer(Math.round(mappedPoint[0]),
                        Math.round(mappedPoint[1]), 2, 1);
            }
            touchMode = TOUCH_IDLE;
            gestureMoved = false;
            return true;
        }

        return true;
    }

    private void startDirect(MotionEvent event) {
        mapToFrame(event.getX(0), event.getY(0));
        cursorX = mappedPoint[0];
        cursorY = mappedPoint[1];
        touchMode = TOUCH_DIRECT;
        sendPointer(Math.round(cursorX), Math.round(cursorY), 0, 0);
        sendPointer(Math.round(cursorX), Math.round(cursorY), 1, 1);
        requestDraw();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (handleAndroidKey(event)) return true;
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (handleAndroidKey(event)) return true;
        return super.onKeyUp(keyCode, event);
    }

    private boolean handleAndroidKey(KeyEvent event) {
        int action = event.getAction();
        if (action == KeyEvent.ACTION_MULTIPLE) {
            String characters = event.getCharacters();
            if (characters != null && !characters.isEmpty()) sendText(characters);
            return true;
        }
        if (action != KeyEvent.ACTION_DOWN && action != KeyEvent.ACTION_UP) {
            return false;
        }
        boolean down = action == KeyEvent.ACTION_DOWN;
        int keyCode = event.getKeyCode();

        Integer keysym = keysymForAndroidKey(keyCode, event);
        if (keysym != null) {
            if (keysym != 0) sendKey(keysym, down);
            return true;
        }
        return false;
    }

    @Nullable
    private Integer keysymForAndroidKey(int keyCode, KeyEvent event) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_ESCAPE: return 0xff1b;
            case KeyEvent.KEYCODE_TAB: return 0xff09;
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER: return 0xff0d;
            case KeyEvent.KEYCODE_DEL: return 0xff08;
            case KeyEvent.KEYCODE_FORWARD_DEL: return 0xffff;
            case KeyEvent.KEYCODE_DPAD_LEFT: return 0xff51;
            case KeyEvent.KEYCODE_DPAD_UP: return 0xff52;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 0xff53;
            case KeyEvent.KEYCODE_DPAD_DOWN: return 0xff54;
            case KeyEvent.KEYCODE_MOVE_HOME: return 0xff50;
            case KeyEvent.KEYCODE_MOVE_END: return 0xff57;
            case KeyEvent.KEYCODE_PAGE_UP: return 0xff55;
            case KeyEvent.KEYCODE_PAGE_DOWN: return 0xff56;
            case KeyEvent.KEYCODE_CTRL_LEFT: return 0xffe3;
            case KeyEvent.KEYCODE_CTRL_RIGHT: return 0xffe4;
            case KeyEvent.KEYCODE_SHIFT_LEFT: return 0xffe1;
            case KeyEvent.KEYCODE_SHIFT_RIGHT: return 0xffe2;
            case KeyEvent.KEYCODE_ALT_LEFT: return 0xffe9;
            case KeyEvent.KEYCODE_ALT_RIGHT: return 0xffea;
            case KeyEvent.KEYCODE_META_LEFT: return 0xffeb;
            case KeyEvent.KEYCODE_META_RIGHT: return 0xffec;
            case KeyEvent.KEYCODE_CAPS_LOCK: return 0xffe5;
            case KeyEvent.KEYCODE_SPACE: return 0x20;
            case KeyEvent.KEYCODE_F1: return 0xffbe;
            case KeyEvent.KEYCODE_F2: return 0xffbf;
            case KeyEvent.KEYCODE_F3: return 0xffc0;
            case KeyEvent.KEYCODE_F4: return 0xffc1;
            case KeyEvent.KEYCODE_F5: return 0xffc2;
            case KeyEvent.KEYCODE_F6: return 0xffc3;
            case KeyEvent.KEYCODE_F7: return 0xffc4;
            case KeyEvent.KEYCODE_F8: return 0xffc5;
            case KeyEvent.KEYCODE_F9: return 0xffc6;
            case KeyEvent.KEYCODE_F10: return 0xffc7;
            case KeyEvent.KEYCODE_F11: return 0xffc8;
            case KeyEvent.KEYCODE_F12: return 0xffc9;
            case KeyEvent.KEYCODE_MINUS: return 0x2d;
            case KeyEvent.KEYCODE_EQUALS: return 0x3d;
            case KeyEvent.KEYCODE_LEFT_BRACKET: return 0x5b;
            case KeyEvent.KEYCODE_RIGHT_BRACKET: return 0x5d;
            case KeyEvent.KEYCODE_BACKSLASH: return 0x5c;
            case KeyEvent.KEYCODE_SEMICOLON: return 0x3b;
            case KeyEvent.KEYCODE_APOSTROPHE: return 0x27;
            case KeyEvent.KEYCODE_GRAVE: return 0x60;
            case KeyEvent.KEYCODE_COMMA: return 0x2c;
            case KeyEvent.KEYCODE_PERIOD: return 0x2e;
            case KeyEvent.KEYCODE_SLASH: return 0x2f;
            default:
                break;
        }

        if (keyCode >= KeyEvent.KEYCODE_A && keyCode <= KeyEvent.KEYCODE_Z) {
            return keyCode - KeyEvent.KEYCODE_A + 'a';
        }
        if (keyCode >= KeyEvent.KEYCODE_0 && keyCode <= KeyEvent.KEYCODE_9) {
            return keyCode - KeyEvent.KEYCODE_0 + '0';
        }
        if (keyCode >= KeyEvent.KEYCODE_NUMPAD_0
                && keyCode <= KeyEvent.KEYCODE_NUMPAD_9) {
            return keyCode - KeyEvent.KEYCODE_NUMPAD_0 + '0';
        }

        int character = event.getUnicodeChar();
        if (character > 0) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                sendText(new String(Character.toChars(character)));
            }
            return 0;
        }
        return null;
    }

    @Override
    public void dispose() {
        if (!running) return;
        running = false;
        mainHandler.removeCallbacksAndMessages(null);
        closeSocket();
        if (readerThread != null) {
            readerThread.interrupt();
            readerThread = null;
        }
        if (writerThread != null) {
            writerThread.interrupt();
            writerThread = null;
        }
        synchronized (bitmapLock) {
            if (frameCanvas != null) {
                frameCanvas.setBitmap(null);
                frameCanvas = null;
            }
            if (jpegTile != null) {
                jpegTile.recycle();
                jpegTile = null;
            }
            if (bitmap != null) {
                bitmap.recycle();
                bitmap = null;
            }
        }
        channel.setMethodCallHandler(null);
    }
}
