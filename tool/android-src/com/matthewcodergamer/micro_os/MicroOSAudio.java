package com.matthewcodergamer.micro_os;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.Nullable;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Plays the guest's PulseAudio output through an Android AudioTrack.
 *
 * The guest-side microos-audio bridge drains a PulseAudio pipe sink and mirrors
 * 48 kHz stereo s16le PCM over a Unix socket. Keeping this path native avoids
 * WebAudio, browser codecs and the latency of resampling in the WebView.
 */
public final class MicroOSAudio {
    private static final String TAG = "MicroOSAudio";
    private static final int MSG_AUDIO = 1;
    private static final int MSG_HELLO = 5;
    private static final int MAX_AUDIO_MESSAGE = 4 * 1024 * 1024;

    private final MethodChannel channel;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Object lock = new Object();
    private final byte[] pcm = new byte[16 * 1024];

    private volatile boolean running;
    private volatile boolean connected;
    private volatile String socketPath = "";
    private volatile float volume = 1f;
    private volatile int sampleRate = 48000;
    private volatile int channels = 2;
    private volatile int generation;

    private volatile Thread worker;
    private LocalSocket socket;
    private AudioTrack track;

    MicroOSAudio(BinaryMessenger messenger) {
        channel = new MethodChannel(messenger, "microos/audio");
        channel.setMethodCallHandler(this::onMethodCall);
    }

