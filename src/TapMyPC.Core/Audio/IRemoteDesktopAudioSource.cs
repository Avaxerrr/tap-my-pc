namespace TapMyPC.Core.Audio;

public interface IRemoteDesktopAudioSource
{
    // One raw Opus packet per frame, 48 kHz stereo, 20 ms.
    IAsyncEnumerable<ReadOnlyMemory<byte>> CaptureAsync(CancellationToken stop);
}
