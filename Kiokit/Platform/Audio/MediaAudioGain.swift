import AVFoundation
import AudioToolbox
import MediaToolbox

/// iOS audio binding for AVPlayer's decoded samples. Apple's peak limiter
/// supplies the same requested 6 dB pre-gain as the audio engine, without
/// changing imported files or Anki's tag queue.
enum MediaAudioGain {
    static func parameters(for track: AVAssetTrack, onProcessing: @escaping @Sendable (OSStatus, Float) -> Void) throws -> AVAudioMixInputParameters {
        let context = MediaAudioGainContext(onProcessing: onProcessing)
        let storage = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: storage,
            init: { _, clientInfo, output in output.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<MediaAudioGainContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                let context = MediaAudioGainContext.from(tap)
                context.prepare(tap: tap, maxFrames: UInt32(maxFrames), format: format.pointee)
            },
            unprepare: { tap in MediaAudioGainContext.from(tap).unprepare() },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                MediaAudioGainContext.from(tap).process(tap: tap, frames: frames, buffers: buffers, framesOut: framesOut, flagsOut: flagsOut)
            })
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        guard status == noErr, let tap else {
            Unmanaged<MediaAudioGainContext>.fromOpaque(storage).release()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        return parameters
    }
}

private final class MediaAudioGainContext: @unchecked Sendable {
    private var unit: AudioUnit?
    private var tap: Unmanaged<MTAudioProcessingTap>?
    private var sampleTime: Float64 = 0
    private var sourceFrames: CMItemCount = 0
    private var sourceFlags: MTAudioProcessingTapFlags = 0
    private var reportedProcessing = false
    private let onProcessing: @Sendable (OSStatus, Float) -> Void

    init(onProcessing: @escaping @Sendable (OSStatus, Float) -> Void) { self.onProcessing = onProcessing }

    static func from(_ tap: MTAudioProcessingTap) -> MediaAudioGainContext {
        Unmanaged<MediaAudioGainContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    func prepare(tap: MTAudioProcessingTap, maxFrames: UInt32, format: AudioStreamBasicDescription) {
        unprepare()
        self.tap = .passUnretained(tap)
        sampleTime = 0
        reportedProcessing = false
        var description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { onProcessing(kAudio_ParamError, 0); return }
        var created: AudioUnit?
        var status = AudioComponentInstanceNew(component, &created)
        guard status == noErr, let created else { onProcessing(status, 0); return }
        unit = created
        var format = format
        var maxFrames = maxFrames
        var callback = AURenderCallbackStruct(inputProc: { storage, _, _, _, frames, buffers in
            let context = Unmanaged<MediaAudioGainContext>.fromOpaque(storage).takeUnretainedValue()
            guard let tap = context.tap?.takeUnretainedValue(), let buffers else { return kAudio_ParamError }
            return MTAudioProcessingTapGetSourceAudio(tap, CMItemCount(frames), buffers, &context.sourceFlags, nil, &context.sourceFrames)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        for scope in [kAudioUnitScope_Input, kAudioUnitScope_Output] {
            status = AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat, scope, 0, &format, UInt32(MemoryLayout.size(ofValue: format)))
            guard status == noErr else { onProcessing(status, 0); unprepare(); return }
        }
        status = AudioUnitSetProperty(created, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, UInt32(MemoryLayout.size(ofValue: maxFrames)))
        guard status == noErr else { onProcessing(status, 0); unprepare(); return }
        status = AudioUnitSetProperty(created, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout.size(ofValue: callback)))
        guard status == noErr else { onProcessing(status, 0); unprepare(); return }
        status = AudioUnitSetParameter(created, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 6, 0)
        guard status == noErr else { onProcessing(status, 0); unprepare(); return }
        status = AudioUnitInitialize(created)
        if status != noErr { onProcessing(status, 0); unprepare() }
    }

    func process(tap: MTAudioProcessingTap, frames: CMItemCount, buffers: UnsafeMutablePointer<AudioBufferList>, framesOut: UnsafeMutablePointer<CMItemCount>, flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
        guard let unit else {
            let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
            if status != noErr { framesOut.pointee = 0 }
            return
        }
        sourceFrames = 0
        sourceFlags = 0
        var time = AudioTimeStamp()
        time.mSampleTime = sampleTime
        time.mFlags = .sampleTimeValid
        var flags: AudioUnitRenderActionFlags = []
        let status = AudioUnitRender(unit, &flags, &time, 0, UInt32(frames), buffers)
        framesOut.pointee = status == noErr ? sourceFrames : 0
        flagsOut.pointee = sourceFlags
        sampleTime += Float64(framesOut.pointee)
        if !reportedProcessing && (sourceFrames > 0 || status != noErr) {
            reportedProcessing = true
            var gain: AudioUnitParameterValue = 0
            let gainStatus = AudioUnitGetParameter(unit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, &gain)
            onProcessing(status == noErr ? gainStatus : status, gain)
        }
    }

    func unprepare() {
        if let unit { AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }
        unit = nil
        tap = nil
    }
}
