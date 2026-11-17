namespace TapMyPC.Core.Audio;

public record AudioOutput(string Id, string Name, bool IsDefault);
public interface IAudioOutputController
{
    IReadOnlyList<AudioOutput> List();
    void Select(string id);
}
