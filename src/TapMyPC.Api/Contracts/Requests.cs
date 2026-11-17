using TapMyPC.Core.Devices;
using System.Text.Json.Serialization;

namespace TapMyPC.Api.Contracts;

public record PairRequest(string? Code, string? Name);
public record VolumeRequest([property: JsonRequired] int Volume);
public record MuteRequest([property: JsonRequired] bool Muted);
public record VolumeStepRequest([property: JsonRequired] VolumeDirection Direction);
public record MediaRequest([property: JsonRequired] MediaAction Action);
public record PowerRequest([property: JsonRequired] PowerAction Action, [property: JsonRequired] int DelaySeconds, [property: JsonRequired] bool Confirmed);