    private void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "start": {
                String path = call.argument("socketPath");
                if (path == null || path.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "socketPath is required", null);
                    return;
                }
                start(path);
                result.success(true);
                break;
            }
            case "stop":
                stop();
                result.success(true);
                break;
            case "setVolume": {
                Double requested = call.argument("volume");
                if (requested != null) {
                    setVolume((float) Math.max(0.0, Math.min(1.0, requested)));
                }
                result.success(true);
                break;
            }
            case "isRunning":
                result.success(connected);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void start(String path) {
        final int id;
        synchronized (lock) {
            if (running && path.equals(socketPath)) return;
            running = false;
            closeSocketLocked();
            socketPath = path;
            running = true;
            id = ++generation;
        }
        worker = new Thread(() -> audioLoop(id), "microos-audio");
        worker.start();
    }

    private void stop() {
        AudioTrack player;
        synchronized (lock) {
            running = false;
            generation++;
            player = track;
            track = null;
            closeSocketLocked();
        }
        releaseTrack(player);
        Thread current = worker;
        if (current != null && current != Thread.currentThread()) {
            current.interrupt();
        }
        worker = null;
        connected = false;
        notifyStatus("disconnected", "Audio stopped");
    }

    private void setVolume(float value) {
        volume = value;
        AudioTrack current;
        synchronized (lock) {
            current = track;
        }
        if (current != null) {
            try {
                current.setVolume(value);
            } catch (IllegalStateException ignored) {
                // The reader thread is replacing the track.
            }
        }
    }

    private void audioLoop(int id) {
        while (running && id == generation) {
            LocalSocket connection = null;
            AudioTrack player = null;
            String failure = null;
            try {
                connection = new LocalSocket();
                connection.connect(new LocalSocketAddress(socketPath,
                        LocalSocketAddress.Namespace.FILESYSTEM));
                connection.setReceiveBufferSize(256 * 1024);
                DataInputStream input = new DataInputStream(
                        new BufferedInputStream(connection.getInputStream(), 32 * 1024));

                readHello(input);
                player = createTrack(sampleRate, channels);
                synchronized (lock) {
                    if (!running || id != generation) break;
                    socket = connection;
                    track = player;
                }
                player.play();
                connected = true;
                notifyStatus("connected", null);

                while (running && id == generation) {
                    int type = input.readUnsignedByte();
                    input.readUnsignedByte();
                    input.readUnsignedShort();
                    long length = input.readInt() & 0xffffffffL;
                    if (length > MAX_AUDIO_MESSAGE) {
                        throw new IOException("invalid audio message length: " + length);
                    }
                    if (type == MSG_AUDIO) {
                        long remaining = length;
                        while (remaining > 0 && running && id == generation) {
                            int chunk = (int) Math.min(remaining, pcm.length);
                            input.readFully(pcm, 0, chunk);
                            int offset = 0;
                            while (offset < chunk && running && id == generation) {
                                int written = player.write(pcm, offset, chunk - offset);
                                if (written < 0) {
                                    throw new IOException(
                                            "AudioTrack write failed: " + written);
                                }
                                if (written == 0) {
                                    Thread.yield();
                                    continue;
                                }
                                offset += written;
                            }
                            remaining -= chunk;
                        }
                    } else {
                        skipFully(input, length);
                    }
                }
            } catch (Exception error) {
                failure = error.getMessage();
                if (failure == null) failure = error.getClass().getSimpleName();
            } finally {
                if (id == generation) connected = false;
                synchronized (lock) {
                    if (track == player) track = null;
                    if (socket == connection) socket = null;
                }
                releaseTrack(player);
                if (connection != null) {
                    try {
                        connection.close();
                    } catch (IOException ignored) {
                    }
                }
                if (running && id == generation) {
                    notifyStatus("disconnected", failure);
                }
            }
            if (!running || id != generation) break;
            try {
                Thread.sleep(750);
            } catch (InterruptedException interrupted) {
                break;
            }
        }
        if (id == generation) {
            connected = false;
            notifyStatus("disconnected", null);
        }
    }
    private void readHello(DataInputStream input) throws IOException {
        int type = input.readUnsignedByte();
        input.readUnsignedByte();
        input.readUnsignedShort();
        long length = input.readInt() & 0xffffffffL;
        if (type != MSG_HELLO || length != 12) {
            throw new IOException("native audio protocol mismatch");
        }
        byte[] hello = new byte[12];
        input.readFully(hello);
        if (hello[0] != 'M' || hello[1] != 'X'
                || hello[2] != 'A' || hello[3] != 'U') {
            throw new IOException("native audio handshake mismatch");
        }
        int version = readU16(hello, 4);
        int rate = readU16(hello, 6);
        int channelCount = hello[8] & 0xff;
        int bits = hello[9] & 0xff;
        if (version != 1 || bits != 16
                || (channelCount != 1 && channelCount != 2)
                || rate < 8000 || rate > 192000) {
            throw new IOException("unsupported audio stream: "
                    + rate + " Hz, " + channelCount + " ch, " + bits + " bit");
        }
        sampleRate = rate;
        channels = channelCount;
    }

    private AudioTrack createTrack(int rate, int channelCount) throws IOException {
        int channelMask = channelCount == 1
                ? AudioFormat.CHANNEL_OUT_MONO
                : AudioFormat.CHANNEL_OUT_STEREO;
        int minimum = AudioTrack.getMinBufferSize(
                rate, channelMask, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0) minimum = rate * channelCount;
        int target = Math.max(minimum, (rate / 50) * channelCount * 2 * 3);
        AudioTrack player;
        try {
            player = new AudioTrack.Builder()
                    .setAudioAttributes(new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                            .build())
                    .setAudioFormat(new AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(rate)
                            .setChannelMask(channelMask)
                            .build())
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .setBufferSizeInBytes(target)
                    .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                    .build();
        } catch (IllegalArgumentException | UnsupportedOperationException error) {
            throw new IOException("cannot create AudioTrack: " + error.getMessage(), error);
        }
        if (player.getState() != AudioTrack.STATE_INITIALIZED) {
            player.release();
            throw new IOException("AudioTrack did not initialize");
        }
        player.setVolume(volume);
        return player;
    }

    private static void releaseTrack(@Nullable AudioTrack player) {
        if (player == null) return;
        try {
            player.pause();
            player.flush();
        } catch (IllegalStateException ignored) {
        }
        try {
            player.release();
        } catch (IllegalStateException ignored) {
        }
    }

    private void closeSocketLocked() {
        if (socket != null) {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
            socket = null;
        }
    }

    private static int readU16(byte[] data, int offset) {
        return ((data[offset] & 0xff) << 8) | (data[offset + 1] & 0xff);
    }

    private static void skipFully(DataInputStream input, long length)
            throws IOException {
        long remaining = length;
        while (remaining > 0) {
            long skipped = input.skip(remaining);
            if (skipped <= 0) {
                if (input.read() < 0) throw new EOFException();
                skipped = 1;
            }
            remaining -= skipped;
        }
    }

    private void notifyStatus(String state, @Nullable String message) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("state", state);
        payload.put("sampleRate", sampleRate);
        payload.put("channels", channels);
        if (message != null) payload.put("message", message);
        mainHandler.post(() -> {
            try {
                channel.invokeMethod("status", payload);
            } catch (Exception ignored) {
            }
        });
    }

    void dispose() {
        stop();
        channel.setMethodCallHandler(null);
    }
}
