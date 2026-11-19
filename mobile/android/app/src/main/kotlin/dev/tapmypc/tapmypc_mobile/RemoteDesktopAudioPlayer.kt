package dev.tapmypc.tapmypc_mobile

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaFormat
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

internal class RemoteDesktopAudioPlayer(private val onError: () -> Unit) {
    private val packets = ArrayBlockingQueue<ByteArray>(8)
    private val worker = Thread(::play, "TapMyPC audio playback")

    fun start() = worker.start()

    fun offer(packet: ByteArray) {
        if (!packets.offer(packet)) {
            packets.poll()
            packets.offer(packet)
        }
    }

    fun stop() {
        worker.interrupt()
        packets.clear()
    }

    private fun play() {
        try {
            val decoder = MediaCodec.createDecoderByType("audio/opus")
            try {
                decoder.configure(opusFormat(), null, null, 0)
                decoder.start()
                val output = createTrack()
                try {
                    output.play()
                    decode(decoder, output)
                } finally {
                    output.release()
                }
            } finally {
                decoder.release()
            }
        } catch (_: InterruptedException) {
            // The viewer disabled audio or closed.
        } catch (_: IOException) {
            onError()
        } catch (_: RuntimeException) {
            onError()
        }
    }

    private fun opusFormat(): MediaFormat {
        val header = ByteBuffer.allocate(19).order(ByteOrder.LITTLE_ENDIAN)
            .put("OpusHead".toByteArray(Charsets.US_ASCII))
            .put(1.toByte()).put(CHANNELS.toByte()).putShort(0.toShort())
            .putInt(SAMPLE_RATE).putShort(0.toShort()).put(0.toByte())
        header.rewind()
        return MediaFormat.createAudioFormat("audio/opus", SAMPLE_RATE, CHANNELS).apply {
            setByteBuffer("csd-0", header)
            setByteBuffer("csd-1", nanoseconds(0))
            setByteBuffer("csd-2", nanoseconds(80_000_000))
        }
    }

    private fun nanoseconds(value: Long): ByteBuffer =
        ByteBuffer.allocate(8).order(ByteOrder.nativeOrder()).putLong(0, value)

    private fun createTrack(): AudioTrack {
        val channelMask = AudioFormat.CHANNEL_OUT_STEREO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minimum = AudioTrack.getMinBufferSize(SAMPLE_RATE, channelMask, encoding)
        check(minimum > 0) { "Unsupported PCM format" }
        return AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build())
            .setAudioFormat(AudioFormat.Builder()
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(channelMask)
                .setEncoding(encoding)
                .build())
            .setBufferSizeInBytes(maxOf(minimum, 2 * PCM_FRAME_BYTES))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
    }

    private fun decode(decoder: MediaCodec, output: AudioTrack) {
        val info = MediaCodec.BufferInfo()
        var presentationTime = 0L
        while (!worker.isInterrupted) {
            val packet = packets.poll(10, TimeUnit.MILLISECONDS)
            if (packet != null) {
                val index = decoder.dequeueInputBuffer(5_000)
                if (index >= 0) {
                    val input = checkNotNull(decoder.getInputBuffer(index))
                    input.clear()
                    input.put(packet)
                    decoder.queueInputBuffer(index, 0, packet.size, presentationTime, 0)
                    presentationTime += 20_000
                }
            }
            while (!worker.isInterrupted) {
                val index = decoder.dequeueOutputBuffer(info, 0)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val format = decoder.outputFormat
                    check(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) == SAMPLE_RATE)
                    check(format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == CHANNELS)
                    continue
                }
                if (index < 0) break
                try {
                    if (info.size > 0) {
                        val pcm = checkNotNull(decoder.getOutputBuffer(index))
                        pcm.position(info.offset)
                        pcm.limit(info.offset + info.size)
                        writePcm(output, pcm)
                    }
                } finally {
                    decoder.releaseOutputBuffer(index, false)
                }
            }
        }
    }

    private fun writePcm(output: AudioTrack, pcm: ByteBuffer) {
        while (pcm.hasRemaining() && !worker.isInterrupted) {
            val written = output.write(pcm, pcm.remaining(), AudioTrack.WRITE_NON_BLOCKING)
            check(written >= 0) { "Android audio output failed" }
            if (written == 0) Thread.sleep(2)
        }
    }

    private companion object {
        const val SAMPLE_RATE = 48_000
        const val CHANNELS = 2
        const val PCM_FRAME_BYTES = SAMPLE_RATE / 50 * CHANNELS * 2
    }
}
