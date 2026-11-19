using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using Concentus;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using TapMyPC.Core.Audio;

namespace TapMyPC.Windows.Audio;

public sealed class WindowsRemoteDesktopAudio : IRemoteDesktopAudioSource
{
    private const int SampleRate = 48000;
    private const int Channels = 2;
    private const int SamplesPerChannel = SampleRate / 50;
    private const int MaxOpusPacketBytes = 1275;

    public async IAsyncEnumerable<ReadOnlyMemory<byte>> CaptureAsync([EnumeratorCancellation] CancellationToken stop)
    {
        using var captureStop = CancellationTokenSource.CreateLinkedTokenSource(stop);
        var frames = Channel.CreateBounded<ReadOnlyMemory<byte>>(new BoundedChannelOptions(8)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleWriter = true
        });
        var recording = RecordDefaultOutputAsync(frames, captureStop.Token);
        try
        {
            await foreach (var frame in frames.Reader.ReadAllAsync(stop)) yield return frame;
        }
        finally
        {
            await captureStop.CancelAsync();
            await recording;
        }
    }

    private static async Task RecordDefaultOutputAsync(Channel<ReadOnlyMemory<byte>> frames, CancellationToken stop)
    {
        try
        {
            using var devices = new MMDeviceEnumerator();
            using var notifications = devices.CreateNotificationClient(useSynchronizationContext: false);
            var changes = Channel.CreateBounded<bool>(1);
            notifications.DefaultDeviceChanged += (_, change) =>
            {
                if (change.Flow == DataFlow.Render && change.Role == Role.Multimedia)
                    changes.Writer.TryWrite(true);
            };

            using var encoder = OpusCodecFactory.CreateEncoder(SampleRate, Channels);
            encoder.Bitrate = 96000;
            encoder.Complexity = 4;

            while (!stop.IsCancellationRequested)
            {
                changes.Reader.TryRead(out _);
                if (!devices.TryGetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia, out var output))
                {
                    // Switching or reconnecting a USB output can briefly leave no default endpoint.
                    await changes.Reader.ReadAsync(stop).AsTask().WaitAsync(TimeSpan.FromSeconds(2), stop);
                    continue;
                }

                using (output)
                {
                    await RecordEndpointAsync(output, encoder, frames.Writer, changes.Reader, stop);
                }
                while (frames.Reader.TryRead(out _)) { }
            }
            frames.Writer.TryComplete();
        }
        catch (OperationCanceledException) when (stop.IsCancellationRequested)
        {
            frames.Writer.TryComplete();
        }
        catch (Exception ex)
        {
            frames.Writer.TryComplete(new InvalidOperationException("Could not capture the default audio output.", ex));
        }
    }

    private static async Task RecordEndpointAsync(MMDevice output, IOpusEncoder encoder,
        ChannelWriter<ReadOnlyMemory<byte>> frames, ChannelReader<bool> changes, CancellationToken stop)
    {
        await using var recorder = new WasapiRecorderBuilder()
            .WithDevice(output)
            .WithLoopbackCapture()
            .WithFormat(new WaveFormat(SampleRate, 16, Channels))
            .WithBufferLength(40)
            .Build();

        var encoderInput = new short[SamplesPerChannel * Channels];
        var encoderOutput = new byte[MaxOpusPacketBytes];
        var samplesBuffered = 0;
        recorder.DataAvailable += (data, _, _, _) =>
        {
            var samples = MemoryMarshal.Cast<byte, short>(data);
            while (!samples.IsEmpty && !stop.IsCancellationRequested)
            {
                var length = Math.Min(samples.Length, encoderInput.Length - samplesBuffered);
                samples[..length].CopyTo(encoderInput.AsSpan(samplesBuffered));
                samplesBuffered += length;
                samples = samples[length..];
                if (samplesBuffered != encoderInput.Length) continue;

                var size = encoder.Encode(encoderInput, SamplesPerChannel, encoderOutput, encoderOutput.Length);
                frames.TryWrite(encoderOutput.AsSpan(0, size).ToArray());
                samplesBuffered = 0;
            }
        };

        var ended = new TaskCompletionSource<Exception?>(TaskCreationOptions.RunContinuationsAsynchronously);
        recorder.RecordingStopped += (_, args) => ended.TrySetResult(args.Exception);
        using var switchWait = CancellationTokenSource.CreateLinkedTokenSource(stop);
        recorder.StartRecording();
        var changed = changes.ReadAsync(switchWait.Token).AsTask();
        try
        {
            if (await Task.WhenAny(changed, ended.Task) == ended.Task)
            {
                // Device removal can stop capture before Windows posts the default-output change.
                try { await changed.WaitAsync(TimeSpan.FromSeconds(1), stop); }
                catch (TimeoutException)
                {
                    throw new InvalidOperationException("Windows stopped capturing audio.", await ended.Task);
                }
            }
            await changed;
        }
        finally { await switchWait.CancelAsync(); }
    }
}
